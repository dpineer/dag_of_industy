import 'package:flutter/material.dart';

// [新增] 真无限画板的坐标系核心参数
const double CENTER_OFFSET = 100000.0; // 虚拟原点偏移量 (用于将逻辑坐标映射到物理画板中心)
const double CANVAS_PHYSICAL_SIZE = 200000.0; // 物理画板极大尺寸
final GlobalKey canvasKey = GlobalKey();      // 全局定标，用于精准测算鼠标坐标
