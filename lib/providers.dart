import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'models.dart';
import 'constants.dart';

const _uuid = Uuid();

class CanvasState {
  final List<ProductionNode> nodes;
  final List<Connection> connections;
  final bool isConnecting;
  final String? sourceNodeId;
  final String? sourcePortId;
  final Offset? connectionStartPos;
  final Offset? connectionCurrentPos;
  final bool isSignalConnecting; // [新增] 信号连接状态
  final String? signalSourceNodeId; // [新增] 信号源节点ID
  final String? signalSourcePortId; // [新增] 信号源端口ID
  final String? activeDragSourceNodeId; // [新增] 拖拽源节点ID
  final String? activeDragSourcePortId; // [新增] 拖拽源端口ID
  final Offset? activeDragCurrentPosition; // [新增] 拖拽当前位置
  final bool isSimulating; // [新增] 模拟状态
  final DragType activeDragType; // [Fix] 新增拖拽类型标识
  final bool isConnectionValid; // [新增] 连接是否有效（是否连接到目标节点）

  CanvasState({
    this.nodes = const [],
    this.connections = const [],
    this.isConnecting = false,
    this.sourceNodeId,
    this.sourcePortId,
    this.connectionStartPos,
    this.connectionCurrentPos,
    this.isSignalConnecting = false, // [新增]
    this.signalSourceNodeId, // [新增]
    this.signalSourcePortId, // [新增]
    this.activeDragSourceNodeId, // [新增]
    this.activeDragSourcePortId, // [新增]
    this.activeDragCurrentPosition, // [新增]
    this.isSimulating = true, // [新增]
    this.activeDragType = DragType.none, // [Fix] 新增拖拽类型标识
    this.isConnectionValid = false, // [新增] 连接是否有效（是否连接到目标节点）
  });

  CanvasState copyWith({
    List<ProductionNode>? nodes,
    List<Connection>? connections,
    bool? isConnecting,
    String? sourceNodeId,
    String? sourcePortId,
    Offset? connectionStartPos,
    Offset? connectionCurrentPos,
    bool? isSignalConnecting,
    String? signalSourceNodeId,
    String? signalSourcePortId,
    String? activeDragSourceNodeId,
    String? activeDragSourcePortId,
    Offset? activeDragCurrentPosition,
    bool? isSimulating,
    bool clearDrag = false, 
    DragType? activeDragType, 
    bool? isConnectionValid, 
  }) {
    return CanvasState(
      nodes: nodes ?? this.nodes,
      connections: connections ?? this.connections,
      isConnecting: isConnecting ?? this.isConnecting,
      sourceNodeId: sourceNodeId ?? this.sourceNodeId,
      sourcePortId: sourcePortId ?? this.sourcePortId,
      connectionStartPos: connectionStartPos ?? this.connectionStartPos,
      connectionCurrentPos: connectionCurrentPos ?? this.connectionCurrentPos,
      isSignalConnecting: isSignalConnecting ?? this.isSignalConnecting,
      signalSourceNodeId: signalSourceNodeId ?? this.signalSourceNodeId,
      signalSourcePortId: signalSourcePortId ?? this.signalSourcePortId,
      // [核心修复] 必须显式处理 clearDrag 时的 null 覆盖，防止 ?? 操作符保留脏数据
      activeDragSourceNodeId: clearDrag ? null : (activeDragSourceNodeId ?? this.activeDragSourceNodeId),
      activeDragSourcePortId: clearDrag ? null : (activeDragSourcePortId ?? this.activeDragSourcePortId),
      activeDragCurrentPosition: clearDrag ? null : (activeDragCurrentPosition ?? this.activeDragCurrentPosition),
      isSimulating: isSimulating ?? this.isSimulating,
      activeDragType: clearDrag ? DragType.none : (activeDragType ?? this.activeDragType),
      isConnectionValid: isConnectionValid ?? this.isConnectionValid,
    );
  }
}

class CanvasNotifier extends Notifier<CanvasState> {
  Timer? _syncTimer;

  @override
  CanvasState build() => CanvasState();

  // 后端网关地址 (Debian 13 本机或服务器地址)
  static const String BACKEND_URL = 'http://127.0.0.1:8080';

  // [修改] 启停控制交由后端管理，前端仅同步状态
  Future<void> toggleSimulation() async {
    final newState = !state.isSimulating;
    try {
      await http.post(Uri.parse('$BACKEND_URL/api/simulation/start'));
      state = state.copyWith(isSimulating: newState);
      
      if (newState) {
        // 启动轮询同步 (工程环境中建议替换为 WebSocket)
        _syncTimer = Timer.periodic(const Duration(milliseconds: 100), _syncStateFromBackend);
      } else {
        _syncTimer?.cancel();
      }
    } catch (e) {
      print("后端通信失败: $e");
    }
  }

  // [新增] 从后端线性逻辑引擎获取真实推演结果
  Future<void> _syncStateFromBackend(Timer timer) async {
    try {
      final response = await http.get(Uri.parse('$BACKEND_URL/api/simulation/state'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // 解析后端返回的 Diagram 状态，映射到前端的可视化 Nodes / Connections
        // 注：保留了原有的 UI 渲染模型，仅在此处做状态映射
        final updatedNodes = (data['nodes'] as List).map((e) => ProductionNode.fromJson(e)).toList();
        state = state.copyWith(nodes: updatedNodes);
      }
    } catch (e) {
      // 容错处理
    }
  }

  // [新增] 信号连接处理方法
  void finalizeSignalConnection(String targetNodeId, String targetPortId) {
    // 获取当前拖拽的信号端口ID
    final sourceInfo = state.activeDragSourceNodeId?.split(':');
    if (sourceInfo != null && sourceInfo.length == 3 && sourceInfo[0] == "SIG") {
      final sourceNodeId = sourceInfo[1];
      final sourcePortId = sourceInfo[2];
      
      // 创建信号类型的连接
      final newConnection = Connection(
        sourceNodeId: sourceNodeId,
        sourcePortId: sourcePortId,
        targetNodeId: targetNodeId,
        targetPortId: targetPortId,
        type: ConnectionType.signal, // 标记为信号连接
      );
      
      final newConnections = List<Connection>.from(state.connections)..add(newConnection);
      state = state.copyWith(connections: newConnections);
    }
  }

  /// 执行一回合的逻辑自动化控制指令
  void executeLogicTick() {
    final logicNodes = state.nodes.where((n) => 
        n.category == ProcessCategory.control && 
        n.logicTargetNodeId != null && 
        n.logicAction != null);

    List<ProductionNode> nextNodes = List.from(state.nodes);

    for (var logicNode in logicNodes) {
      bool conditionMet = true;
      if (logicNode.logicCondition != null && logicNode.conditionValue != null) {
        conditionMet = _evaluateCondition(logicNode, state.nodes);
      }
      
      if (conditionMet) {
        final targetId = logicNode.logicTargetNodeId;
        final action = logicNode.logicAction;
        
        // [核心修复 1.1] 修复短 ID 匹配问题，兼容用户输入的截断 ID 与底层 UUID
        final targetIndex = nextNodes.indexWhere((node) => targetId != null && (node.id.startsWith(targetId) || targetId.startsWith(node.id)));
        
        if (targetIndex == -1) {
          print('Debug: 无法通过输入的短 ID [$targetId] 找到目标节点');
          continue;
        }

        ProductionNode targetNode = nextNodes[targetIndex];
        int originalStackCount = targetNode.stackCount;

        switch (action) {
          case 'build':
            if (!targetNode.isBuilt) {
              // 检查目标节点的建设资源需求（使用目标节点的constructionCost）
              // 但检查资源是否存在于蓝图节点的输入库存中
              bool hasResources = _checkBlueprintConstructionResourcesForTarget(logicNode, targetNode);
              if (!hasResources) {
                continue; // 没有足够资源，跳过此操作
              }
              
              // 消耗蓝图节点的建设资源（使用目标节点的constructionCost）
              ProductionNode updatedTargetNode = _consumeBlueprintConstructionResourcesForTarget(logicNode, targetNode);
              nextNodes[targetIndex] = updatedTargetNode.copyWith(
                isBuilt: true, 
                isRunning: false,
                stackCount: originalStackCount // 保持原始堆叠数量
              );
            }
            break;
            
          case 'stack':
            // 查找实际的目标节点（使用完整的ID匹配）
            final actualTargetNode = state.nodes.firstWhere(
              (n) => n.id == targetNode.id, 
              orElse: () => targetNode,
            );
            
            // 检查逻辑节点是否有足够的资源来执行操作（使用实际目标节点的constructionCost）
            bool hasResources = _checkConstructionResources(logicNode, actualTargetNode);
            if (!hasResources) {
              continue; // 没有足够资源，跳过此操作
            }
            
            // 消耗扩容所需的资源（使用实际目标节点的constructionCost）
            ProductionNode updatedLogicNode = _consumeConstructionResources(logicNode, actualTargetNode);
            int logicNodeIndex = nextNodes.indexWhere((n) => n.id == logicNode.id);
            nextNodes[logicNodeIndex] = updatedLogicNode;
            
            nextNodes[targetIndex] = targetNode.copyWith(
              stackCount: targetNode.stackCount + 1,
              isBuilt: true 
            );
            break;
            
          case 'unstack':
            if (targetNode.stackCount > 0) {
              int newStackCount = targetNode.stackCount - 1;
              nextNodes[targetIndex] = targetNode.copyWith(
                stackCount: newStackCount,
                isBuilt: newStackCount > 0 ? targetNode.isBuilt : false
              );
            }
            break;
            
          case 'dismantle':
            if (targetNode.stackCount > 1) {
              nextNodes[targetIndex] = targetNode.copyWith(stackCount: targetNode.stackCount - 1);
            } else {
              nextNodes[targetIndex] = targetNode.copyWith(
                isBuilt: false,
                isRunning: false,
                stackCount: originalStackCount > 1 ? originalStackCount - 1 : 1, // 保持原始堆叠数量的逻辑
              );
            }
            break;
            
          case 'start':
            if (targetNode.isBuilt && !targetNode.isRunning) {
              nextNodes[targetIndex] = targetNode.copyWith(isRunning: true);
            }
            break;
            
          case 'stop':
            if (targetNode.isBuilt && targetNode.isRunning) {
              nextNodes[targetIndex] = targetNode.copyWith(isRunning: false);
            }
            break;
        }
      }
    }
    state = state.copyWith(nodes: nextNodes);
  }
  
  /// 评估逻辑条件是否满足
  bool _evaluateCondition(ProductionNode logicNode, List<ProductionNode> allNodes) {
    if (logicNode.logicCondition == null || logicNode.conditionValue == null) return true;
    
    // [核心修复 1.2] 条件判断目标 ID 同样需要支持短 ID 前缀匹配
    ProductionNode? targetNode = logicNode;
    if (logicNode.conditionTargetNodeId != null && logicNode.conditionTargetNodeId!.isNotEmpty) {
      targetNode = allNodes.where((n) => n.id.startsWith(logicNode.conditionTargetNodeId!)).firstOrNull ?? logicNode;
    }
    
    // ... 下游的条件值获取保留不变 ...
    var portValue = 0.0;
    if (logicNode.conditionPortId != null) {
      // 检查输入端口
      final inputPort = targetNode.inputs.firstWhere((p) => p.id == logicNode.conditionPortId, orElse: () => InputPort(itemName: 'default'));
      if (inputPort.id != 'default') {
        portValue = targetNode.inputInventory[inputPort.id] ?? 0.0;
      } else {
        // 检查输出端口
        final outputPort = targetNode.outputs.firstWhere((p) => p.id == logicNode.conditionPortId, orElse: () => OutputPort(itemName: 'default'));
        if (outputPort.id != 'default') {
          portValue = targetNode.outputInventory[outputPort.id] ?? 0.0;
        }
      }
    } else {
      // 没有任何端口时取节点全局仓储总和
      portValue = (targetNode.inputInventory.values.fold(0.0, (a,b)=>a+b)) + 
                  (targetNode.outputInventory.values.fold(0.0, (a,b)=>a+b));
    }
    
    // ... 下游的条件阈值返回保留不变 ...
    switch (logicNode.logicCondition) {
      case 'greater_than':
        return portValue > (logicNode.conditionValue ?? 0);
      case 'less_than':
        return portValue < (logicNode.conditionValue ?? 0);
      case 'greater_equal':
        return portValue >= (logicNode.conditionValue ?? 0);
      case 'less_equal':
        return portValue <= (logicNode.conditionValue ?? 0);
      case 'equal':
        return portValue == (logicNode.conditionValue ?? 0);
      case 'not_equal':
        return portValue != (logicNode.conditionValue ?? 0);
      case 'running':
        return targetNode.isRunning;
      case 'not_running':
        return !targetNode.isRunning;
      case 'built':
        return targetNode.isBuilt;
      case 'not_built':
        return !targetNode.isBuilt;
      default:
        return true;
    }
  }

  /// 检查是否有足够的建设资源
  bool _checkConstructionResources(ProductionNode logicNode, ProductionNode targetNode) {
    // 检查逻辑节点的输入库存是否包含建设目标节点所需的资源
    for (final entry in targetNode.constructionCost.entries) {
      final resourceName = entry.key;
      final requiredAmount = entry.value;
      
      // 在逻辑节点的输入库存中查找对应资源
      double availableAmount = 0.0;
      for (final inputPort in logicNode.inputs) {
        if (inputPort.itemName == resourceName) {
          availableAmount = logicNode.inputInventory[inputPort.id] ?? 0.0;
          break;
        }
      }
      
      if (availableAmount < requiredAmount) {
        return false; // 资源不足
      }
    }
    return true; // 资源充足
  }

  /// 消耗建设资源并返回更新后的逻辑节点
  ProductionNode _consumeConstructionResources(ProductionNode logicNode, ProductionNode targetNode) {
    // 从逻辑节点的输入库存中消耗建设资源
    final updatedInputInventory = Map<String, double>.from(logicNode.inputInventory);
    
    for (final entry in targetNode.constructionCost.entries) {
      final resourceName = entry.key;
      final requiredAmount = entry.value;
      
      // 在逻辑节点的输入库存中查找对应资源并消耗
      for (final inputPort in logicNode.inputs) {
        if (inputPort.itemName == resourceName) {
          final currentAmount = updatedInputInventory[inputPort.id] ?? 0.0;
          final newAmount = (currentAmount - requiredAmount).clamp(0.0, double.infinity);
          updatedInputInventory[inputPort.id] = newAmount;
          break;
        }
      }
    }
    
    // 返回更新后的逻辑节点
    return logicNode.copyWith(inputInventory: updatedInputInventory);
  }
  
  /// 检查蓝图节点是否有足够的建设资源（从其输入端口获取）
  bool _checkBlueprintConstructionResources(ProductionNode blueprintNode) {
    // 检查蓝图节点的输入库存是否包含建设所需的资源
    for (final entry in blueprintNode.constructionCost.entries) {
      final resourceName = entry.key;
      final requiredAmount = entry.value;
      
      // 在蓝图节点的输入库存中查找对应资源
      double availableAmount = 0.0;
      for (final inputPort in blueprintNode.inputs) {
        if (inputPort.itemName == resourceName) {
          availableAmount = blueprintNode.inputInventory[inputPort.id] ?? 0.0;
          break;
        }
      }
      
      if (availableAmount < requiredAmount) {
        return false; // 资源不足
      }
    }
    return true; // 资源充足
  }

  /// 消耗蓝图节点的建设资源
  ProductionNode _consumeBlueprintConstructionResources(ProductionNode blueprintNode) {
    // 从蓝图节点的输入库存中消耗建设资源
    final updatedInputInventory = Map<String, double>.from(blueprintNode.inputInventory);
    
    for (final entry in blueprintNode.constructionCost.entries) {
      final resourceName = entry.key;
      final requiredAmount = entry.value;
      
      // 在蓝图节点的输入库存中查找对应资源并消耗
      for (final inputPort in blueprintNode.inputs) {
        if (inputPort.itemName == resourceName) {
          final currentAmount = updatedInputInventory[inputPort.id] ?? 0.0;
          final newAmount = (currentAmount - requiredAmount).clamp(0.0, double.infinity);
          updatedInputInventory[inputPort.id] = newAmount;
          break;
        }
      }
    }
    
    // 返回更新后的蓝图节点
    return blueprintNode.copyWith(inputInventory: updatedInputInventory);
  }
  
  /// 检查蓝图节点是否有足够的建设资源（从其输入端口获取）用于目标节点
  bool _checkBlueprintConstructionResourcesForTarget(ProductionNode blueprintNode, ProductionNode targetNode) {
    // 检查蓝图节点的输入库存是否包含目标节点建设所需的资源
    for (final entry in targetNode.constructionCost.entries) {
      final resourceName = entry.key;
      final requiredAmount = entry.value;
      
      // 在蓝图节点的输入库存中查找对应资源
      double availableAmount = 0.0;
      for (final inputPort in blueprintNode.inputs) {
        if (inputPort.itemName == resourceName) {
          availableAmount = blueprintNode.inputInventory[inputPort.id] ?? 0.0;
          break;
        }
      }
      
      if (availableAmount < requiredAmount) {
        return false; // 资源不足
      }
    }
    return true; // 资源充足
  }

  /// 消耗蓝图节点的建设资源用于目标节点
  ProductionNode _consumeBlueprintConstructionResourcesForTarget(ProductionNode blueprintNode, ProductionNode targetNode) {
    // 从蓝图节点的输入库存中消耗建设资源
    final updatedInputInventory = Map<String, double>.from(blueprintNode.inputInventory);
    
    for (final entry in targetNode.constructionCost.entries) {
      final resourceName = entry.key;
      final requiredAmount = entry.value;
      
      // 在蓝图节点的输入库存中查找对应资源并消耗
      for (final inputPort in blueprintNode.inputs) {
        if (inputPort.itemName == resourceName) {
          final currentAmount = updatedInputInventory[inputPort.id] ?? 0.0;
          final newAmount = (currentAmount - requiredAmount).clamp(0.0, double.infinity);
          updatedInputInventory[inputPort.id] = newAmount;
          break;
        }
      }
    }
    
    // 返回更新后的蓝图节点
    return blueprintNode.copyWith(inputInventory: updatedInputInventory);
  }

  void addNode(ProductionNode node) {
    // 总是添加新节点，而不是检查是否已存在相同类型的节点
    state = state.copyWith(nodes:[...state.nodes, node]);
  }


  /// 切换污染物的"丢弃"状态
  void togglePollutantDiscard(String nodeId, String portId) {
    final updatedNodes = state.nodes.map((node) {
      if (node.id == nodeId) {
        final updatedOutputs = node.outputs.map((port) {
          if (port.id == portId && port.isPollutant) {
            return port.copyWith(isDiscarded: !port.isDiscarded);
          }
          return port;
        }).toList();
        return node.copyWith(outputs: updatedOutputs);
      }
      return node;
    }).toList();
    state = state.copyWith(nodes: updatedNodes);
  }

  /// 更新节点基础属性
  void updateNodeProperties(String nodeId, {String? newName, ProcessCategory? newCategory}) {
    final updatedNodes = state.nodes.map((node) {
      if (node.id == nodeId) {
        return node.copyWith(name: newName, category: newCategory);
      }
      return node;
    }).toList();
    state = state.copyWith(nodes: updatedNodes);
  }

  /// 删除节点及其相关的连线
  void removeNode(String nodeId) {
    // 使用完整ID精确匹配来删除节点，避免短ID匹配问题
    final updatedNodes = state.nodes.where((n) => n.id != nodeId).toList();
    final updatedConnections = state.connections.where((c) => 
        c.sourceNodeId != nodeId && c.targetNodeId != nodeId).toList();
    
    state = state.copyWith(nodes: updatedNodes, connections: updatedConnections);
  }

  /// [修复] 完整更新节点 (包含端口级联清理机制)
  void updateNodeComplete(String nodeId, ProductionNode updatedNode) {
    // 萃取新节点中存留的有效端口ID
    final validPortIds =[
      ...updatedNode.inputs.map((p) => p.id),
      ...updatedNode.outputs.map((p) => p.id)
    ].toSet();

    // 过滤掉引用了已删除端口的游离连接
    final updatedConnections = state.connections.where((c) {
      if (c.sourceNodeId == nodeId && !validPortIds.contains(c.sourcePortId)) return false;
      if (c.targetNodeId == nodeId && !validPortIds.contains(c.targetPortId)) return false;
      return true;
    }).toList();

    final updatedNodes = state.nodes.map((n) => n.id == nodeId ? updatedNode : n).toList();
    state = state.copyWith(nodes: updatedNodes, connections: updatedConnections);
  }

  // ==========================================
  // [连线合法性校验] 严格同态连接 (Digital->Digital, Analog->Analog)
  // ==========================================
  void startConnectionDrag(String nodeId, String portId, [DragType? type]) {
    state = state.copyWith(
      activeDragSourceNodeId: nodeId,
      activeDragSourcePortId: portId,
      // [核心修复] 不要强制向下转型为宏观 DragType.signal，必须保留精准的 signalDigital 或 signalAnalog
      activeDragType: type ?? DragType.material,
      activeDragCurrentPosition: null,
    );
  }

  void updateConnectionDrag(Offset globalPosition) {
    // [Fix] 拖拽过程中直接更新位置，不再操作 isConnectionValid
    // isConnectionValid 仅由 DragTarget.onWillAccept 反馈写入
    state = state.copyWith(activeDragCurrentPosition: globalPosition);
  }

  void endConnectionDrag() {
    state = state.copyWith(
      clearDrag: true,
      isConnectionValid: false,
      // copyWith 中 clearDrag=true 会清除 activeDragSourceNodeId/PortId/Type
      // activeDragCurrentPosition 需要在 CanvasState.copyWith 中同步清除
    );
  }

  // [修改] 手工构造 Struct 时，向后端发送校验请求 (对应功能 2)
  Future<void> finalizeConnection(String targetNodeId, String targetPortId, DragType targetPortType) async {
    if (state.activeDragSourceNodeId == null || state.activeDragSourcePortId == null) return;

    final sourceType = state.activeDragType;

    // [Fix] 统一信号兼容性判断：digital/analog/signal 三者之间可互连，
    // material 仅与 material 互连，彻底修复因类型归并导致的连线失败问题。
    final bool sourceIsSignal = sourceType == DragType.signal ||
        sourceType == DragType.signalDigital || sourceType == DragType.signalAnalog;
    final bool targetIsSignal = targetPortType == DragType.signal ||
        targetPortType == DragType.signalDigital || targetPortType == DragType.signalAnalog;

    final bool typesCompatible = (sourceIsSignal && targetIsSignal) ||
        (sourceType == DragType.material && targetPortType == DragType.material);

    if (!typesCompatible) {
      endConnectionDrag();
      return;
    }

    if (state.activeDragSourceNodeId == targetNodeId) {
      endConnectionDrag();
      return;
    }

    final newConn = Connection(
      sourceNodeId: state.activeDragSourceNodeId!,
      sourcePortId: state.activeDragSourcePortId!,
      targetNodeId: targetNodeId,
      targetPortId: targetPortId,
      type: sourceIsSignal ? ConnectionType.signal : ConnectionType.material,
    );

    // 发送至后端验证是否符合割公理及线性逻辑约束
    try {
      final res = await http.post(
        Uri.parse('$BACKEND_URL/api/structs/manual'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(newConn.toJson()),
      );
      if (jsonDecode(res.body)['status'] == 'verified') {
        state = state.copyWith(
          connections: [...state.connections, newConn],
          clearDrag: true,
        );
      } else {
        // 违背逻辑，拒绝连接
        endConnectionDrag();
      }
    } catch (e) {
      endConnectionDrag();
    }
  }

  // 添加一个方法来处理拖拽取消
  void cancelConnectionDrag() {
    if (state.activeDragSourceNodeId != null) {
      // 如果有活动的拖拽但没有连接到任何节点，则清除拖拽状态
      state = state.copyWith(
        isConnectionValid: false, // 连接无效
        clearDrag: true
      );
    }
  }

  // [Fix] 仅用于 DragTarget 悬停时的视觉高亮反馈，不参与绘制逻辑门控
  void setConnectionHoverValid(bool valid) {
    state = state.copyWith(isConnectionValid: valid);
  }

  /// 获取图论分析器
  GraphAnalyzer getAnalyzer() => GraphAnalyzer(state.nodes, state.connections);

  /// 导出为 JSON 文件
  Future<void> exportToFile(String filePath) async {
    final Map<String, dynamic> data = {
      'nodes': state.nodes.map((n) => n.toJson()).toList(),
      'connections': state.connections.map((c) => c.toJson()).toList(),
    };
    final file = File(filePath);
    await file.writeAsString(jsonEncode(data));
  }

  /// 从 JSON 文件导入
  Future<void> importFromFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) throw Exception("文件不存在");
    
    final content = await file.readAsString();
    final data = jsonDecode(content);
    
    final importedNodes = (data['nodes'] as List).map((e) => ProductionNode.fromJson(e)).toList();
    final importedConns = (data['connections'] as List).map((e) => Connection.fromJson(e)).toList();
    
    // 覆盖当前画布状态
    state = CanvasState(nodes: importedNodes, connections: importedConns);
  }

  /// 从 JSON 字符串导入
  Future<void> importFromJsonString(String jsonString) async {
    try {
      final data = jsonDecode(jsonString);
      
      final importedNodes = (data['nodes'] as List).map((e) => ProductionNode.fromJson(e)).toList();
      final importedConns = (data['connections'] as List).map((e) => Connection.fromJson(e)).toList();
      
      // 覆盖当前画布状态
      state = CanvasState(nodes: importedNodes, connections: importedConns);
    } catch (e) {
      throw Exception("JSON格式错误: $e");
    }
  }

  /// 更新节点位置
  void updateNodePosition(String nodeId, Offset delta) {
    final nodeIndex = state.nodes.indexWhere((n) => n.id == nodeId);
    if (nodeIndex == -1) return;

    var activeNode = state.nodes[nodeIndex];
    double newDx = activeNode.position.dx + delta.dx;
    double newDy = activeNode.position.dy + delta.dy;
    activeNode = activeNode.copyWith(position: Offset(newDx, newDy));

    List<ProductionNode> newNodes = List.from(state.nodes);
    newNodes[nodeIndex] = activeNode;
    List<Connection> updatedConns = List.from(state.connections);

    const double cardWidth = 260.0;
    const double cardHeight = 220.0;

    for (int i = 0; i < newNodes.length; i++) {
      if (i == nodeIndex) continue;
      var otherNode = newNodes[i];

      Rect rectActive = Rect.fromLTWH(activeNode.position.dx, activeNode.position.dy, cardWidth, cardHeight);
      Rect rectOther = Rect.fromLTWH(otherNode.position.dx, otherNode.position.dy, cardWidth, cardHeight);

      if (rectActive.overlaps(rectOther)) {
        bool isSameKind = (activeNode.category == otherNode.category && activeNode.name == otherNode.name);
        
        // [Fix] 仅保留同类卡片的吸附合并逻辑，彻底删除了导致卡片乱飞、死锁失控的 physical push (排斥力) 算法。
        // 现在多张卡片允许安全地物理重叠，不再干涉拖拽手势。
        if (isSameKind && (rectActive.center - rectOther.center).distance < 50.0) {
          // [修复] 保留原始堆叠数量，而不是简单相加
          int originalStackCount = activeNode.stackCount;
          activeNode = activeNode.copyWith(stackCount: originalStackCount + otherNode.stackCount);
          newNodes[nodeIndex] = activeNode;
          
          String oldId = otherNode.id;
          String newId = activeNode.id;
          newNodes.removeAt(i);
          
          updatedConns = updatedConns.map((conn) {
            if (conn.sourceNodeId == oldId) {
              var oldPort = otherNode.outputs.firstWhere((p) => p.id == conn.sourcePortId);
              var newPort = activeNode.outputs.firstWhere((p) => p.itemName == oldPort.itemName, orElse: () => activeNode.outputs.first);
              return Connection(id: conn.id, sourceNodeId: newId, sourcePortId: newPort.id, targetNodeId: conn.targetNodeId, targetPortId: conn.targetPortId);
            }
            if (conn.targetNodeId == oldId) {
              var oldPort = otherNode.inputs.firstWhere((p) => p.id == conn.targetPortId);
              var newPort = activeNode.inputs.firstWhere((p) => p.itemName == oldPort.itemName, orElse: () => activeNode.inputs.first);
              return Connection(id: conn.id, sourceNodeId: conn.sourceNodeId, sourcePortId: conn.sourcePortId, targetNodeId: newId, targetPortId: newPort.id);
            }
            return conn;
          }).toList();
          break; 
        }
      }
    }
    state = state.copyWith(nodes: newNodes, connections: updatedConns);
  }

  /// [Feature] 新增：上帝模式的资源干预操作 (填充/排空)
  void setInventory(String nodeId, String portId, bool isInput, double amount) {
    final nodeIndex = state.nodes.indexWhere((n) => n.id == nodeId);
    if (nodeIndex == -1) return;

    var node = state.nodes[nodeIndex];
    if (isInput) {
      final newInv = Map<String, double>.from(node.inputInventory);
      newInv[portId] = amount;
      state = state.copyWith(nodes: List.from(state.nodes)..[nodeIndex] = node.copyWith(inputInventory: newInv));
    } else {
      final newInv = Map<String, double>.from(node.outputInventory);
      newInv[portId] = amount;
      state = state.copyWith(nodes: List.from(state.nodes)..[nodeIndex] = node.copyWith(outputInventory: newInv));
    }
  }

  void dispose() {
    _syncTimer?.cancel();
  }
}

final canvasProvider = NotifierProvider<CanvasNotifier, CanvasState>(() => CanvasNotifier());

/// 图论引擎
class GraphAnalyzer {
  final List<ProductionNode> nodes;
  final List<Connection> connections;

  GraphAnalyzer(this.nodes, this.connections);

  /// 验证整个DAG的合法性
  List<String> validateNetwork() {
    List<String> warnings =[];
    
    for (var node in nodes) {
      // 检查输入端口是否断链
      for (var input in node.inputs) {
        if (input.isRequired && !connections.any((c) => c.targetPortId == input.id)) {
          warnings.add("节点[${node.name}]的输入[${input.itemName}]未连接原料。");
        }
      }
      
      // 检查负外部性污染物
      for (var output in node.outputs) {
        if (output.isPollutant) {
          bool isConnected = connections.any((c) => c.sourcePortId == output.id);
          if (!isConnected && !output.isDiscarded) {
            warnings.add("违规: 节点[${node.name}]的污染物[${output.itemName}]未处理且未确认丢弃！");
          } else if (!isConnected && output.isDiscarded) {
            warnings.add("警告: 节点[${node.name}]的污染物[${output.itemName}]直接向环境排放。");
          }
        }
      }
    }
    return warnings;
  }
}