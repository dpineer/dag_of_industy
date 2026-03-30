import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart'; // 顶部导入依赖
import 'models.dart';
import 'providers.dart';
import 'node_widget.dart'; // 见后文

void main() {
  runApp(const ProviderScope(child: IndustrialSimulatorApp()));
}

class IndustrialSimulatorApp extends StatelessWidget {
  const IndustrialSimulatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '工业生产链模拟器',
      // 配置亮色主题
      theme: ThemeData(
        brightness: Brightness.light,
        colorSchemeSeed: Colors.blueGrey,
        scaffoldBackgroundColor: const Color(0xFFF0F4F8),
      ),
      // 配置暗色主题
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.blueGrey,
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      themeMode: ThemeMode.system, // 自动跟随 Linux 系统暗色模式设置
      home: const CanvasScreen(),
    );
  }
}

class CanvasScreen extends ConsumerWidget {
  const CanvasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canvasState = ref.watch(canvasProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('生产网络 DAG 规划区'),
        actions:[
          IconButton(
            icon: const Icon(Icons.add_box),
            tooltip: '添加测试工序',
            onPressed: () {
              ref.read(canvasProvider.notifier).addNode(ProductionNode(
                name: '新工序',
                category: ProcessCategory.reaction,
                position: const Offset(300, 200),
                inputs: [InputPort(itemName: '原料', rate: 10)],
                outputs:[
                  OutputPort(itemName: '产品', rate: 5),
                  OutputPort(itemName: '副产品', rate: 4, isPollutant: false)
                ],
                constructionCost: {'钢材': 100, '电子元件': 50}, // [新增] 建设资源
              ));
            },
          ),
          IconButton(
            icon: const Icon(Icons.analytics),
            tooltip: '网络审查',
            onPressed: () => _showAnalysisDialog(context, ref),
          ),
          // [新增] 实时状态机启停控制
          IconButton(
            icon: Icon(
              canvasState.isSimulating ? Icons.pause_circle_filled : Icons.play_circle_filled,
              color: canvasState.isSimulating ? Colors.orange : Colors.green,
              size: 28,
            ),
            tooltip: canvasState.isSimulating ? '暂停模拟网络' : '启动模拟网络',
            onPressed: () {
              ref.read(canvasProvider.notifier).toggleSimulation();
            },
          ),
          // [新增] 逻辑自动化控制按钮
          IconButton(
            icon: const Icon(Icons.auto_mode, color: Colors.purple),
            tooltip: '执行逻辑自动化指令',
            onPressed: () {
              ref.read(canvasProvider.notifier).executeLogicTick();
            },
          ),
          // 周期图表按钮更替图标为显式的图表
          IconButton(
            icon: const Icon(Icons.bar_chart, color: Colors.blueAccent),
            tooltip: '生成周期分析图表',
            onPressed: () => _runSimulationAndShowChart(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: '导出配置',
            onPressed: () async {
              try {
                // Linux 本地默认测试路径，实际工程可引入 file_picker 选择路径
                await ref.read(canvasProvider.notifier).exportToFile('./production_graph.json');
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('成功导出至 ./production_graph.json')));
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出失败: $e')));
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: '导入配置',
            onPressed: () async {
              try {
                await ref.read(canvasProvider.notifier).importFromFile('./production_graph.json');
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('导入成功')));
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败: $e')));
              }
            },
          ),
        ],
      ),
      body: InteractiveViewer(
        boundaryMargin: const EdgeInsets.all(double.infinity),
        minScale: 0.1,
        maxScale: 3.0,
          child: Container(
            width: 5000,
            height: 5000,
            // 【修复调色】: 移除硬编码颜色，跟随暗黑/高亮模式的底层背景色
            color: Theme.of(context).scaffoldBackgroundColor, 
            child: Stack(
              clipBehavior: Clip.none,
              children:[
                // 1. 绘制已连接线段与正在拖拽的活动线段
                CustomPaint(
                  size: const Size(5000, 5000),
                  painter: _ConnectionPainter(
                    nodes: canvasState.nodes,
                    connections: canvasState.connections,
                    activeSourceNodeId: canvasState.activeDragSourceNodeId,
                    activeDragSourcePortId: canvasState.activeDragSourcePortId,
                    activeDragCurrentPosition: canvasState.activeDragCurrentPosition,
                  ),
                ),
                // 2. 绘制各个节点卡片
                ...canvasState.nodes.map((node) => Positioned(
                  // 【修复刷新 Bug】: 使用 ValueKey(node.id) 替代 ObjectKey(node)
                  // 这样既能保证性能，实现丝滑拖动，又能让底层机制正确识别并重绘内部状态
                  key: ValueKey(node.id), 
                  left: node.position.dx,
                  top: node.position.dy,
                  child: NodeWidget(node: node),
                )),
              ],
            ),
          ),
      ),
    );
  }

  void _showAnalysisDialog(BuildContext context, WidgetRef ref) {
    final analyzer = ref.read(canvasProvider.notifier).getAnalyzer();
    final warnings = analyzer.validateNetwork();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('网络拓扑审查'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: warnings.isEmpty 
            ?[const Text("✅ 生产网络 DAG 校验通过，无逻辑断链。")]
            : warnings.map((w) => Text("⚠️ $w", style: TextStyle(
                color: w.contains('违规') ? Colors.red : Colors.orange
              ))).toList(),
        ),
        actions:[
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))
        ],
      ),
    );
  }

  // 运行逻辑及图表渲染方法
  void _runSimulationAndShowChart(BuildContext context, WidgetRef ref) {
    final nodes = ref.read(canvasProvider).nodes;
    if (nodes.isEmpty) return;

    // 简单周期计算模型: 假设处理周期 = 100 / (节点所有输出端口速率总和 + 0.1) 
    // 实际工程中这里应调用 GraphAnalyzer.calculateCost / CycleTime 引擎
    final List<BarChartGroupData> barGroups =[];
    int index = 0;
    double maxCycleTime = 0;

    for (var node in nodes) {
      double totalRate = node.outputs.fold(0.0, (sum, out) => sum + out.rate);
      double cycleTime = totalRate > 0 ? (100.0 / totalRate) : 0; // 模拟周期
      if (cycleTime > maxCycleTime) maxCycleTime = cycleTime;

      barGroups.add(
        BarChartGroupData(
          x: index,
          barRods:[
            BarChartRodData(
              toY: cycleTime,
              color: node.category.themeColor, // 使用节点所属分类颜色
              width: 20,
              borderRadius: BorderRadius.circular(4),
            )
          ],
        )
      );
      index++;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.5,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children:[
              const Text('生产周期分析图表 (瓶颈追踪)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Expanded(
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: maxCycleTime * 1.2, // 顶部留白
                    barGroups: barGroups,
                    titlesData: FlTitlesData(
                      show: true,
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            if (value.toInt() >= nodes.length) return const SizedBox.shrink();
                            // X轴显示节点名称的截断短名
                            String name = nodes[value.toInt()].name;
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(name.length > 4 ? '${name.substring(0,4)}..' : name, 
                                 style: const TextStyle(fontSize: 10)),
                            );
                          },
                        ),
                      ),
                      leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                      ),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    gridData: const FlGridData(show: true, drawVerticalLine: false),
                    borderData: FlBorderData(show: false),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionPainter extends CustomPainter {
  final List<ProductionNode> nodes;
  final List<Connection> connections;
  final String? activeSourceNodeId;
  final String? activeDragSourcePortId;
  final Offset? activeDragCurrentPosition;

  _ConnectionPainter({
    required this.nodes,
    required this.connections,
    this.activeSourceNodeId,
    this.activeDragSourcePortId,
    this.activeDragCurrentPosition,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blueGrey
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final activePaint = Paint()
      ..color = Colors.blueAccent
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // 获取端口在画板上的绝对坐标 (基于卡片布局的偏移推算)
    Offset getPortGlobalOffset(String nodeId, bool isOutput, int portIndex) {
      final node = nodes.firstWhere((n) => n.id == nodeId);
      // X轴：输入在左(0)，输出在右(250)；Y轴：标题高40 + 端口偏移(约30*index)
      double dx = node.position.dx + (isOutput ? 250 : 0);
      double dy = node.position.dy + 60 + (portIndex * 35);
      return Offset(dx, dy);
    }

    // 绘制已有连接
    for (var conn in connections) {
      final sNode = nodes.where((n) => n.id == conn.sourceNodeId).firstOrNull;
      final tNode = nodes.where((n) => n.id == conn.targetNodeId).firstOrNull;
      if (sNode == null || tNode == null) continue;

      int sIndex = sNode.outputs.indexWhere((p) => p.id == conn.sourcePortId);
      int tIndex = tNode.inputs.indexWhere((p) => p.id == conn.targetPortId);

      if (sIndex < 0 || tIndex < 0) continue;

      final start = getPortGlobalOffset(sNode.id, true, sIndex);
      final end = getPortGlobalOffset(tNode.id, false, tIndex);
      _drawBezierCurve(canvas, start, end, paint);
    }

    // 绘制正在拖拽的连接
    if (activeSourceNodeId != null && activeDragCurrentPosition != null) {
      final sNode = nodes.firstWhere((n) => n.id == activeSourceNodeId);
      // 使用状态中的activeDragSourcePortId来确定拖拽的端口
      int sIndex = sNode.outputs.indexWhere((p) => p.id == activeDragSourcePortId); 
      final start = getPortGlobalOffset(sNode.id, true, sIndex != -1 ? sIndex : 0);
      _drawBezierCurve(canvas, start, activeDragCurrentPosition!, activePaint);
    }
  }

  void _drawBezierCurve(Canvas canvas, Offset start, Offset end, Paint paint) {
    final path = Path();
    path.moveTo(start.dx, start.dy);
    // 控制点设定为水平方向偏移，以形成 S 型贝塞尔曲线
    double controlOffset = (end.dx - start.dx).abs() * 0.5;
    path.cubicTo(
      start.dx + controlOffset, start.dy,
      end.dx - controlOffset, end.dy,
      end.dx, end.dy,
    );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ConnectionPainter oldDelegate) => true;
}
