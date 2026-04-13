import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 添加剪贴板服务
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math' show min; // 用于信号端口标签逻辑
import 'models.dart';
import 'providers.dart';
import 'node_edit_dialog.dart';

class NodeWidget extends ConsumerStatefulWidget {
  final ProductionNode node;
  const NodeWidget({super.key, required this.node});

  @override
  ConsumerState<NodeWidget> createState() => _NodeWidgetState();
}

class _NodeWidgetState extends ConsumerState<NodeWidget> {
  // 逻辑控制卡片的内联调试面板展开状态（默认展开）
  bool _logicPanelExpanded = true;

  ProductionNode get node => widget.node;

  @override
  Widget build(BuildContext context) {
    final bool isBlueprint = !node.isBuilt;
    
    // 封装单层卡片 UI 以便复用
    Widget cardContent = Container(
      width: 250,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        // 蓝图状态显示虚线或浅色边框，停机状态显示灰色边框
        border: Border.all(
          color: isBlueprint ? Colors.blue.withOpacity(0.5) : (node.isRunning ? node.category.themeColor : Colors.grey), 
          width: 2,
          style: isBlueprint ? BorderStyle.solid : BorderStyle.solid, 
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).brightness == Brightness.dark 
              ? Colors.black54 
              : Colors.black26, 
            blurRadius: 6
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children:[
          // 卡片头部
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: node.category.themeColor.withOpacity(0.15),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children:[
                Row(
                  children:[
                    // [新增] 状态指示灯
                    Icon(Icons.circle, size: 10, color: node.status.color),
                    const SizedBox(width: 6),
                    Text(
                      "${node.name} #${node.id.substring(0, 5)}", 
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Theme.of(context).textTheme.bodyLarge?.color),
                    ),
                  ],
                ),
                Text(
                  node.status.label, // [新增] 文字状态
                  style: TextStyle(fontSize: 10, color: node.status.color, fontWeight: FontWeight.bold),
                )
              ],
            ),
          ),
          
          // 【核心修复 2】: 逻辑卡片的专属控制面板
          _buildLogicDebugPanel(context),
          
          // 【核心修复 2】: 解除对逻辑卡片的隔离，所有种类的卡片均需渲染输入输出端口
          // 使得控制卡片能够通过"输入端口"吸收外部建设所需资源，通过"输出端口"传递指令流或副产物
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children:[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, 
                    children: [
                      // 信号输入端口
                      if (node.signalInputs.isNotEmpty) ...node.signalInputs.map((p) => _buildSignalPort(context, ref, p, true)),
                      if (node.signalInputs.isNotEmpty) const Divider(height: 8),
                      // 物料输入端口
                      ...node.inputs.map((i) => _buildInputPort(context, ref, i)).toList()
                    ]
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end, 
                    children: [
                      // 信号输出端口
                      if (node.signalOutputs.isNotEmpty) ...node.signalOutputs.map((p) => _buildSignalPort(context, ref, p, false)),
                      if (node.signalOutputs.isNotEmpty) const Divider(height: 8),
                      // 物料输出端口
                      ...node.outputs.map((o) => _buildOutputPort(context, ref, o)).toList()
                    ]
                  ),
                ),
              ],
            ),
          ),
          // [修复 3] 仓储水位线与进度条分治渲染机制
          Builder(
            builder: (context) {
              double displayProgress = node.progress;
              
              // 若为仓储类型的卡片，进度条的数值强制映射为库存占比
              if (node.category == ProcessCategory.storing) {
                double totalInv = 0.0;
                node.inputInventory.values.forEach((v) => totalInv += v);
                node.outputInventory.values.forEach((v) => totalInv += v);
                
                // 防止 maxCapacity 为 0 的除法异常
                displayProgress = node.maxCapacity > 0 
                    ? (totalInv / node.maxCapacity).clamp(0.0, 1.0) 
                    : 0.0;
              }
              
              // 若为控制类型的卡片且有目标节点，进度条显示目标节点的存储量
              else if (node.category == ProcessCategory.control && node.logicTargetNodeId != null) {
                // 查找目标节点（使用双向前缀匹配，兼容短ID和完整ID）
                final targetNode = ref.read(canvasProvider).nodes.firstWhere(
                  (n) => n.id.startsWith(node.logicTargetNodeId!) || node.logicTargetNodeId!.startsWith(n.id), 
                  orElse: () => node,
                );
                
                // 如果目标节点存在，则显示目标节点的存储量
                if (targetNode != node) {
                  double totalInv = 0.0;
                  targetNode.inputInventory.values.forEach((v) => totalInv += v);
                  targetNode.outputInventory.values.forEach((v) => totalInv += v);
                  
                  // 防止 maxCapacity 为 0 的除法异常
                  displayProgress = targetNode.maxCapacity > 0 
                      ? (totalInv / targetNode.maxCapacity).clamp(0.0, 1.0) 
                      : 0.0;
                }
              }
              
              // 若为蓝图类型的卡片，进度条显示建设资源积累进度（使用节点自身的建设配方）
              else if (!node.isBuilt) {
                // 计算建设资源的满足程度
                if (node.constructionCost.isNotEmpty) {
                  double totalRequired = 0.0;
                  double totalAvailable = 0.0;
                  
                  for (final entry in node.constructionCost.entries) {
                    final resourceName = entry.key;
                    final requiredAmount = entry.value;
                    totalRequired += requiredAmount;
                    
                    // 在输入库存中查找对应资源
                    double availableAmount = 0.0;
                    for (final inputPort in node.inputs) {
                      if (inputPort.itemName == resourceName) {
                        availableAmount = node.inputInventory[inputPort.id] ?? 0.0;
                        break;
                      }
                    }
                    
                    // 累加可用资源，但不超过所需量（避免进度超过100%）
                    totalAvailable += availableAmount.clamp(0.0, requiredAmount);
                  }
                  
                  displayProgress = totalRequired > 0 
                      ? (totalAvailable / totalRequired).clamp(0.0, 1.0) 
                      : 0.0;
                } else {
                  // 如果没有建设成本，进度为0
                  displayProgress = 0.0;
                }
              }

              if (node.status != NodeStatus.idle || !node.isBuilt) {
                return Container(
                  height: 4,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(6)),
                    color: Colors.grey.shade300,
                  ),
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: displayProgress, // 替换这里原有的 node.progress
                    child: Container(
                      color: !node.isBuilt 
                          ? Colors.blueAccent // 蓝图为建设进度，使用蓝色
                          : (node.category == ProcessCategory.storing 
                              ? Colors.blueAccent // 仓储卡片使用专用的水位颜色
                              : node.status.color),
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            }
          )
        ],
      ),
    );

    return GestureDetector(
      // [Fix] 强制卡片消费内部所有的手势命中测试，防止多卡片交叠时底层画板抢夺焦点导致无法拖拽
      behavior: HitTestBehavior.opaque, 
      onSecondaryTapDown: (details) => _showContextMenu(context, ref, details.globalPosition),
      onPanUpdate: (details) => ref.read(canvasProvider.notifier).updateNodePosition(node.id, details.delta),
      child: Opacity(
        opacity: isBlueprint ? 0.6 : 1.0, 
        child: Stack(
          clipBehavior: Clip.none,
          children:[
            if (node.stackCount > 1)
              for (int i = 1; i < (node.stackCount > 4 ? 4 : node.stackCount); i++)
                Positioned(
                  top: i * 4.0, left: i * 4.0, 
                  child: Container(
                    width: 250, height: 100, 
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor.withOpacity(0.5),
                      border: Border.all(color: node.category.themeColor.withOpacity(0.5)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                
            // 顶层主卡片
            cardContent,
            
            // [Fix] 加减UI上移并缩小
            Positioned(
              top: -24, 
              right: -5,
              child: Transform.scale(
                scale: 0.8, // 缩小至 80% 避免遮挡下面内容
                child: _buildStackController(ref),
              ),
            ),
            
            // [Fix] 已删除位于此处的第二个 isRunning 状态指示点 (圆点现已统一在卡片 Header 处显示)
          ],
        ),
      ),
    );
  }

  // 堆叠数量增减组件
  Widget _buildStackController(WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children:[
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (node.stackCount > 1) {
                // 使用 updateNodeComplete 方法更新节点
                ref.read(canvasProvider.notifier).updateNodeComplete(node.id, node.copyWith(stackCount: node.stackCount - 1));
              }
            },
            child: const Padding(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8), child: Icon(Icons.remove, color: Colors.white, size: 16)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(' ${node.stackCount} ', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              // 使用 updateNodeComplete 方法更新节点
              ref.read(canvasProvider.notifier).updateNodeComplete(node.id, node.copyWith(stackCount: node.stackCount + 1));
            },
            child: const Padding(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8), child: Icon(Icons.add, color: Colors.white, size: 16)),
          ),
        ],
      ),
    );
  }

  /// 弹出右键上下文菜单
  void _showContextMenu(BuildContext context, WidgetRef ref, Offset position) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: const[
        PopupMenuItem(value: 'edit', child: Text('编辑节点属性')),
        PopupMenuItem(value: 'copy', child: Text('复制节点信息')),
        PopupMenuItem(value: 'delete', child: Text('删除该节点', style: TextStyle(color: Colors.red))),
      ],
    );

    if (result == 'edit' && context.mounted) {
      _showEditDialog(context, ref);
    } else if (result == 'copy') {
      _copyNodeInfoToClipboard(context);
    } else if (result == 'delete') {
      // 使用完整ID删除节点
      ref.read(canvasProvider.notifier).removeNode(node.id);
    }
  }

  /// 节点属性编辑弹窗
  void _showEditDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => NodeEditDialog(nodeId: node.id),
    );
  }

  /// 复制节点信息到剪贴板
  void _copyNodeInfoToClipboard(BuildContext context) async {
    // 构建节点信息字符串
    StringBuffer buffer = StringBuffer();
    buffer.writeln('节点名称: ${node.name}');
    buffer.writeln('节点ID: ${node.id}');
    buffer.writeln('节点类型: ${node.category.displayName}');
    buffer.writeln('位置: (${node.position.dx}, ${node.position.dy})');
    buffer.writeln('状态: ${node.status.label}');
    buffer.writeln('是否已建设: ${node.isBuilt ? '是' : '否'}');
    buffer.writeln('是否运行: ${node.isRunning ? '是' : '否'}');
    buffer.writeln('堆叠数量: ${node.stackCount}');
    buffer.writeln('最大容量: ${node.maxCapacity}');
    buffer.writeln('进度: ${(node.progress * 100).toStringAsFixed(2)}%');
    
    // 添加输入端口信息
    if (node.inputs.isNotEmpty) {
      buffer.writeln('\n输入端口:');
      for (var input in node.inputs) {
        double inv = node.inputInventory[input.id] ?? 0.0;
        buffer.writeln('  - ${input.itemName}: ${input.rate}${input.unit}/s (库存: ${inv.toStringAsFixed(2)}${input.unit})');
      }
    }
    
    // 添加输出端口信息
    if (node.outputs.isNotEmpty) {
      buffer.writeln('\n输出端口:');
      for (var output in node.outputs) {
        double inv = node.outputInventory[output.id] ?? 0.0;
        String type = output.isPollutant ? ' (污染物)' : (output.isConstructionMaterial ? ' (建设资源)' : '');
        buffer.writeln('  - ${output.itemName}: ${output.rate}${output.unit}/s (库存: ${inv.toStringAsFixed(2)}${output.unit})$type');
      }
    }
    
    // 添加信号端口信息
    if (node.signalInputs.isNotEmpty || node.signalOutputs.isNotEmpty) {
      buffer.writeln('\n信号端口:');
      for (var input in node.signalInputs) {
        buffer.writeln('  - 输入: ${input.name} (${input.type.name}) = ${input.value} (行为: ${input.inBehavior.name})');
      }
      for (var output in node.signalOutputs) {
        buffer.writeln('  - 输出: ${output.name} (${output.type.name}) = ${output.value} (行为: ${output.outBehavior.name})');
      }
    }
    
    // 添加建设成本信息
    if (node.constructionCost.isNotEmpty) {
      buffer.writeln('\n建设成本:');
      for (var entry in node.constructionCost.entries) {
        buffer.writeln('  - ${entry.key}: ${entry.value}');
      }
    }
    
    // 添加逻辑控制信息
    if (node.category == ProcessCategory.control) {
      buffer.writeln('\n逻辑控制:');
      buffer.writeln('  - 目标节点: ${node.logicTargetNodeId ?? '未设置'}');
      buffer.writeln('  - 控制指令: ${node.logicAction ?? '未设置'}');
      buffer.writeln('  - 逻辑算子: ${node.logicOp.displayName}');
    }
    
    try {
      await Clipboard.setData(ClipboardData(text: buffer.toString()));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('节点信息已复制到剪贴板')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('复制失败: $e')),
        );
      }
    }
  }

  // 在 NodeWidget 中新增库存干预菜单方法
  void _showInventoryIntervention(BuildContext context, WidgetRef ref, String portId, bool isInput, double currentInv) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('物理资源干预', style: TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_sweep, color: Colors.red),
              title: const Text('排空 (0)'),
              onTap: () {
                ref.read(canvasProvider.notifier).setInventory(node.id, portId, isInput, 0.0);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_box, color: Colors.green),
              title: const Text('灌注 (+1000)'),
              onTap: () {
                ref.read(canvasProvider.notifier).setInventory(node.id, portId, isInput, currentInv + 1000.0);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputPort(BuildContext context, WidgetRef ref, InputPort port) {
    double inv = node.inputInventory[port.id] ?? 0.0;
    print("InputPort - Name: ${port.itemName}, Rate: ${port.rate}, Unit: ${port.unit}, ID: ${port.id}"); // 调试日志
    // 接收连线的 DragTarget
    return DragTarget<String>(
      onAccept: (sourcePortData) {
        print("InputPort onAccept - sourcePortData: $sourcePortData, target port ID: ${port.id}"); // 调试日志
        // sourcePortData 格式为 "nodeId:portId"
        ref.read(canvasProvider.notifier).finalizeConnection(node.id, port.id, DragType.material);
      },
      builder: (context, candidateData, rejectedData) {
        bool isHovered = candidateData.isNotEmpty;
        print("InputPort builder - candidateData: $candidateData, port ID: ${port.id}"); // 调试日志
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.only(left: 0),
          child: Row(
            children:[
              Icon(Icons.chevron_right, size: 20, color: isHovered ? Colors.green : Colors.grey),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children:[
                    Text(
                      "${port.itemName} (${port.rate}${port.unit}/s)",
                      style: TextStyle(fontSize: 11, color: Theme.of(context).textTheme.bodyMedium?.color),
                    ),
                    GestureDetector(
                      onTap: () => _showInventoryIntervention(context, ref, port.id, true, inv),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4)
                        ),
                        child: Text(
                          "存: ${inv.toStringAsFixed(1)} ${port.unit}",
                          style: const TextStyle(fontSize: 10, color: Colors.blueGrey, decoration: TextDecoration.underline),
                        ),
                      ),
                    )
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSignalPort(BuildContext context, WidgetRef ref, SignalPort port, bool isInput) {
    final bool isDigital = port.type == SignalType.digital;
    final Color portColor = isDigital ? Colors.cyanAccent : Colors.purpleAccent;
    final IconData portIcon = isDigital ? Icons.stop : Icons.change_history;
    final DragType expectedDragType = isDigital ? DragType.signalDigital : DragType.signalAnalog;

    if (isInput) {
      // --- 信号输入端对齐物料输入端 UI 架构 ---
      return DragTarget<String>(
        onWillAccept: (data) {
          final currentDragType = ref.read(canvasProvider).activeDragType;
          final canAccept = currentDragType == expectedDragType;
          if (canAccept) {
            ref.read(canvasProvider.notifier).setConnectionHoverValid(true);
          }
          return canAccept;
        },
        onLeave: (_) {
          ref.read(canvasProvider.notifier).setConnectionHoverValid(false);
        },
        onAccept: (data) {
          ref.read(canvasProvider.notifier).finalizeConnection(node.id, port.id, expectedDragType);
        },
        builder: (ctx, candidate, _) {
          bool isHovered = candidate.isNotEmpty;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(portIcon, size: 16, color: isHovered ? Colors.greenAccent : portColor),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "${port.name} (${isDigital ? '数字' : '模拟'})",
                        style: TextStyle(fontSize: 11, color: Theme.of(context).textTheme.bodyMedium?.color),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                        decoration: BoxDecoration(
                          color: portColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4)
                        ),
                        child: Text(
                          "值: ${port.value.toStringAsFixed(1)}",
                          style: TextStyle(fontSize: 10, color: portColor),
                        ),
                      )
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    } else {
      // --- 信号输出端对齐物料输出端 UI 架构 ---
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "${port.name} (${isDigital ? '数字' : '模拟'})",
                  style: TextStyle(fontSize: 11, color: Theme.of(context).textTheme.bodyMedium?.color),
                  overflow: TextOverflow.ellipsis,
                ),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                  decoration: BoxDecoration(
                    color: portColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4)
                  ),
                  child: Text(
                    "值: ${port.value.toStringAsFixed(1)}",
                    style: TextStyle(fontSize: 10, color: portColor),
                  ),
                )
              ],
            ),
            const SizedBox(width: 4),
            Draggable<String>(
              data: "${node.id}:${port.id}",
              feedback: Icon(portIcon, size: 16, color: portColor.withOpacity(0.8)),
              childWhenDragging: Icon(portIcon, size: 16, color: Colors.grey),
              onDragStarted: () {
                ref.read(canvasProvider.notifier).startConnectionDrag(node.id, port.id, expectedDragType);
              },
              onDragUpdate: (details) {
                final RenderBox renderBox = context.findRenderObject() as RenderBox;
                Offset localPosition = renderBox.globalToLocal(details.globalPosition);
                Offset canvasPosition = node.position + localPosition;
                ref.read(canvasProvider.notifier).updateConnectionDrag(canvasPosition);
              },
              onDragEnd: (details) => ref.read(canvasProvider.notifier).endConnectionDrag(),
              onDraggableCanceled: (velocity, offset) => ref.read(canvasProvider.notifier).cancelConnectionDrag(),
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: Icon(portIcon, size: 16, color: portColor),
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildOutputPort(BuildContext context, WidgetRef ref, OutputPort port) {
    double inv = node.outputInventory[port.id] ?? 0.0;
    print("OutputPort - Name: ${port.itemName}, Rate: ${port.rate}, Unit: ${port.unit}, ID: ${port.id}, isPollutant: ${port.isPollutant}"); // 调试日志
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children:[
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children:[
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children:[
                  Text(
                    "${port.itemName} (${port.rate}${port.unit}/s)", 
                    style: TextStyle(
                      fontSize: 11,
                      color: port.isConstructionMaterial 
                        ? Colors.blue.shade600 // 建设资源显示为蓝色
                        : (port.isPollutant ? Colors.red.shade400 : Theme.of(context).textTheme.bodyMedium?.color),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _showInventoryIntervention(context, ref, port.id, false, inv),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4)
                      ),
                      child: Text(
                        "存: ${inv.toStringAsFixed(1)} ${port.unit}",
                        style: const TextStyle(fontSize: 10, color: Colors.blueGrey, decoration: TextDecoration.underline),
                      ),
                    ),
                  )
                ],
              ),
              const SizedBox(width: 4),
              
              // 拖拽触点区域
              Draggable<String>(
                data: "${node.id}:${port.id}", // 传递源节点与源端口数据
                feedback: Icon(Icons.circle, color: Colors.blueAccent.withOpacity(0.8), size: 16),
                childWhenDragging: const Icon(Icons.circle_outlined, size: 16, color: Colors.grey),
                
                // 拖拽生命周期挂载
                onDragStarted: () {
                  print("OutputPort drag started - node ID: ${node.id}, port ID: ${port.id}"); // 调试日志
                  ref.read(canvasProvider.notifier).startConnectionDrag(node.id, port.id, DragType.material);
                },
                onDragUpdate: (details) {
                  // 获取当前画板的 RenderBox (需要为 CustomPaint 区域绑定 GlobalKey，或通过 context 向上查找)
                  // 此处提供标准解法：使用 context 找到最近的 RenderBox (即所在的 InteractiveViewer 内容区)
                  final RenderBox renderBox = context.findRenderObject() as RenderBox;
                  final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
                  
                  // 将全局坐标转换为当前组件所在画布的局部坐标
                  // 假设 InteractiveViewer 的 child 是占据 5000x5000 的 Stack，需要在 Stack 层级做坐标转换
                  // 为了简化，推荐在 provider 中传递经过转换后的局部坐标
                  
                  // 简易精确转换法：
                  Offset localPosition = renderBox.globalToLocal(details.globalPosition);
                  // 注意：因为 renderBox 是端口自己的 RenderBox，我们需要加上 node.position 来换算为全局画布坐标
                  Offset canvasPosition = node.position + localPosition; 
                  
                  ref.read(canvasProvider.notifier).updateConnectionDrag(canvasPosition);
                },
                onDragEnd: (details) {
                // 【修复 2】: 释放时清理拖拽状态，防止 Ghost Line 残留
                ref.read(canvasProvider.notifier).endConnectionDrag();
              },
              onDraggableCanceled: (velocity, offset) {
                // 当拖拽被取消时，也清除拖拽状态
                ref.read(canvasProvider.notifier).cancelConnectionDrag();
              },
                
                // 默认静态图标
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Icon(
                    Icons.circle,
                    size: 16,
                    color: port.isPollutant ? Colors.red : Colors.blueGrey,
                  ),
                ),
              ),
            ],
          ),
        ),
        // ... 保留原有的直接丢弃(污染)选项UI ...
        if (port.isPollutant)
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0, right: 20.0),
            child: InkWell(
              onTap: () => ref.read(canvasProvider.notifier).togglePollutantDiscard(node.id, port.id),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children:[
                  Icon(
                    port.isDiscarded ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 14,
                    color: port.isDiscarded ? Colors.orange : Colors.grey,
                  ),
                  const SizedBox(width: 2),
                  Text("直接丢弃(污染)", style: TextStyle(
                    fontSize: 10, 
                    color: port.isDiscarded ? Colors.orange : Colors.grey,
                  )),
                ],
              ),
            ),
          )
      ],
    );
  }

  // [新增] 逻辑卡片独立调试面板
  // 完整替换原有 if (node.category == ProcessCategory.control) 区域
  Widget _buildLogicDebugPanel(BuildContext context) {
    if (node.category != ProcessCategory.control) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.blueAccent.withOpacity(0.08),
        border: Border.all(color: Colors.blueAccent.withOpacity(0.3), width: 1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 面板标题栏（含展开/折叠控制）
          InkWell(
            onTap: () => setState(() => _logicPanelExpanded = !_logicPanelExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.memory, size: 14, color: Colors.blueAccent),
                  const SizedBox(width: 4),
                  Text(
                    '逻辑算子: ${node.logicOp.displayName}',
                    style: const TextStyle(fontSize: 11, color: Colors.blueAccent, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  // 快速切换算子按钮
                  PopupMenuButton<LogicOperator>(
                    padding: EdgeInsets.zero,
                    iconSize: 14,
                    tooltip: '切换算子',
                    onSelected: (op) {
                      ref.read(canvasProvider.notifier).updateNodeComplete(
                        node.id, node.copyWith(logicOp: op),
                      );
                    },
                    itemBuilder: (_) => LogicOperator.values.map((op) =>
                      PopupMenuItem(value: op, child: Text(op.displayName, style: const TextStyle(fontSize: 12))),
                    ).toList(),
                    child: const Icon(Icons.tune, size: 14, color: Colors.blueAccent),
                  ),
                  Icon(
                    _logicPanelExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 14,
                    color: Colors.blueAccent,
                  ),
                ],
              ),
            ),
          ),

          // 展开内容区
          if (_logicPanelExpanded) ...[
            const Divider(height: 1, thickness: 1),
            Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 信号输入端口实时状态显示
                  if (node.signalInputs.isNotEmpty) ...[
                    const Text('信号输入', style: TextStyle(fontSize: 10, color: Colors.grey)),
                    ...node.signalInputs.asMap().entries.map((e) {
                      final idx = e.key;
                      final port = e.value;
                      final label = idx == 0 ? 'IN A' : (idx == 1 ? 'IN B' : 'IN${idx}');
                      final isDigital = port.type == SignalType.digital;
                      return _buildSignalValueRow(
                        label: label,
                        port: port,
                        isInput: true,
                        color: isDigital ? Colors.cyanAccent : Colors.purpleAccent,
                      );
                    }),
                    const SizedBox(height: 4),
                  ],

                  // 信号输出端口实时状态显示
                  if (node.signalOutputs.isNotEmpty) ...[
                    const Text('信号输出', style: TextStyle(fontSize: 10, color: Colors.grey)),
                    ...node.signalOutputs.asMap().entries.map((e) {
                      final idx = e.key;
                      final port = e.value;
                      final label = 'OUT${idx}';
                      final isDigital = port.type == SignalType.digital;
                      return _buildSignalValueRow(
                        label: label,
                        port: port,
                        isInput: false,
                        color: isDigital ? Colors.cyanAccent : Colors.purpleAccent,
                      );
                    }),
                    const SizedBox(height: 4),
                  ],

                  // 目标绑定信息（简要）
                  Row(
                    children: [
                      const Icon(Icons.link, size: 12, color: Colors.blueGrey),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '目标: ${node.logicTargetNodeId != null ? node.logicTargetNodeId!.substring(0, min(8, node.logicTargetNodeId!.length)) : "未绑定"}  指令: ${node.logicAction ?? "—"}',
                          style: const TextStyle(fontSize: 10, color: Colors.blueGrey),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),

                  // Latch 寄存器状态
                  if (node.logicOp == LogicOperator.latch && node.registers.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Q = ${node.registers['q']?.toStringAsFixed(1) ?? '0.0'}',
                        style: const TextStyle(fontSize: 11, color: Colors.amber, fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // [新增] 信号端口单行状态显示组件（含实时值与行为标签）
  Widget _buildSignalValueRow({
    required String label,
    required SignalPort port,
    required bool isInput,
    required Color color,
  }) {
    final bool isDigital = port.type == SignalType.digital;
    // 数字信号：显示 0/1 状态灯；模拟信号：显示数值
    final String valueStr = isDigital
        ? (port.value > 0.5 ? '● 1' : '○ 0')
        : port.value.toStringAsFixed(2);
    final String behaviorStr = isInput
        ? (port.inBehavior != SignalInputBehavior.none ? port.inBehavior.label.split('(').first.trim() : '')
        : (port.outBehavior != SignalOutputBehavior.none ? port.outBehavior.label.split('(').first.trim() : '');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
          const SizedBox(width: 6),
          Text(valueStr, style: TextStyle(fontSize: 11, color: color)),
          if (behaviorStr.isNotEmpty) ...[
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                behaviorStr,
                style: const TextStyle(fontSize: 9, color: Colors.grey),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}