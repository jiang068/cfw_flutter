import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'system_tool_manager.dart';

/// 简化并净化后的 Mihomo 管理器 - 纯逻辑层，无 UI 依赖
class LogItem {
  final String time;
  final String type;
  final String msg;
  final String rule;
  final String proxy;
  final String destination;

  LogItem({required this.time, required this.type, required this.msg, this.rule = '', this.proxy = '', this.destination = ''});
}

class MihomoManager {
  MihomoManager._internal() {
    _dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:9090'));
  }
  static final MihomoManager _instance = MihomoManager._internal();
  factory MihomoManager() => _instance;

  // Networking & process
  late final Dio _dio;
  Process? _mihomoProcess;
  WebSocket? _logSocket;

  // 状态通知器（UI 层通过 ValueListenableBuilder 订阅）
  final ValueNotifier<bool> isLoadingProxies = ValueNotifier<bool>(false);
  final ValueNotifier<List<String>> groupNames = ValueNotifier<List<String>>(<String>[]);
  final ValueNotifier<Map<String, dynamic>> proxiesData = ValueNotifier<Map<String, dynamic>>(<String, dynamic>{});
  final ValueNotifier<List<LogItem>> logs = ValueNotifier<List<LogItem>>(<LogItem>[]);
  final ValueNotifier<String> coreVersion = ValueNotifier<String>('Unknown');
  final ValueNotifier<Map<String, dynamic>> config = ValueNotifier<Map<String, dynamic>>(<String, dynamic>{
    'port': 7890,
    'allow-lan': false,
    'ipv6': false,
    'log-level': 'info',
    'mode': 'rule',
  });
  // 系统代理状态持久化（UI 可订阅）
  final ValueNotifier<bool> isSystemProxyEnabled = ValueNotifier<bool>(false);

  /// 启动内核（强杀旧进程 -> 启动 -> 轮询连接与初始化）
  Future<void> startMihomo({String exe = './mihomo.exe', List<String> args = const ['-f', 'config.yaml', '-d', '.']}) async {
    try {
      // 强杀残留进程
      try {
        Process.runSync('taskkill', ['/F', '/IM', 'mihomo.exe']);
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 500));

      _mihomoProcess = await Process.start(exe, args, runInShell: false);

      // 监听内核 stdout/stderr 输出，便于排查
      try {
        _mihomoProcess!.stdout.transform(utf8.decoder).listen((data) => debugPrint('🟢 [内核] ${data.trim()}'));
      } catch (e) {
        debugPrint('🟢 [内核] stdout 监听失败: $e');
      }
      try {
        _mihomoProcess!.stderr.transform(utf8.decoder).listen((data) => debugPrint('🔴 [内核报错] ${data.trim()}'));
      } catch (e) {
        debugPrint('🔴 [内核报错] stderr 监听失败: $e');
      }
      // 监听进程退出
      _mihomoProcess!.exitCode.then((code) {
        debugPrint('❌ 内核进程已意外退出！ exitCode: $code');
      });

      // 尝试在启动后连接内核并初始化状态
      for (int i = 0; i < 10; i++) {
        try {
          await Future.delayed(const Duration(seconds: 1));
          await syncConfig();
          await fetchVersion();
          await fetchProxies();
          connectLogSocket();
          break;
        } catch (e) {
          debugPrint('启动初始化重试时出错: $e');
        }
      }
    } catch (e) {
      if (kDebugMode) print('Mihomo start failed: $e');
    }
  }

  /// 关闭/清理资源
  Future<void> dispose() async {
    try {
      await _logSocket?.close();
    } catch (_) {}
    try {
      _mihomoProcess?.kill();
    } catch (_) {}
  }

  /// 同步配置（/configs）到 config Notifier
  Future<void> syncConfig() async {
    try {
      final res = await _dio.get('/configs');
      final data = res.data;
      // 优先使用 mixed-port，如果为 0 或 null，再使用 port，保底为 7890
      int currentPort = 7890;
      try {
        currentPort = (data['mixed-port'] ?? data['port'] ?? 7890) is int
            ? (data['mixed-port'] ?? data['port'] ?? 7890)
            : int.parse((data['mixed-port'] ?? data['port'] ?? 7890).toString());
      } catch (_) {
        currentPort = 7890;
      }
      if (currentPort == 0) currentPort = 7890;

      config.value = {
        'port': currentPort,
        'allow-lan': data['allow-lan'] ?? false,
        'ipv6': data['ipv6'] ?? false,
        'log-level': data['log-level'] ?? 'info',
        'mode': data['mode'] ?? 'rule',
      };
    } catch (e) {
      debugPrint('🌐 [API 请求失败] syncConfig: $e');
      rethrow;
    }
  }

  /// 更新某个配置项
  Future<void> updateConfig(String key, dynamic value) async {
    try {
      await _dio.patch('/configs', data: {key: value});
      await syncConfig();
    } catch (e) {
      debugPrint('🌐 [API 请求失败] updateConfig: $e');
      rethrow;
    }
  }

  /// 获取内核版本信息
  Future<void> fetchVersion() async {
    try {
      final res = await _dio.get('/version');
      String v = res.data['version'] ?? '';
      bool isMeta = res.data['meta'] == true;
      bool isPremium = res.data['premium'] == true;
      coreVersion.value = "$v${isMeta ? ' Mihomo' : (isPremium ? ' Premium' : '')}";
    } catch (e) {
      debugPrint('🌐 [API 请求失败] fetchVersion: $e');
    }
  }

  /// 获取代理组与节点
  Future<void> fetchProxies() async {
    isLoadingProxies.value = true;
    try {
      final res = await _dio.get('/proxies');
      Map<String, dynamic> allProxies = Map<String, dynamic>.from(res.data['proxies'] ?? {});

      List<String> groups = [];
      allProxies.forEach((key, value) {
        if (value is Map && (value['type'] == 'Selector' || value['type'] == 'URLTest' || value['type'] == 'Fallback')) {
          if (key != 'GLOBAL') groups.add(key);
        }
      });
      if (allProxies.containsKey('GLOBAL')) groups.insert(0, 'GLOBAL');

      proxiesData.value = allProxies;
      groupNames.value = groups;
    } catch (e) {
      debugPrint('🌐 [API 请求失败] fetchProxies: $e');
    } finally {
      isLoadingProxies.value = false;
    }
  }

  /// 切换代理组的节点
  Future<void> switchProxy(String groupName, String nodeName) async {
    try {
      await _dio.put('/proxies/$groupName', data: {"name": nodeName});
      await fetchProxies();
    } catch (e) {
      debugPrint('🌐 [API 请求失败] switchProxy: $e');
    }
  }

  /// 建立 WebSocket 日志连接，收到消息后调用 parseLog
  Future<void> connectLogSocket() async {
    try {
      _logSocket = await WebSocket.connect('ws://127.0.0.1:9090/logs?level=info');
      _logSocket!.listen((data) {
        try {
          final json = jsonDecode(data);
          parseLog((json['type'] ?? 'info').toString(), json['payload'] ?? '');
            } catch (e) {
              debugPrint('log parse error: $e');
            }
      }, onError: (e) {
            debugPrint('log socket error: $e');
      }, onDone: () {
            debugPrint('log socket closed');
      });
    } catch (e) {
          debugPrint('connectLogSocket failed: $e');
    }
  }

  /// 解析日志（保留原始正则与逻辑），并通过 logs Notifier 发布
  void parseLog(String type, String payload) {
    String time = "${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}:${DateTime.now().second.toString().padLeft(2, '0')}";
    String msg = payload;
    String rule = '';
    String proxy = '';
    String dest = '';

    type = type.toLowerCase();
    if (type == 'warning') type = 'warn';
    if (type == 'err') type = 'error';

  RegExp matchReg = RegExp(r"^.*?(\[.*?\])\s+(.*?)\s+(?:(match\s+.*?|doesn't match any rule)\s+)?using\s+([\s\S]*)$");
  RegExp dialReg = RegExp(r"^.*?(\[.*?\])\s*dial\s+(.*?)\s*(?:\(match\s+(.*?)\)\s+)?(.*?)\s*error:\s*([\s\S]*)$");

    var m = matchReg.firstMatch(payload);
    var me = dialReg.firstMatch(payload);

    if (m != null) {
      msg = "${m.group(1)!.trim()} ${m.group(2)!.trim()}";
      rule = m.group(3) != null
          ? (m.group(3)!.contains("doesn't match") ? "No Match" : m.group(3)!.replaceAll(RegExp(r'^match\s+', caseSensitive: false), '').trim())
          : "GLOBAL/DIRECT";
      proxy = m.group(4)!.trim();
      var parts = m.group(2)!.split("-->");
      dest = parts.length > 1 ? parts[1].trim() : '';
    } else if (me != null) {
      rule = me.group(3) != null ? me.group(3)!.replaceAll(RegExp(r'\/$'), '').trim() : "GLOBAL/DIRECT";
      msg = "${me.group(1)!.trim()} ${me.group(4)!.trim()} error: ${me.group(5)!.trim()}";
      type = 'error';
      proxy = me.group(2)!.trim();
      var parts = me.group(4)!.split("-->");
      dest = parts.length > 1 ? parts[1].trim() : '';
    }

    final newLog = LogItem(time: time, type: type, msg: msg, rule: rule, proxy: proxy, destination: dest);
    final list = List<LogItem>.from(logs.value);
    list.insert(0, newLog);
    if (list.length > 500) list.removeLast();
    logs.value = list;
  }

  /// 设置/切换系统代理（会调用 SystemToolManager）
  Future<void> setSystemProxyEnabled(bool enabled) async {
    final port = config.value['port'] ?? 7890;
    if (enabled) {
      try {
        await SystemToolManager.enableSystemProxy(port);
        isSystemProxyEnabled.value = true;
      } catch (e) {
        if (kDebugMode) print('enableSystemProxy failed: $e');
        isSystemProxyEnabled.value = false;
      }
    } else {
      try {
        await SystemToolManager.disableSystemProxy();
        isSystemProxyEnabled.value = false;
      } catch (e) {
        if (kDebugMode) print('disableSystemProxy failed: $e');
      }
    }
  }
}
