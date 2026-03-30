import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

// [新增] 节点运行时状态机
enum NodeStatus {
  idle('待机', Colors.grey),
  running('运行中', Colors.green),
  starved('缺料停机', Colors.red),
  blocked('产物堵塞', Colors.orange);

  final String label;
  final Color color;
  const NodeStatus(this.label, this.color);
}

enum ProcessCategory {
  forming(1, '初创成型', Colors.brown),
  deforming(2, '塑性变形', Colors.orange),
  separating(3, '分离切割', Colors.red),
  joining(4, '连接接合', Colors.blue),
  coating(5, '表面涂覆', Colors.cyan),
  modifying(6, '改性处理', Colors.purple),
  storing(7, '存储', Colors.grey),
  quantityChange(8, '数量变更', Colors.teal),
  moving(9, '位移搬运', Colors.green),
  positioning(10, '固定定位', Colors.indigo),
  inspecting(11, '检验测试', Colors.amber),
  mechanical(12, '机械过程', Colors.deepOrange),
  thermal(13, '热力过程', Colors.redAccent),
  reaction(14, '反应过程', Colors.pink),
  membrane(15, '膜与特种分离', Colors.lightBlue),
  control(16, '控制与外部性', Colors.blueGrey);

  final int code;
  final String displayName;
  final Color themeColor;
  const ProcessCategory(this.code, this.displayName, this.themeColor);
}

abstract class Port {
  final String id;
  final String itemName;
  final double rate;
  final double unitCost;
  final String unit; // [新增] 计量单位

  Port({
    String? id,
    required this.itemName,
    this.rate = 1.0,
    this.unitCost = 0.0,
    this.unit = 'kg', // 默认单位
  }) : id = id ?? _uuid.v4();

  Map<String, dynamic> toJson();
}

class InputPort extends Port {
  final bool isRequired;
  
  InputPort({
    super.id,
    required super.itemName,
    super.rate,
    super.unitCost,
    super.unit,
    this.isRequired = true,
  });

  InputPort copyWith({String? itemName, double? rate, double? unitCost, String? unit, bool? isRequired}) {
    return InputPort(
      id: id,
      itemName: itemName ?? this.itemName,
      rate: rate ?? this.rate,
      unitCost: unitCost ?? this.unitCost,
      unit: unit ?? this.unit,
      isRequired: isRequired ?? this.isRequired,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'id': id, 'itemName': itemName, 'rate': rate, 'unitCost': unitCost, 'unit': unit, 'isRequired': isRequired,
  };
  
  factory InputPort.fromJson(Map<String, dynamic> json) => InputPort(
    id: json['id'], itemName: json['itemName'], rate: json['rate'], unitCost: json['unitCost'], unit: json['unit'] ?? 'kg', isRequired: json['isRequired'] ?? true,
  );
}

class OutputPort extends Port {
  final bool isPollutant;
  final bool isDiscarded;
  final bool isConstructionMaterial; // [新增] 标识是否为建设资源

  OutputPort({
    super.id,
    required super.itemName,
    super.rate,
    super.unitCost,
    super.unit,
    this.isPollutant = false,
    this.isDiscarded = false,
    this.isConstructionMaterial = false, // [新增] 默认不是建设资源
  });

  OutputPort copyWith({String? itemName, double? rate, double? unitCost, String? unit, bool? isPollutant, bool? isDiscarded, bool? isConstructionMaterial}) {
    return OutputPort(
      id: id,
      itemName: itemName ?? this.itemName,
      rate: rate ?? this.rate,
      unitCost: unitCost ?? this.unitCost,
      unit: unit ?? this.unit,
      isPollutant: isPollutant ?? this.isPollutant,
      isDiscarded: isDiscarded ?? this.isDiscarded,
      isConstructionMaterial: isConstructionMaterial ?? this.isConstructionMaterial,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'id': id, 'itemName': itemName, 'rate': rate, 'unitCost': unitCost, 'unit': unit, 'isPollutant': isPollutant, 'isDiscarded': isDiscarded, 'isConstructionMaterial': isConstructionMaterial,
  };
  
  factory OutputPort.fromJson(Map<String, dynamic> json) => OutputPort(
    id: json['id'], itemName: json['itemName'], rate: json['rate'], unitCost: json['unitCost'], unit: json['unit'] ?? 'kg', isPollutant: json['isPollutant'] ?? false, isDiscarded: json['isDiscarded'] ?? false, isConstructionMaterial: json['isConstructionMaterial'] ?? false,
  );
}

class ProductionNode {
  final String id;
  final String name;
  final ProcessCategory category;
  final List<InputPort> inputs;
  final List<OutputPort> outputs;
  final double maintenanceRate;
  final double failureProbability;
  final double runningCost;
  final Offset position;
  
  // [新增] 运行时相关属性
  final double maxCapacity;
  final Map<String, double> inputInventory;
  final Map<String, double> outputInventory;
  final double progress;
  final NodeStatus status;
  
  // 特性4: 堆叠机制
  final int stackCount; // 卡片堆叠数量 (默认 1)
  
  // 特性2 & 特性3: 生命周期与建设模板
  final bool isBuilt;   // 是否已建设 (false 为透明蓝图状态)
  final bool isRunning; // 当前是否处于启动运行状态
  final Map<String, double> constructionCost; // 建设所需资源 (如: {'钢材': 500, '电子元件': 50})
  
  // 特性3: 逻辑控制卡片专用属性 (当 category 为 ProcessCategory.control 时启用)
  final String? logicTargetNodeId; // 控制目标节点 ID
  final String? logicAction;       // 自动化指令: 'start', 'stop', 'build', 'dismantle'
  final String? logicCondition;    // [新增] 逻辑条件类型
  final double? conditionValue;    // [新增] 条件阈值
  final String? conditionPortId;   // [新增] 条件监测端口ID
  final String? conditionTargetNodeId; // [新增] 条件监测目标节点ID

  ProductionNode({
    String? id,
    required this.name,
    required this.category,
    this.inputs = const[],
    this.outputs = const[],
    this.maintenanceRate = 1.0,
    this.failureProbability = 0.0,
    this.runningCost = 0.0,
    this.position = Offset.zero,
    this.maxCapacity = 100.0,
    this.inputInventory = const{},
    this.outputInventory = const{},
    this.progress = 0.0,
    this.status = NodeStatus.idle,
    this.stackCount = 1,
    this.isBuilt = true,
    this.isRunning = true,
    this.constructionCost = const {},
    this.logicTargetNodeId,
    this.logicAction,
    this.logicCondition,
    this.conditionValue,
    this.conditionPortId,
    this.conditionTargetNodeId,
  }) : id = id ?? _uuid.v4();

  ProductionNode copyWith({
    String? name,
    ProcessCategory? category,
    List<InputPort>? inputs,
    List<OutputPort>? outputs,
    double? maintenanceRate,
    double? failureProbability,
    double? runningCost,
    Offset? position,
    double? maxCapacity,
    Map<String, double>? inputInventory,
    Map<String, double>? outputInventory,
    double? progress,
    NodeStatus? status,
    int? stackCount,
    bool? isBuilt,
    bool? isRunning,
    Map<String, double>? constructionCost,
    String? logicTargetNodeId,
    String? logicAction,
    String? logicCondition,
    double? conditionValue,
    String? conditionPortId,
    String? conditionTargetNodeId,
  }) {
    return ProductionNode(
      id: id,
      name: name ?? this.name,
      category: category ?? this.category,
      inputs: inputs ?? this.inputs,
      outputs: outputs ?? this.outputs,
      maintenanceRate: maintenanceRate ?? this.maintenanceRate,
      failureProbability: failureProbability ?? this.failureProbability,
      runningCost: runningCost ?? this.runningCost,
      position: position ?? this.position,
      maxCapacity: maxCapacity ?? this.maxCapacity,
      inputInventory: inputInventory ?? this.inputInventory,
      outputInventory: outputInventory ?? this.outputInventory,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      stackCount: stackCount ?? this.stackCount,
      isBuilt: isBuilt ?? this.isBuilt,
      isRunning: isRunning ?? this.isRunning,
      constructionCost: constructionCost ?? this.constructionCost,
      logicTargetNodeId: logicTargetNodeId ?? this.logicTargetNodeId,
      logicAction: logicAction ?? this.logicAction,
      logicCondition: logicCondition ?? this.logicCondition,
      conditionValue: conditionValue ?? this.conditionValue,
      conditionPortId: conditionPortId ?? this.conditionPortId,
      conditionTargetNodeId: conditionTargetNodeId ?? this.conditionTargetNodeId,
    );
  }

  // 序列化时仅保存静态配置，忽略瞬态库存和进度
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category.name,
    'inputs': inputs.map((e) => e.toJson()).toList(),
    'outputs': outputs.map((e) => e.toJson()).toList(),
    'position': {'dx': position.dx, 'dy': position.dy},
    'maxCapacity': maxCapacity,
    'stackCount': stackCount,
    'isBuilt': isBuilt,
    'isRunning': isRunning,
    'constructionCost': constructionCost,
    'logicTargetNodeId': logicTargetNodeId,
    'logicAction': logicAction,
    'logicCondition': logicCondition, // [新增]
    'conditionValue': conditionValue, // [新增]
    'conditionPortId': conditionPortId, // [新增]
    'conditionTargetNodeId': conditionTargetNodeId, // [新增]
  };

  factory ProductionNode.fromJson(Map<String, dynamic> json) {
    return ProductionNode(
      id: json['id'],
      name: json['name'],
      category: ProcessCategory.values.firstWhere((e) => e.name == json['category']),
      inputs: (json['inputs'] as List).map((e) => InputPort.fromJson(e)).toList(),
      outputs: (json['outputs'] as List).map((e) => OutputPort.fromJson(e)).toList(),
      position: Offset(json['position']['dx'], json['position']['dy']),
      maxCapacity: json['maxCapacity'] ?? 100.0,
      stackCount: json['stackCount'] ?? 1,
      isBuilt: json['isBuilt'] ?? true,
      isRunning: json['isRunning'] ?? true,
      constructionCost: json['constructionCost'] ?? const {},
      logicTargetNodeId: json['logicTargetNodeId'],
      logicAction: json['logicAction'],
      logicCondition: json['logicCondition'], // [新增]
      conditionValue: json['conditionValue'] != null ? double.tryParse(json['conditionValue'].toString()) : null, // [新增]
      conditionPortId: json['conditionPortId'], // [新增]
      conditionTargetNodeId: json['conditionTargetNodeId'], // [新增]
    );
  }
}

class Connection {
  final String id;
  final String sourceNodeId;
  final String sourcePortId;
  final String targetNodeId;
  final String targetPortId;

  Connection({
    String? id,
    required this.sourceNodeId,
    required this.sourcePortId,
    required this.targetNodeId,
    required this.targetPortId,
  }) : id = id ?? _uuid.v4();

  Map<String, dynamic> toJson() => {
    'id': id, 'sourceNodeId': sourceNodeId, 'sourcePortId': sourcePortId, 'targetNodeId': targetNodeId, 'targetPortId': targetPortId,
  };

  factory Connection.fromJson(Map<String, dynamic> json) => Connection(
    id: json['id'], sourceNodeId: json['sourceNodeId'], sourcePortId: json['sourcePortId'], targetNodeId: json['targetNodeId'], targetPortId: json['targetPortId'],
  );
}
