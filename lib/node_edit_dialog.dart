import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models.dart';
import 'providers.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

class NodeEditDialog extends ConsumerStatefulWidget {
  final String nodeId;
  const NodeEditDialog({super.key, required this.nodeId});

  @override
  ConsumerState<NodeEditDialog> createState() => _NodeEditDialogState();
}

class _NodeEditDialogState extends ConsumerState<NodeEditDialog> {
  late TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    final node = ref.read(canvasProvider).nodes.firstWhere((n) => n.id == widget.nodeId);
    _nameCtrl = TextEditingController(text: node.name);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  /// 统一的防丢数据更新函数
  void _dispatchUpdate(ProductionNode updatedNode) {
    ref.read(canvasProvider.notifier).updateNodeComplete(updatedNode.id, updatedNode);
  }

  @override
  Widget build(BuildContext context) {
    // 监听对应节点状态 (实时获取最新的堆叠、连线等外部影响的状态)
    final node = ref.watch(canvasProvider).nodes.firstWhere((n) => n.id == widget.nodeId);

    // 建立本地临时状态副本以便在弹窗中编辑
    List<InputPort> tempInputs = List.from(node.inputs);
    List<OutputPort> tempOutputs = List.from(node.outputs);

    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children:[
          const Text('节点详细配置', style: TextStyle(fontSize: 16)),
          // 【核心修复 2】: 实时显示且不可编辑的唯一 ID
          SelectableText('ID: ${node.id.split('-').first}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
      content: SizedBox(
        width: 450,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children:[
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: '节点名称'),
                onChanged: (val) => _dispatchUpdate(node.copyWith(name: val)),
              ),
              const SizedBox(height: 10),
              
              DropdownButtonFormField<ProcessCategory>(
                value: node.category,
                decoration: const InputDecoration(labelText: '工艺分类'),
                items: ProcessCategory.values.map((cat) => DropdownMenuItem(
                  value: cat,
                  child: Text(cat.displayName),
                )).toList(),
                onChanged: (val) {
                  if (val != null) {
                    final updatedNode = node.copyWith(category: val);
                    _dispatchUpdate(updatedNode);
                  }
                },
              ),
              const SizedBox(height: 10),
              
              // 【核心修复 5】: 建设模板 (建设所需资源配置)
              const Text('建设资源模板 (Blueprint Cost)', style: TextStyle(fontWeight: FontWeight.bold)),
              ...node.constructionCost.entries.map((entry) {
                return Row(
                  children:[
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        initialValue: entry.key,
                        decoration: const InputDecoration(
                          labelText: '资源名称',
                          isDense: true,
                        ),
                        onChanged: (val) {
                          final newCost = Map<String, double>.from(node.constructionCost);
                          final value = newCost[entry.key] ?? 0;
                          newCost.remove(entry.key);
                          newCost[val] = value;
                          _dispatchUpdate(node.copyWith(constructionCost: newCost));
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        initialValue: entry.value.toString(),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '数量',
                          isDense: true,
                        ),
                        onChanged: (val) {
                          final newCost = Map<String, double>.from(node.constructionCost);
                          newCost[entry.key] = double.tryParse(val) ?? 0;
                          _dispatchUpdate(node.copyWith(constructionCost: newCost));
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle, color: Colors.red, size: 16),
                      onPressed: () {
                        final newCost = Map<String, double>.from(node.constructionCost)..remove(entry.key);
                        _dispatchUpdate(node.copyWith(constructionCost: newCost));
                      },
                    )
                  ],
                );
              }),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('添加建设所需资源'),
                onPressed: () {
                  final newCost = Map<String, double>.from(node.constructionCost)..putIfAbsent('新资源', () => 100);
                  _dispatchUpdate(node.copyWith(constructionCost: newCost));
                },
              ),

              // 特性3: 如果是逻辑控制卡片，显示自动化指令配置面板
              if (node.category == ProcessCategory.control) ...[
                const Divider(),
                const Text('逻辑自动化配置', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                DropdownButtonFormField<String>(
                  value: node.logicAction,
                  decoration: const InputDecoration(labelText: '执行指令'),
                  items: const[
                    DropdownMenuItem(value: 'build', child: Text('指令: 建设 (仅激活蓝图)')),
                    DropdownMenuItem(value: 'stack', child: Text('指令: 增加堆叠 (自动建设)')),
                    DropdownMenuItem(value: 'start', child: Text('指令: 启动运行')),
                    DropdownMenuItem(value: 'stop', child: Text('指令: 停止运行')),
                    DropdownMenuItem(value: 'dismantle', child: Text('指令: 减少堆叠/拆除')),
                  ],
                  onChanged: (val) {
                    final updatedNode = node.copyWith(logicAction: val);
                    _dispatchUpdate(updatedNode);
                  },
                ),
                // 目标节点ID输入框
                TextField(
                  controller: TextEditingController(text: node.logicTargetNodeId),
                  decoration: const InputDecoration(labelText: '目标节点ID'),
                  onChanged: (val) {
                    final updatedNode = node.copyWith(logicTargetNodeId: val.isEmpty ? null : val);
                    _dispatchUpdate(updatedNode);
                  },
                ),
                const SizedBox(height: 10),
                // [新增] 条件控制配置
                const Text('条件控制配置', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)),
                DropdownButtonFormField<String>(
                  value: node.logicCondition,
                  decoration: const InputDecoration(labelText: '触发条件'),
                  items: const[
                    DropdownMenuItem(value: null, child: Text('无条件执行')),
                    DropdownMenuItem(value: 'greater_than', child: Text('库存大于')),
                    DropdownMenuItem(value: 'less_than', child: Text('库存小于')),
                    DropdownMenuItem(value: 'greater_equal', child: Text('库存大于等于')),
                    DropdownMenuItem(value: 'less_equal', child: Text('库存小于等于')),
                    DropdownMenuItem(value: 'equal', child: Text('库存等于')),
                    DropdownMenuItem(value: 'not_equal', child: Text('库存不等于')),
                    DropdownMenuItem(value: 'running', child: Text('目标运行中')),
                    DropdownMenuItem(value: 'not_running', child: Text('目标未运行')),
                    DropdownMenuItem(value: 'built', child: Text('目标已建设')),
                    DropdownMenuItem(value: 'not_built', child: Text('目标未建设')),
                  ],
                  onChanged: (val) {
                    final updatedNode = node.copyWith(logicCondition: val);
                    _dispatchUpdate(updatedNode);
                  },
                ),
                // 条件阈值输入
                if (node.logicCondition != null && 
                    !['running', 'not_running', 'built', 'not_built'].contains(node.logicCondition))
                  TextField(
                    controller: TextEditingController(text: node.conditionValue?.toString()),
                    decoration: const InputDecoration(labelText: '条件阈值'),
                    keyboardType: TextInputType.number,
                    onChanged: (val) {
                      final updatedNode = node.copyWith(conditionValue: double.tryParse(val));
                      _dispatchUpdate(updatedNode);
                    },
                  ),
                // 监测目标节点ID输入框
                if (node.logicCondition != null && 
                    !['running', 'not_running', 'built', 'not_built'].contains(node.logicCondition))
                  TextField(
                    controller: TextEditingController(text: node.conditionTargetNodeId),
                    decoration: const InputDecoration(labelText: '监测目标节点ID'),
                    onChanged: (val) {
                      final updatedNode = node.copyWith(conditionTargetNodeId: val.isEmpty ? null : val);
                      _dispatchUpdate(updatedNode);
                    },
                  ),
              ],
              
              // [新增] 逻辑运算器配置
              if (node.category == ProcessCategory.control) ...[
                const Divider(),
                const Text('运算器配置', style: TextStyle(fontWeight: FontWeight.bold)),
                DropdownButtonFormField<LogicOperator>(
                  value: node.logicOp,
                  items: LogicOperator.values.map((op) => DropdownMenuItem(
                    value: op,
                    child: Text(op.name.toUpperCase()),
                  )).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      _dispatchUpdate(node.copyWith(logicOp: val));
                    }
                  },
                ),
                // 信号端口管理...
                TextButton(
                  onPressed: () {
                    final newIn = [...node.signalInputs, SignalPort(id: _uuid.v4(), name: 'sig_in')];
                    _dispatchUpdate(node.copyWith(signalInputs: newIn));
                  },
                  child: const Text('添加信号输入端口'),
                ),
                TextButton(
                  onPressed: () {
                    final newOut = [...node.signalOutputs, SignalPort(id: _uuid.v4(), name: 'sig_out')];
                    _dispatchUpdate(node.copyWith(signalOutputs: newOut));
                  },
                  child: const Text('添加信号输出端口'),
                )
              ],
              
              const Divider(),
              const Text('输入端口 (Inputs)', style: TextStyle(fontWeight: FontWeight.bold)),
              ...tempInputs.asMap().entries.map((entry) => Row(
                children:[
                  Expanded(flex: 3, child: TextFormField(
                    initialValue: entry.value.itemName,
                    decoration: const InputDecoration(labelText: '名称', isDense: true),
                    onChanged: (val) {
                      final updatedPort = entry.value.copyWith(itemName: val);
                      tempInputs[entry.key] = updatedPort;
                      final updatedNode = node.copyWith(inputs: tempInputs);
                      _dispatchUpdate(updatedNode);
                    },
                  )),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: TextFormField(
                    initialValue: entry.value.rate.toString(),
                    decoration: const InputDecoration(labelText: '速率', isDense: true),
                    keyboardType: TextInputType.number,
                    onChanged: (val) {
                      final updatedPort = entry.value.copyWith(rate: double.tryParse(val) ?? 1.0);
                      tempInputs[entry.key] = updatedPort;
                      final updatedNode = node.copyWith(inputs: tempInputs);
                      _dispatchUpdate(updatedNode);
                    },
                  )),
                  const SizedBox(width: 8),
                  Expanded(flex: 1, child: TextFormField(
                    initialValue: entry.value.unit,
                    decoration: const InputDecoration(labelText: '单位', isDense: true),
                    onChanged: (val) {
                      final updatedPort = entry.value.copyWith(unit: val);
                      tempInputs[entry.key] = updatedPort;
                      final updatedNode = node.copyWith(inputs: tempInputs);
                      _dispatchUpdate(updatedNode);
                    },
                  )),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                    onPressed: () {
                      tempInputs.removeAt(entry.key);
                      final updatedNode = node.copyWith(inputs: tempInputs);
                      _dispatchUpdate(updatedNode);
                    },
                  )
                ],
              )),
              TextButton.icon(
                icon: const Icon(Icons.add), label: const Text('添加输入'),
                onPressed: () {
                  tempInputs.add(InputPort(itemName: '新原料', rate: 1.0));
                  final updatedNode = node.copyWith(inputs: tempInputs);
                  _dispatchUpdate(updatedNode);
                },
              ),
              const Divider(),
              const Text('输出端口 (Outputs)', style: TextStyle(fontWeight: FontWeight.bold)),
              ...tempOutputs.asMap().entries.map((entry) => Row(
                children:[
                  Expanded(flex: 3, child: TextFormField(
                    initialValue: entry.value.itemName,
                    decoration: const InputDecoration(labelText: '名称', isDense: true),
                    onChanged: (val) {
                      final updatedPort = entry.value.copyWith(itemName: val);
                      tempOutputs[entry.key] = updatedPort;
                      final updatedNode = node.copyWith(outputs: tempOutputs);
                      _dispatchUpdate(updatedNode);
                    },
                  )),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: TextFormField(
                    initialValue: entry.value.rate.toString(),
                    decoration: const InputDecoration(labelText: '速率', isDense: true),
                    keyboardType: TextInputType.number,
                    onChanged: (val) {
                      final updatedPort = entry.value.copyWith(rate: double.tryParse(val) ?? 1.0);
                      tempOutputs[entry.key] = updatedPort;
                      final updatedNode = node.copyWith(outputs: tempOutputs);
                      _dispatchUpdate(updatedNode);
                    },
                  )),
                  const SizedBox(width: 8),
                  Expanded(flex: 1, child: TextFormField(
                    initialValue: entry.value.unit,
                    decoration: const InputDecoration(labelText: '单位', isDense: true),
                    onChanged: (val) {
                      final updatedPort = entry.value.copyWith(unit: val);
                      tempOutputs[entry.key] = updatedPort;
                      final updatedNode = node.copyWith(outputs: tempOutputs);
                      _dispatchUpdate(updatedNode);
                    },
                  )),
                  // 污染标记开关
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children:[
                      Switch(
                        value: entry.value.isPollutant,
                        onChanged: (val) {
                          final updatedPort = entry.value.copyWith(isPollutant: val);
                          tempOutputs[entry.key] = updatedPort;
                          final updatedNode = node.copyWith(outputs: tempOutputs);
                          _dispatchUpdate(updatedNode);
                        },
                      ),
                      const Text('污染', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                  // 删除该输出端口按钮
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                    onPressed: () {
                      tempOutputs.removeAt(entry.key);
                      final updatedNode = node.copyWith(outputs: tempOutputs);
                      _dispatchUpdate(updatedNode);
                    },
                  )
                ],
              )),
              TextButton.icon(
                icon: const Icon(Icons.add), label: const Text('添加输出'),
                onPressed: () {
                  tempOutputs.add(OutputPort(itemName: '新产品', rate: 1.0));
                  final updatedNode = node.copyWith(outputs: tempOutputs);
                  _dispatchUpdate(updatedNode);
                },
              ),
            ],
          ),
        ),
      ),
      actions:[TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
    );
  }
}
