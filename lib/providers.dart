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

  @override
  CanvasState build() => CanvasState();

  // [新增] 模拟器生命周期控制
  void toggleSimulation() {
    if (state.isSimulating) {
      _simTimer?.cancel();
      state = state.copyWith(isSimulating: false);
    } else {
      state = state.copyWith(isSimulating: true);
      _simTimer = Timer.periodic(const Duration(milliseconds: 100), _simTick);
    }
  }

  // [新增] 核心时序调度引擎 (Tick)
  void _simTick(Timer timer) {
    const double dt = 0.1; // 100ms时间步长
    Map<String, Map<String, double>> nextInputInv = {};
    Map<String, Map<String, double>> nextOutputInv = {};

    // 1. 初始化临时状态缓冲区
    for (var node in state.nodes) {
      nextInputInv[node.id] = Map.from(node.inputInventory);
      nextOutputInv[node.id] = Map.from(node.outputInventory);
    }

    // 2. 网络流转阶段：根据连接拓扑转移库存 (从 Source 转移至 Target)
    for (var conn in state.connections) {
      final sNode = state.nodes.where((n) => n.id == conn.sourceNodeId).firstOrNull;
      final tNode = state.nodes.where((n) => n.id == conn.targetNodeId).firstOrNull;
      if (sNode == null || tNode == null) continue;

      final outPort = sNode.outputs.where((p) => p.id == conn.sourcePortId).firstOrNull;
      final inPort = tNode.inputs.where((p) => p.id == conn.targetPortId).firstOrNull;
      if (outPort == null || inPort == null) continue;

      double available = nextOutputInv[sNode.id]![outPort.id] ?? 0.0;
      double maxTransfer = outPort.rate * dt; // 传输上限受限于源端口速率
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
      bool isStarved = false;
      bool isBlocked = false;

      // 判定是否缺料 (如果节点无输入端口，被视为 Source，永不缺料)
      for (var inPort in node.inputs) {
        if ((nextInputInv[node.id]![inPort.id] ?? 0.0) < inPort.rate * dt) {
          isStarved = true; break;
        }
      }

      // 判定是否堵塞 (如果节点无输出端口，被视为 Sink，永不堵塞)
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
        nextProgress = (nextProgress + dt) % 1.0; // 模拟周期转动

        // 实际消耗与产出发生 (按堆叠数量倍增)
        for (var inPort in node.inputs) {
          nextInputInv[node.id]![inPort.id] = (nextInputInv[node.id]![inPort.id] ?? 0.0) - inPort.rate * dt * node.stackCount;
        }
        for (var outPort in node.outputs) {
          if (!outPort.isDiscarded) {
            nextOutputInv[node.id]![outPort.id] = (nextOutputInv[node.id]![outPort.id] ?? 0.0) + outPort.rate * dt * node.stackCount;
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

  /// 执行一回合的逻辑自动化控制指令
  void executeLogicTick() {
    // 获取所有类型为"控制(Logic)"且具有明确目标和指令的卡片
    final logicNodes = state.nodes.where((n) => 
        n.category == ProcessCategory.control && 
        n.logicTargetNodeId != null && 
        n.logicAction != null);
        
    List<ProductionNode> nextNodes = List.from(state.nodes);

    for (var logicNode in logicNodes) {
      // 检查逻辑条件是否满足
      bool conditionMet = true;
      
      if (logicNode.logicCondition != null && logicNode.conditionValue != null) {
        conditionMet = _evaluateCondition(logicNode, state.nodes);
      }
      
      // 只有条件满足时才执行控制指令
      if (conditionMet) {
        final targetIndex = nextNodes.indexWhere((n) => n.id == logicNode.logicTargetNodeId);
        if (targetIndex == -1) continue;

        final targetNode = nextNodes[targetIndex];
        ProductionNode? updatedTarget;

        switch (logicNode.logicAction) {
          case 'build':
            // 逻辑判定：查找是否存在相同类型的节点（相同category和name）
            final existingNodeIndex = nextNodes.indexWhere((n) => 
                n.id != targetNode.id && // 排除目标节点本身
                n.category == targetNode.category && 
                n.name == targetNode.name);
            
            if (existingNodeIndex != -1) {
              // 如果存在相同类型的节点，增加其堆叠数
              final existingNode = nextNodes[existingNodeIndex];
              final updatedExistingNode = existingNode.copyWith(stackCount: existingNode.stackCount + 1);
              nextNodes[existingNodeIndex] = updatedExistingNode;
              // 目标节点保持不变
              updatedTarget = targetNode;
            } else {
              // 如果不存在相同类型的节点，则对目标节点执行build操作
              if (!targetNode.isBuilt) {
                updatedTarget = targetNode.copyWith(isBuilt: true, isRunning: false, stackCount: targetNode.stackCount + 1);
              } else {
                // 如果已经建设，则增加堆叠数量
                updatedTarget = targetNode.copyWith(stackCount: targetNode.stackCount + 1);
              }
            }
            break;
          case 'dismantle':
            // 逻辑判定：拆除节点退回为蓝图状态
            if (targetNode.isBuilt) updatedTarget = targetNode.copyWith(isBuilt: false, isRunning: false);
            break;
          case 'start':
            if (targetNode.isBuilt && !targetNode.isRunning) updatedTarget = targetNode.copyWith(isRunning: true);
            break;
          case 'stop':
            if (targetNode.isBuilt && targetNode.isRunning) updatedTarget = targetNode.copyWith(isRunning: false);
            break;
        }

        if (updatedTarget != null) {
          nextNodes[targetIndex] = updatedTarget;
        }
      }
    }

    state = state.copyWith(nodes: nextNodes);
  }
  
  /// 评估逻辑条件是否满足
  bool _evaluateCondition(ProductionNode logicNode, List<ProductionNode> allNodes) {
    if (logicNode.logicCondition == null || logicNode.conditionValue == null) {
      return true;
    }
    
    // 获取监测目标节点
    final targetNode = allNodes.firstWhere((n) => n.id == logicNode.conditionTargetNodeId, orElse: () => logicNode);
    if (targetNode == null) return false;
    
    // 获取监测端口
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
      // 如果没有指定端口，则使用节点的总体库存
      portValue = (targetNode.inputInventory.values.reduce((a, b) => a + b)) + 
                  (targetNode.outputInventory.values.reduce((a, b) => a + b));
    }
    
    // 根据条件类型进行比较
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

  void addNode(ProductionNode node) {
    // 检查是否已存在相同类型的节点（相同category和name）
    final existingNodeIndex = state.nodes.indexWhere((n) => 
        n.category == node.category && n.name == node.name);
    
    if (existingNodeIndex != -1) {
      // 如果存在相同类型的节点，增加其堆叠数
      final existingNode = state.nodes[existingNodeIndex];
      final updatedNode = existingNode.copyWith(stackCount: existingNode.stackCount + 1);
      
      List<ProductionNode> updatedNodes = List.from(state.nodes);
      updatedNodes[existingNodeIndex] = updatedNode;
      
      state = state.copyWith(nodes: updatedNodes);
    } else {
      // 如果不存在相同类型的节点，添加新节点
      state = state.copyWith(nodes:[...state.nodes, node]);
    }
  }

  void updateNodePosition(String nodeId, Offset delta) {
    final nodeIndex = state.nodes.indexWhere((n) => n.id == nodeId);
    if (nodeIndex == -1) return;

    var activeNode = state.nodes[nodeIndex];
    
    // 【核心修复 1】: 坐标钳制 (Clamping)
    // 强制限制坐标在 0 ~ 4700 之间，绝对不允许出现负数坐标，防止脱离 Stack 命中测试区
    double newDx = (activeNode.position.dx + delta.dx).clamp(0.0, 4750.0);
    double newDy = (activeNode.position.dy + delta.dy).clamp(0.0, 4800.0);
    activeNode = activeNode.copyWith(position: Offset(newDx, newDy));

    List<ProductionNode> newNodes = List.from(state.nodes);
    newNodes[nodeIndex] = activeNode;
    List<Connection> updatedConns = List.from(state.connections);

    // 碰撞检测基准常数 (预估卡片宽高)
    const double cardWidth = 260.0;
    const double cardHeight = 220.0;

    // 【核心修复 3 & 4】: 碰撞遍历检测
    for (int i = 0; i < newNodes.length; i++) {
      if (i == nodeIndex) continue;
      var otherNode = newNodes[i];

      Rect rectActive = Rect.fromLTWH(activeNode.position.dx, activeNode.position.dy, cardWidth, cardHeight);
      Rect rectOther = Rect.fromLTWH(otherNode.position.dx, otherNode.position.dy, cardWidth, cardHeight);

      if (rectActive.overlaps(rectOther)) {
        // 判断是否为完全相同的卡片种类
        bool isSameKind = (activeNode.category == otherNode.category && activeNode.name == otherNode.name);

        if (isSameKind) {
          // 同类卡片：如果中心点距离极近（< 50像素），触发吸附合并
          if ((rectActive.center - rectOther.center).distance < 50.0) {
            // 合并堆叠数量
            activeNode = activeNode.copyWith(stackCount: activeNode.stackCount + otherNode.stackCount);
            newNodes[nodeIndex] = activeNode;
            
            String oldId = otherNode.id;
            String newId = activeNode.id;
            newNodes.removeAt(i);
            
            // 自动迁移被吞并卡片的连线，根据 itemName 重新挂载端口
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

            break; // 发生合并，立即终止当前帧的其他碰撞检测
          }
        } else {
          // 不同种类的卡片：产生排斥力 (分离算法)
          Offset diff = rectOther.center - rectActive.center;
          if (diff.distance == 0) diff = const Offset(1, 0); // 避免中心完全重合产生的零向量
          
          double overlapX = cardWidth - diff.dx.abs();
          double overlapY = cardHeight - diff.dy.abs();
          
          if (overlapX > 0 && overlapY > 0) {
            // 取最小交叠轴进行推离
            if (overlapX < overlapY) {
              double pushX = overlapX * diff.dx.sign;
              otherNode = otherNode.copyWith(
                position: Offset((otherNode.position.dx + pushX).clamp(0.0, 4750.0), otherNode.position.dy)
              );
            } else {
              double pushY = overlapY * diff.dy.sign;
              otherNode = otherNode.copyWith(
                position: Offset(otherNode.position.dx, (otherNode.position.dy + pushY).clamp(0.0, 4800.0))
              );
            }
            newNodes[i] = otherNode;
          }
        }
      }
    }

    state = state.copyWith(nodes: newNodes, connections: updatedConns);
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
