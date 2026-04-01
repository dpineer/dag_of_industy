import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  });

  CanvasState copyWith({
    List<ProductionNode>? nodes,
    List<Connection>? connections,
    bool? isConnecting,
    String? sourceNodeId,
    String? sourcePortId,
    Offset? connectionStartPos,
    Offset? connectionCurrentPos,
    bool? isSignalConnecting, // [新增]
    String? signalSourceNodeId, // [新增]
    String? signalSourcePortId, // [新增]
    String? activeDragSourceNodeId, // [新增]
    String? activeDragSourcePortId, // [新增]
    Offset? activeDragCurrentPosition, // [新增]
    bool? isSimulating, // [新增]
    bool clearDrag = false, // [新增] 清除拖拽状态
  }) {
    return CanvasState(
      nodes: nodes ?? this.nodes,
      connections: connections ?? this.connections,
      isConnecting: isConnecting ?? this.isConnecting,
      sourceNodeId: sourceNodeId ?? this.sourceNodeId,
      sourcePortId: sourcePortId ?? this.sourcePortId,
      connectionStartPos: connectionStartPos ?? this.connectionStartPos,
      connectionCurrentPos: connectionCurrentPos ?? this.connectionCurrentPos,
      isSignalConnecting: isSignalConnecting ?? this.isSignalConnecting, // [新增]
      signalSourceNodeId: signalSourceNodeId ?? this.signalSourceNodeId, // [新增]
      signalSourcePortId: signalSourcePortId ?? this.signalSourcePortId, // [新增]
      activeDragSourceNodeId: activeDragSourceNodeId ?? this.activeDragSourceNodeId, // [新增]
      activeDragSourcePortId: activeDragSourcePortId ?? this.activeDragSourcePortId, // [新增]
      activeDragCurrentPosition: activeDragCurrentPosition ?? this.activeDragCurrentPosition, // [新增]
      isSimulating: isSimulating ?? this.isSimulating, // [新增]
    );
  }
}

class CanvasNotifier extends Notifier<CanvasState> {
  Timer? _timer;

  @override
  CanvasState build() {
    _timer = Timer.periodic(const Duration(milliseconds: 100), _tick);
    return CanvasState();
  }

  void _tick(Timer timer) {
    if (!state.isSimulating) return; // [新增] 检查模拟状态

    List<ProductionNode> nextNodes = List.from(state.nodes);

    // 1. 更新节点状态
    for (int i = 0; i < nextNodes.length; i++) {
      ProductionNode node = nextNodes[i];
      if (!node.isBuilt || !node.isRunning) continue; // 未建设或未运行的节点不更新

      // 检查是否缺料
      bool hasRequiredInputs = true;
      for (var input in node.inputs) {
        if (input.isRequired && (node.inputInventory[input.id] ?? 0) < input.rate * 0.1) {
          hasRequiredInputs = false;
          break;
        }
      }

      // 检查产物是否堵塞
      bool hasSpaceForOutput = true;
      for (var output in node.outputs) {
        if ((node.outputInventory[output.id] ?? 0) >= node.maxCapacity * 0.9) {
          hasSpaceForOutput = false;
          break;
        }
      }

      NodeStatus newStatus = NodeStatus.running;
      if (!hasRequiredInputs) {
        newStatus = NodeStatus.starved;
      } else if (!hasSpaceForOutput) {
        newStatus = NodeStatus.blocked;
      }

      // 更新节点状态
      nextNodes[i] = node.copyWith(status: newStatus);

      // 2. 执行生产逻辑
      if (newStatus == NodeStatus.running) {
        // 消耗输入
        Map<String, double> newInputInventory = Map.from(node.inputInventory);
        for (var input in node.inputs) {
          double current = newInputInventory[input.id] ?? 0;
          newInputInventory[input.id] = (current - input.rate * 0.1).clamp(0, node.maxCapacity);
        }

        // 产生输出
        Map<String, double> newOutputInventory = Map.from(node.outputInventory);
        for (var output in node.outputs) {
          if (!output.isDiscarded) {
            double current = newOutputInventory[output.id] ?? 0;
            newOutputInventory[output.id] = (current + output.rate * 0.1).clamp(0, node.maxCapacity);
          }
        }

        // 更新库存
        nextNodes[i] = nextNodes[i].copyWith(
          inputInventory: newInputInventory,
          outputInventory: newOutputInventory,
          progress: (node.progress + 0.1) % 1.0,
        );
      }
    }

    // 3. 处理连接物流
    for (var connection in state.connections) {
      if (connection.type == ConnectionType.signal) continue; // 跳过信号连接，物料流不处理

      ProductionNode? sourceNode = nextNodes.firstWhere((n) => n.id == connection.sourceNodeId, orElse: () => nextNodes.firstWhere((n) => n.id == connection.targetNodeId));
      ProductionNode? targetNode = nextNodes.firstWhere((n) => n.id == connection.targetNodeId, orElse: () => nextNodes.firstWhere((n) => n.id == connection.sourceNodeId));

      if (sourceNode == null || targetNode == null) continue;
      if (!sourceNode.isBuilt || !targetNode.isBuilt) continue;

      // 找到连接的端口
      OutputPort? sourcePort = sourceNode.outputs.firstWhere((p) => p.id == connection.sourcePortId, orElse: () => sourceNode.outputs.firstWhere((p) => p.id == connection.targetPortId));
      InputPort? targetPort = targetNode.inputs.firstWhere((p) => p.id == connection.targetPortId, orElse: () => targetNode.inputs.firstWhere((p) => p.id == connection.sourcePortId));

      if (sourcePort == null || targetPort == null) continue;

      // 物料传输
      double sourceAmount = sourceNode.outputInventory[sourcePort.id] ?? 0;
      if (sourceAmount > 0) {
        double transferAmount = (sourcePort.rate * 0.1).clamp(0, sourceAmount);
        if (transferAmount > 0) {
          // 从源节点输出库存中移除
          Map<String, double> newSourceOutputInventory = Map.from(sourceNode.outputInventory);
          newSourceOutputInventory[sourcePort.id] = (sourceAmount - transferAmount).clamp(0, sourceNode.maxCapacity);

          // 添加到目标节点输入库存
          double targetAmount = targetNode.inputInventory[targetPort.id] ?? 0;
          Map<String, double> newTargetInputInventory = Map.from(targetNode.inputInventory);
          newTargetInputInventory[targetPort.id] = (targetAmount + transferAmount).clamp(0, targetNode.maxCapacity);

          // 更新节点
          int sourceIndex = nextNodes.indexWhere((n) => n.id == sourceNode!.id);
          int targetIndex = nextNodes.indexWhere((n) => n.id == targetNode!.id);
          if (sourceIndex != -1) {
            nextNodes[sourceIndex] = nextNodes[sourceIndex].copyWith(outputInventory: newSourceOutputInventory);
          }
          if (targetIndex != -1) {
            nextNodes[targetIndex] = nextNodes[targetIndex].copyWith(inputInventory: newTargetInputInventory);
          }
        }
      }
    }

    // [核心] 独立于物料流的逻辑信号 Tick
    _logicTick(timer);

    state = state.copyWith(nodes: nextNodes);
  }

  // [核心] 独立于物料流的逻辑信号 Tick
  void _logicTick(Timer timer) {
    List<ProductionNode> nextNodes = List.from(state.nodes);
    
    // 第一步：状态到信号的提取 (State -> Signal Output)
    for (int i = 0; i < nextNodes.length; i++) {
      nextNodes[i] = _extractStatusToSignals(nextNodes[i]);
    }

    // 第二步：信号传播 (Signal Propagation)
    // 建立一个信号池，暂存本轮 Tick 的信号值
    Map<String, double> signalPool = {}; 
    for (var conn in state.connections) {
      if (conn.type == ConnectionType.signal) {
        final sNode = nextNodes.firstWhere((n) => n.id == conn.sourceNodeId);
        final sPort = sNode.signalOutputs.firstWhere((p) => p.id == conn.sourcePortId);
        signalPool["${conn.targetNodeId}:${conn.targetPortId}"] = sPort.value;
      }
    }

    // 第三步：逻辑运算处理 (Logic Computation)
    for (int i = 0; i < nextNodes.length; i++) {
      var node = nextNodes[i];
      
      // 更新输入信号端口值
      var updatedInputs = node.signalInputs.map((p) {
        return SignalPort(
          id: p.id,
          name: p.name,
          type: p.type,
          value: signalPool["${node.id}:${p.id}"] ?? 0.0,
        );
      }).toList();

      node = node.copyWith(signalInputs: updatedInputs);

      // 如果是逻辑节点，执行运算
      if (node.category == ProcessCategory.control) {
        node = _executeLogicOperations(node);
      }

      // 第四步：信号到控制的映射 (Signal Input -> Control)
      node = _applySignalsToControl(node);
      nextNodes[i] = node;
    }

    state = state.copyWith(nodes: nextNodes);
  }

  // [功能] 节点物理状态转换为信号输出
  ProductionNode _extractStatusToSignals(ProductionNode node) {
    var outputs = List<SignalPort>.from(node.signalOutputs);
    for (int i = 0; i < outputs.length; i++) {
      var port = outputs[i];
      // 约定名称：status_code (0:idle, 1:running, 2:starved, 3:blocked)
      if (port.name == 'status_code') {
        port.value = node.status.index.toDouble();
      }
      // 约定名称：inv_ratio (0.0 - 1.0)
      if (port.name == 'inv_ratio') {
        double total = node.inputInventory.values.fold(0, (a, b) => a + b);
        port.value = node.maxCapacity > 0 ? (total / node.maxCapacity) : 0;
      }
    }
    return node.copyWith(signalOutputs: outputs);
  }

  // [功能] 逻辑算子执行引擎 (图灵完备核心)
  ProductionNode _executeLogicOperations(ProductionNode node) {
    double inA = node.signalInputs.isNotEmpty ? node.signalInputs[0].value : 0.0;
    double inB = node.signalInputs.length > 1 ? node.signalInputs[1].value : 0.0;
    double outVal = 0.0;
    Map<String, double> nextRegs = Map.from(node.registers);

    switch (node.logicOp) {
      case LogicOperator.and:
        outVal = (inA > 0.5 && inB > 0.5) ? 1.0 : 0.0;
        break;
      case LogicOperator.not:
        outVal = inA > 0.5 ? 0.0 : 1.0;
        break;
      case LogicOperator.adder:
        outVal = inA + inB;
        break;
      case LogicOperator.latch:
        // Set-Reset Latch: inA 为 Set, inB 为 Reset
        double current = nextRegs['q'] ?? 0.0;
        if (inA > 0.5) current = 1.0;
        if (inB > 0.5) current = 0.0;
        nextRegs['q'] = current;
        outVal = current;
        break;
      case LogicOperator.greater:
        outVal = inA > inB ? 1.0 : 0.0;
        break;
      default:
        outVal = inA;
    }

    var outputs = List<SignalPort>.from(node.signalOutputs);
    if (outputs.isNotEmpty) outputs[0].value = outVal;
    
    return node.copyWith(signalOutputs: outputs, registers: nextRegs);
  }

  // [功能] 信号控制节点行为
  ProductionNode _applySignalsToControl(ProductionNode node) {
    // 寻找约定名称为 'ctrl_run' 的输入信号
    final runSig = node.signalInputs.where((p) => p.name == 'ctrl_run').firstOrNull;
    if (runSig != null) {
      // 只要 ctrl_run 信号 > 0.5，则强制启动，否则关闭
      return node.copyWith(isRunning: runSig.value > 0.5);
    }
    return node;
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

  // [新增] 切换模拟状态
  void toggleSimulation() {
    state = state.copyWith(isSimulating: !state.isSimulating);
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
                stackCount: 1 
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
    // 清除拖拽状态，这将导致贝塞尔曲线不再绘制
    state = state.copyWith(
      activeDragSourceNodeId: null,
      activeDragSourcePortId: null,
      activeDragCurrentPosition: null,
    );
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
    _timer?.cancel();
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