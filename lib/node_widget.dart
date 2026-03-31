import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models.dart';
import 'providers.dart';
import 'node_edit_dialog.dart';

class NodeWidget extends ConsumerWidget {
  final ProductionNode node;

  const NodeWidget({super.key, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          if (node.category == ProcessCategory.control)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              margin: const EdgeInsets.only(bottom: 4),
              color: Colors.blueAccent.withOpacity(0.1),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children:[
                  const Icon(Icons.hub, size: 16, color: Colors.blueAccent),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children:[
                      Text("目标蓝图: ${node.logicTargetNodeId != null ? node.logicTargetNodeId!.substring(0,6) : '未绑定'}", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                      Text("控制指令: ${node.logicAction ?? '待配置'}", style: const TextStyle(fontSize: 10, color: Colors.orange)),
                    ],
                  ),
                ],
              ),
            ),
          
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
                    children: node.inputs.map((i) => _buildInputPort(context, ref, i)).toList()
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end, 
                    children: node.outputs.map((o) => _buildOutputPort(context, ref, o)).toList()
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

              if (node.status != NodeStatus.idle) {
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
                      color: node.category == ProcessCategory.storing 
                          ? Colors.blueAccent // 仓储卡片使用专用的水位颜色，其余沿用 status
                          : node.status.color,
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
        PopupMenuItem(value: 'delete', child: Text('删除该节点', style: TextStyle(color: Colors.red))),
      ],
    );

    if (result == 'edit' && context.mounted) {
      _showEditDialog(context, ref);
    } else if (result == 'delete') {
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
    // 接收连线的 DragTarget
    return DragTarget<String>(
      onAccept: (sourcePortData) {
        // sourcePortData 格式为 "nodeId:portId"
        ref.read(canvasProvider.notifier).finalizeConnection(node.id, port.id);
      },
      builder: (context, candidateData, rejectedData) {
        bool isHovered = candidateData.isNotEmpty;
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
                      "${port.itemName} (${port.rate}/${port.unit}/s)",
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

  Widget _buildOutputPort(BuildContext context, WidgetRef ref, OutputPort port) {
    double inv = node.outputInventory[port.id] ?? 0.0;
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
                    "${port.itemName} (${port.rate}/${port.unit}/s)", 
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
                  ref.read(canvasProvider.notifier).startConnectionDrag(node.id, port.id);
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
                  // 释放时无论是否命中目标，均清理拖拽状态
                  ref.read(canvasProvider.notifier).endConnectionDrag();
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
}