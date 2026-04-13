// --- START OF FILE api_server.dart ---
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'providers.dart';
import 'models.dart';

/// [Architecture] 本地 RESTful API 微服务网关
/// 暴露 Flutter 内部 Riverpod 状态机至外部跨语言后端服务
class ApiServer {
  final Ref ref;
  HttpServer? _server;

  ApiServer(this.ref);

  /// 启动监听服务
  Future<void> start({int port = 8080}) async {
    final router = Router();

    // CORS 头部中间件配置
    final corsHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Origin, Content-Type',
    };

    // [API: Read] 获取全局物理画板及全部节点拓扑网络状态
    router.get('/api/state', (Request request) {
      final state = ref.read(canvasProvider);
      final data = {
        'isSimulating': state.isSimulating,
        'nodes': state.nodes.map((n) => n.toJson()).toList(),
        'connections': state.connections.map((c) => c.toJson()).toList(),
      };
      return Response.ok(jsonEncode(data), headers: {
        'Content-Type': 'application/json',
        ...corsHeaders,
      });
    });

    // [API: Create] 注入/构造全新工业节点
    router.post('/api/node', (Request request) async {
      try {
        final payload = await request.readAsString();
        final json = jsonDecode(payload);
        final node = ProductionNode.fromJson(json);
        ref.read(canvasProvider.notifier).addNode(node);
        return Response.ok(jsonEncode({'status': 'success', 'id': node.id}), 
          headers: {...corsHeaders, 'Content-Type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
      }
    });

    // [API: Update] 高级覆写/编辑指定节点全量配置
    router.put('/api/node/<id>', (Request request, String id) async {
      try {
        final payload = await request.readAsString();
        final json = jsonDecode(payload);
        // 防御性校验，确保外部 ID 约束一致
        json['id'] = id; 
        final updatedNode = ProductionNode.fromJson(json);
        ref.read(canvasProvider.notifier).updateNodeComplete(id, updatedNode);
        return Response.ok(jsonEncode({'status': 'success'}), headers: corsHeaders);
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
      }
    });

    // [API: Delete] 销毁指定节点
    router.delete('/api/node/<id>', (Request request, String id) {
      ref.read(canvasProvider.notifier).removeNode(id);
      return Response.ok(jsonEncode({'status': 'deleted', 'id': id}), headers: corsHeaders);
    });

    // [API: Intervention] 上帝模式：物理/虚拟仓储干预
    router.post('/api/inventory', (Request request) async {
      try {
        final payload = await request.readAsString();
        final json = jsonDecode(payload);
        // 期望载荷: {"nodeId": "xxx", "portId": "yyy", "isInput": true, "amount": 1000.0}
        ref.read(canvasProvider.notifier).setInventory(
          json['nodeId'],
          json['portId'],
          json['isInput'] as bool,
          (json['amount'] as num).toDouble(),
        );
        return Response.ok(jsonEncode({'status': 'success'}), headers: corsHeaders);
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
      }
    });

    //[API: Control] 控制模拟器时钟与主进程的启停
    router.post('/api/simulation/toggle', (Request request) {
      ref.read(canvasProvider.notifier).toggleSimulation();
      final isSimulating = ref.read(canvasProvider).isSimulating;
      return Response.ok(jsonEncode({'status': 'success', 'isSimulating': isSimulating}), 
        headers: {...corsHeaders, 'Content-Type': 'application/json'});
    });

    // 挂载中间件，执行 OPTIONS 预检请求豁免
    Handler handler = const Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware((innerHandler) => (request) async {
              if (request.method == 'OPTIONS') return Response.ok('', headers: corsHeaders);
              return innerHandler(request);
            })
        .addHandler(router.call);

    // 绑定至 IPv4 任意地址 (允许跨机器被其它后端调用)
    // 如果端口被占用，尝试递增端口直到成功
    int currentPort = port;
    const int maxAttempts = 10;
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        _server = await io.serve(handler, InternetAddress.anyIPv4, currentPort);
        print('✅ [ApiServer] 跨语言后端网关已在端口 ${_server!.port} 启动监听');
        return;
      } on SocketException catch (e) {
        if (e.osError?.errorCode == 98 || e.message.contains('地址已在使用')) {
          // 端口被占用，尝试下一个端口
          print('⚠️ 端口 $currentPort 被占用，尝试端口 ${currentPort + 1}');
          currentPort++;
          continue;
        }
        rethrow;
      }
    }
    throw Exception('无法在端口 $port 到 $currentPort 之间找到可用端口');
  }

  void stop() {
    _server?.close(force: true);
    print('⛔ [ApiServer] 网关已关闭');
  }
}

/// 网关生命周期提供者，受控于 Riverpod 的资源回收机制
final apiServerProvider = Provider<ApiServer>((ref) {
  final server = ApiServer(ref);
  // 可根据配置中心或环境变量动态决定端口，当前预设为 8080
  server.start(port: 8080);
  ref.onDispose(() => server.stop());
  return server;
});
// --- END OF FILE api_server.dart ---