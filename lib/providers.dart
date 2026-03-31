import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models.dart';
import 'dart:convert';
import 'dart:io';

/// 画布整体状态
class CanvasState {
  final List<ProductionNode> nodes;
  final List<Connection> connections;
  final bool isSimulating; //[新增] 模拟器运行状态
  // 拖拽连线状态
  final String? activeDragSourceNodeId;
  final String? activeDragSourcePortId;
  final Offset? activeDragCurrentPosition;

  CanvasState({
    this.nodes = const [],
    this.connections = const[],
    this.isSimulating = false,
    this.activeDragSourceNodeId,
    this.activeDragSourcePortId,
    this.activeDragCurrentPosition,
  });

  CanvasState copyWith({
    List<ProductionNode>? nodes,
    List<Connection>? connections,
    bool? isSimulating,
    String? activeDragSourceNodeId,
    String? activeDragSourcePortId,
    Offset? activeDragCurrentPosition,
    bool clearDrag = false, // 显式清除拖拽状态标志
  }) {
    return CanvasState(
      nodes: nodes ?? this.nodes,
      connections: connections ?? this.connections,
      isSimulating: isSimulating ?? this.isSimulating,
      activeDragSourceNodeId: clearDrag ? null : (activeDragSourceNodeId ?? this.activeDragSourceNodeId),
      activeDragSourcePortId: clearDrag ? null : (activeDragSourcePortId ?? this.activeDragSourcePortId),
      activeDragCurrentPosition: clearDrag ? null : (activeDragCurrentPosition ?? this.activeDragCurrentPosition),
    );
  }
}

class CanvasNotifier extends Notifier<CanvasState> {
  Timer? _simTimer;
  Timer? _logicTimer; // [新增] 专门负责逻辑节点的自动化触发时钟

  @override
  CanvasState build() => CanvasState();

  // [修复 2] 自动化指令深度融合入系统生命周期
  void toggleSimulation() {
    if (state.isSimulating) {
      _simTimer?.cancel();
      _logicTimer?.cancel();
      state = state.copyWith(isSimulating: false);
    } else {
      state = state.copyWith(isSimulating: true);
      _simTimer = Timer.periodic(const Duration(milliseconds: 100), _simTick);
      // 以 1 秒为逻辑运算的默认周期，防止无消耗条件的指令在 100ms 级别内暴走堆叠
      _logicTimer = Timer.periodic(const Duration(seconds: 1), (_) => executeLogicTick());
    }
  }

  // [新增] 核心时序调度引擎 (Tick)
  void _simTick(Timer timer) {
    const double dt = 0.1; 
    Map<String, Map<String, double>> nextInputInv = {};
    Map<String, Map<String, double>> nextOutputInv = {};

    for (var node in state.nodes) {
      nextInputInv[node.id] = Map.from(node.inputInventory);
      nextOutputInv[node.id] = Map.from(node.outputInventory);
    }

    // 2. 网络流转阶段
    for (var conn in state.connections) {
      final sNode = state.nodes.where((n) => n.id == conn.sourceNodeId).firstOrNull;
      final tNode = state.nodes.where((n) => n.id == conn.targetNodeId).firstOrNull;
      if (sNode == null || tNode == null) continue;

      // [Fix] 处于未建设(蓝图)状态的节点不允许参与管线物料传输
      if (!sNode.isBuilt || !tNode.isBuilt) continue;

      // ... 原有传输计算逻辑保留 ...
      final outPort = sNode.outputs.where((p) => p.id == conn.sourcePortId).firstOrNull;
      final inPort = tNode.inputs.where((p) => p.id == conn.targetPortId).firstOrNull;
      if (outPort == null || inPort == null) continue;

      double available = nextOutputInv[sNode.id]![outPort.id] ?? 0.0;
      double maxTransfer = outPort.rate * dt; 
      double targetSpace = tNode.maxCapacity - (nextInputInv[tNode.id]![inPort.id] ?? 0.0);

      double transferAmount = [available, maxTransfer, targetSpace].reduce(min);
      if (transferAmount > 0) {
        nextOutputInv[sNode.id]![outPort.id] = available - transferAmount;
        nextInputInv[tNode.id]![inPort.id] = (nextInputInv[tNode.id]![inPort.id] ?? 0.0) + transferAmount;
      }
    }

    // 3. 节点处理与状态判定阶段
    List<ProductionNode> nextNodes =[];
    for (var node in state.nodes) {
      if (!node.isBuilt || !node.isRunning) {
        nextNodes.add(node.copyWith(
          inputInventory: nextInputInv[node.id],
          outputInventory: nextOutputInv[node.id],
          status: NodeStatus.idle,
        ));
        continue;
      }

      bool isStarved = false;
      bool isBlocked = false;

      // [Fix] 仓储节点不属于生产加工设备，剥离其缺料(Starved)判定
      if (node.category != ProcessCategory.storing) {
        for (var inPort in node.inputs) {
          if ((nextInputInv[node.id]![inPort.id] ?? 0.0) < inPort.rate * dt) {
            isStarved = true; break;
          }
        }
      }

      if (!isStarved) {
        for (var outPort in node.outputs) {
          double inv = nextOutputInv[node.id]![outPort.id] ?? 0.0;
          if (inv + outPort.rate * dt > node.maxCapacity && !outPort.isDiscarded) {
            isBlocked = true; break;
          }
        }
      }

      NodeStatus nextStatus;
      double nextProgress = node.progress;

      if (isStarved) {
        nextStatus = NodeStatus.starved;
      } else if (isBlocked) {
        nextStatus = NodeStatus.blocked;
      } else {
        nextStatus = NodeStatus.running;
        
        if (node.category == ProcessCategory.storing) {
          // [Fix] 仓储专属逻辑：将输入库存自动流转至同名输出库存，无配方消耗，仅作缓冲
          for (var inPort in node.inputs) {
            double currentInv = nextInputInv[node.id]![inPort.id] ?? 0.0;
            if (currentInv > 0) {
              // 寻找是否存在同名的输出端口
              var outPort = node.outputs.firstWhere(
                (p) => p.itemName == inPort.itemName, 
                orElse: () => OutputPort(itemName: '')
              );
              if (outPort.itemName.isNotEmpty) {
                nextInputInv[node.id]![inPort.id] = 0.0; // 入库转移
                nextOutputInv[node.id]![outPort.id] = (nextOutputInv[node.id]![outPort.id] ?? 0.0) + currentInv;
              }
            }
          }
        } else {
          // 原有配方转化逻辑：按设备堆叠倍数消耗输入，产生输出
          nextProgress = (nextProgress + dt) % 1.0; 
          for (var inPort in node.inputs) {
            nextInputInv[node.id]![inPort.id] = (nextInputInv[node.id]![inPort.id] ?? 0.0) - inPort.rate * dt * node.stackCount;
          }
          for (var outPort in node.outputs) {
            if (!outPort.isDiscarded) {
              nextOutputInv[node.id]![outPort.id] = (nextOutputInv[node.id]![outPort.id] ?? 0.0) + outPort.rate * dt * node.stackCount;
            }
          }
        }
      }

      nextNodes.add(node.copyWith(
        inputInventory: nextInputInv[node.id],
        outputInventory: nextOutputInv[node.id],
        status: nextStatus,
        progress: nextProgress,
      ));
    }

    state = state.copyWith(nodes: nextNodes);
  }

  // [Feature] 新增：上帝模式的资源干预操作 (填充/排空)
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
          activeNode = activeNode.copyWith(stackCount: activeNode.stackCount + otherNode.stackCount);
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
        final targetIndex = nextNodes.indexWhere((node) => targetId != null && node.id.startsWith(targetId));
        
        if (targetIndex == -1) {
          print('Debug: 无法通过输入的短 ID [$targetId] 找到目标节点');
          continue;
        }

        ProductionNode targetNode = nextNodes[targetIndex];
        int originalStackCount = targetNode.stackCount;

        switch (action) {
          case 'build':
            if (!targetNode.isBuilt) {
              // [Fix] 剥离逻辑节点的资源校验，指令现在将作为"上帝模式"绝对执行
              nextNodes[targetIndex] = targetNode.copyWith(
                isBuilt: true, 
                isRunning: false,
                stackCount: 1 
              );
            }
            break;
            
          case 'stack':
            // [Fix] 同样剥离扩容的资源校验，确保指令畅通无阻，修复由于缺少材料导致的"不生效"
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
                stackCount: 1, 
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

  // --- 连线拖拽生命周期 (改进适配 Draggable) ---
  void startConnectionDrag(String nodeId, String portId) {
    state = state.copyWith(
      activeDragSourceNodeId: nodeId,
      activeDragSourcePortId: portId,
      // 初始拖拽不记录鼠标位置，由绘制层依据源端口全局位置推算起点
      activeDragCurrentPosition: null, 
    );
  }

  void updateConnectionDrag(Offset globalPosition) {
    state = state.copyWith(activeDragCurrentPosition: globalPosition);
  }

  void endConnectionDrag() {
    state = state.copyWith(clearDrag: true);
  }

  void finalizeConnection(String targetNodeId, String targetPortId) {
    if (state.activeDragSourceNodeId == null || state.activeDragSourcePortId == null) return;
    
    // 防止自环连接
    if (state.activeDragSourceNodeId == targetNodeId) {
      endConnectionDrag();
      return;
    }

    final sourceNode = state.nodes.firstWhere((n) => n.id == state.activeDragSourceNodeId!, orElse: () => state.nodes.first);
    final targetNode = state.nodes.firstWhere((n) => n.id == targetNodeId, orElse: () => state.nodes.first);
    
    final sourcePort = sourceNode.outputs.firstWhere((p) => p.id == state.activeDragSourcePortId!, orElse: () => sourceNode.outputs.first);
    final targetPort = targetNode.inputs.firstWhere((p) => p.id == targetPortId, orElse: () => targetNode.inputs.first);

    // 【核心修复 3】: 严格校验物料名称是否一致
    if (sourcePort.itemName != targetPort.itemName) {
      // 此处可抛出警告或直接中断连线
      endConnectionDrag();
      return;
    }

    // 建立连接
    final newConn = Connection(
      sourceNodeId: state.activeDragSourceNodeId!,
      sourcePortId: state.activeDragSourcePortId!,
      targetNodeId: targetNodeId,
      targetPortId: targetPortId,
    );
    
    state = state.copyWith(
      connections:[...state.connections, newConn],
      clearDrag: true,
    );
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
