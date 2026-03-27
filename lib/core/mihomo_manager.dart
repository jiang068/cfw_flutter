import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
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
  WebSocket? _trafficSocket;

  // 状态通知器（UI 层通过 ValueListenableBuilder 订阅）
  final ValueNotifier<bool> isLoadingProxies = ValueNotifier<bool>(false);
  final ValueNotifier<List<String>> groupNames = ValueNotifier<List<String>>(<String>[]);
  final ValueNotifier<Map<String, dynamic>> proxiesData = ValueNotifier<Map<String, dynamic>>(<String, dynamic>{});
  final ValueNotifier<List<LogItem>> logs = ValueNotifier<List<LogItem>>(<LogItem>[]);
  final ValueNotifier<String> coreVersion = ValueNotifier<String>('Unknown');
  final ValueNotifier<Map<String, dynamic>> config = ValueNotifier<Map<String, dynamic>>(<String, dynamic>{
    'port': 7891,
    'allow-lan': false,
    'ipv6': false,
    'log-level': 'info',
    'mode': 'rule',
  });
  // 混合配置状态（可由 UI 弹窗编辑并持久化）
  final ValueNotifier<bool> isMixinEnabled = ValueNotifier<bool>(false);
  final ValueNotifier<String> mixinText = ValueNotifier<String>('');
  // 高级 TUN 配置（仅本地持久化，以便 UI 可编辑/保存）
  final ValueNotifier<Map<String, dynamic>> tunAdvanced = ValueNotifier<Map<String, dynamic>>(<String, dynamic>{});
  // 系统代理状态持久化（UI 可订阅）
  final ValueNotifier<bool> isSystemProxyEnabled = ValueNotifier<bool>(false);
  // 开机自启状态（Windows）
  final ValueNotifier<bool> isAutoStartEnabled = ValueNotifier<bool>(false);
  // 防火墙状态（是否允许 mihomo.exe 通过防火墙）
  final ValueNotifier<bool> isFirewallAllowed = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isFirewallLoading = ValueNotifier<bool>(false);
  // 服务模式状态（是否以任务计划方式运行）
  final ValueNotifier<bool> isServiceModeEnabled = ValueNotifier<bool>(false);
  
  // 记录代理组的折叠状态 (true 为折叠，false 为展开)
  final Map<String, ValueNotifier<bool>> groupCollapseStates = {};

  ValueNotifier<bool> getGroupCollapseState(String groupName) {
    if (!groupCollapseStates.containsKey(groupName)) {
      groupCollapseStates[groupName] = ValueNotifier<bool>(false); // 默认不折叠
    }
    return groupCollapseStates[groupName]!;
  }
  
  // 配置文件列表状态
  final ValueNotifier<List<File>> profiles = ValueNotifier<List<File>>([]);
  final ValueNotifier<String> activeProfilePath = ValueNotifier<String>('');
  
  // 外部下载请求使用的独立 Dio
  final Dio _extDio = Dio();

  // 网速状态
  final ValueNotifier<String> upSpeed = ValueNotifier<String>('0 B/s');
  final ValueNotifier<String> downSpeed = ValueNotifier<String>('0 B/s');

  String get _homeDir {
    final profile = Platform.environment['USERPROFILE'] ?? '';
    return '$profile\\.config\\cfw_flutter';
  }

  String get _runningConfigPath {
    return '$_homeDir\\config.yaml';
  }

  Future<void> _ensureCoreResources() async {
    final List<String> resourceFiles = ['geoip.metadb', 'geosite.dat', 'Country.mmdb'];
    final exeDir = Directory.current.path; // 程序运行目录

    for (var fileName in resourceFiles) {
      final targetFile = File('$_homeDir\\$fileName');
      if (!await targetFile.exists()) {
        // 尝试从程序根目录或 bin 目录查找并拷贝
        File sourceFile = File('$exeDir\\$fileName');
        if (!await sourceFile.exists()) {
          sourceFile = File('$exeDir\\bin\\$fileName');
        }

        if (await sourceFile.exists()) {
          debugPrint('🚚 [资源初始化] 正在拷贝 $fileName 到 Home 目录...');
          if (!(await targetFile.parent.exists())) await targetFile.parent.create(recursive: true);
          await sourceFile.copy(targetFile.path);
        } else {
          debugPrint('⚠️ [资源警告] 未能找到基础资源 $fileName，内核可能尝试自行下载。');
        }
      }
    }
  }

  /// 启动内核（强杀旧进程 -> 启动 -> 轮询连接与初始化）
  /// 启动内核（强杀旧进程 -> 兜底配置 -> 启动 -> 轮询连接与初始化）
  Future<void> startMihomo({String exe = './mihomo.exe', List<String> args = const ['-f', 'config.yaml', '-d', '.']}) async {
    try {
      // 初始化系统级别的状态
      try {
        isAutoStartEnabled.value = await SystemToolManager.isAutoStartEnabled();
      } catch (_) {
        isAutoStartEnabled.value = false;
      }
      try {
        isFirewallAllowed.value = await SystemToolManager.isFirewallRuleExists();
      } catch (_) {
        isFirewallAllowed.value = false;
      }
      try {
        isServiceModeEnabled.value = await SystemToolManager.isServiceModeEnabled();
      } catch (_) {
        isServiceModeEnabled.value = false;
      }
      
      // 强杀残留进程
      try {
        // 核心修复：改为异步执行，绝不阻塞 UI 线程
        await Process.run('taskkill', ['/F', '/IM', 'mihomo.exe']);
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 500));

      // ==========================================
      // 核心修复：保底配置文件生成逻辑（简化，交由命令行参数接管 external-controller/secret）
      // ==========================================
      // 1. 确保 Home 目录存在
      final homeDirectory = Directory(_homeDir);
      if (!await homeDirectory.exists()) {
        await homeDirectory.create(recursive: true);
      }

      // 2. 将保底配置写入 Home 目录
      final configFile = File(_runningConfigPath);
      if (!await configFile.exists()) {
        debugPrint('⚠️ [内核守护] 未检测到 config.yaml，正在生成默认保底配置...');
        // 注意：这里的多行字符串必须绝对顶格，否则 YAML 解析会因为缩进报错而导致内核忽略配置！
        const fallbackConfig = '''mixed-port: 7891
allow-lan: false
mode: rule
log-level: info
ipv6: false
dns:
  enable: true
  listen: 0.0.0.0:1053
  nameserver:
    - 114.114.114.114
    - 223.5.5.5
    - 8.8.8.8
proxies: []
proxy-groups: []
rules:
  - MATCH,DIRECT
''';
        await configFile.writeAsString(fallbackConfig, flush: true);
      }

      // 1. 动态生成安全的 API 端口和 Secret
      final random = Random();
      final apiPort = 50000 + random.nextInt(9000); // 50000 - 58999
      final apiSecret = List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

      // 2. 重新配置 Dio 实例
      _dio.options.baseUrl = 'http://127.0.0.1:$apiPort';
      _dio.options.headers['Authorization'] = 'Bearer $apiSecret';

      // 3. 强制注入命令行参数（覆盖 yaml 中的控制端口）
      // 3. 修改安全启动参数：指定 -d 为 Home 目录，-f 为 Home 目录下的 config.yaml
      // 3. 确保基础资源文件（GeoIP等）已到位
      await _ensureCoreResources();

      // 4. 修改安全启动参数：指定 -d 为 Home 目录，-f 为 Home 目录下的 config.yaml
      final safeArgs = [
        '-d', _homeDir,
        '-f', _runningConfigPath,
        '-ext-ctl', '127.0.0.1:$apiPort',
        '-secret', apiSecret,
      ];

      _mihomoProcess = await Process.start(exe, safeArgs, runInShell: false);

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

      // 尝试在启动后连接内核并初始化状态（极速轮询，最多 ~5 秒）
      for (int i = 0; i < 50; i++) { // 最多等 5 秒
        try {
          await Future.delayed(const Duration(milliseconds: 100));
          // 用最轻量的 version 接口测试内核是否就绪
          final res = await _dio.get('/version');
          if (res.statusCode == 200) {
            debugPrint('🟢 [内核] 启动就绪，耗时: ${i * 100} ms');
            await _loadLocalSettings(); // 先将本地记忆注入内核
            await syncConfig();         // 再同步一次状态给 UI
            await fetchVersion();
            await fetchProxies();
            // 启动时加载本地配置文件列表
            try {
              await loadProfiles();
              // 冷启动后，内核默认读取的是 config.yaml，我们需要将持久化的 activeProfile 重新注入内核
              if (activeProfilePath.value.isNotEmpty && activeProfilePath.value != _runningConfigPath) {
                final activeFile = File(activeProfilePath.value);
                if (await activeFile.exists()) {
                  debugPrint('🔄 [配置管理] 启动恢复: 正在应用上次记忆的配置');
                  await _dio.put('/configs', queryParameters: {'force': 'false'}, data: {'path': activeFile.absolute.path});
                  await syncConfig();
                  await fetchProxies();
                } else {
                  // 文件丢失，回退为默认配置
                  activeProfilePath.value = _runningConfigPath;
                  await _saveLocalSettings();
                }
              }
            } catch (e) {
              debugPrint('📂 [配置管理] 启动加载 profiles 失败: $e');
            }
            connectLogSocket();
                  // 连接流量 WebSocket（实时上/下行）
                  try {
                    await connectTrafficSocket();
                  } catch (e) {
                    debugPrint('📡 [流量] 连接失败: $e');
                  }
            break;
          }
        } catch (_) {}
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Mihomo start failed: $e');
    }
  }

  /// 关闭/清理资源
  Future<void> dispose() async {
    try {
      // 退出前强制还原系统代理
      if (isSystemProxyEnabled.value) {
        try {
          await SystemToolManager.disableSystemProxy();
          debugPrint('🧹 [清理] 退出时已还原系统代理');
        } catch (_) {}
      }
    } catch (_) {}

    try {
      await _logSocket?.close();
    } catch (_) {}

    try {
      await _trafficSocket?.close();
    } catch (_) {}
    
    try {
      if (_mihomoProcess != null) {
        Process.runSync('taskkill', ['/F', '/T', '/PID', _mihomoProcess!.pid.toString()]);
        debugPrint('🛑 [进程管理] 已强杀 Mihomo 进程树 (PID: ${_mihomoProcess!.pid})');
      }
    } catch (_) {}
  }

  /// 同步配置（/configs）到 config Notifier
  Future<void> syncConfig() async {
    try {
      final res = await _dio.get('/configs');
      final data = res.data;
      // 优先使用 mixed-port，如果为 0 或 null，再使用 port，保底为 7891
      int currentPort = 7891;
      try {
        currentPort = (data['mixed-port'] ?? data['port'] ?? 7891) is int
            ? (data['mixed-port'] ?? data['port'] ?? 7891)
            : int.parse((data['mixed-port'] ?? data['port'] ?? 7891).toString());
      } catch (_) {
        currentPort = 7891;
      }
      if (currentPort == 0) currentPort = 7891;

      config.value = {
        'port': currentPort,
        'allow-lan': data['allow-lan'] ?? false,
        'ipv6': data['ipv6'] ?? false,
        'tun-enable': data['tun']?['enable'] ?? false,
        'bind-address': data['bind-address'] ?? '*',
        'log-level': data['log-level'] ?? 'info',
        'mode': data['mode'] ?? 'rule',
      };
    } catch (e) {
      debugPrint('🌐 [API 请求失败] syncConfig: $e');
      rethrow;
    }
  }

  String get _profilesDir {
    final profile = Platform.environment['USERPROFILE'] ?? '';
    return '$profile\\.config\\cfw_flutter\\profiles';
  }

  String get _profileUrlsPath {
    final profile = Platform.environment['USERPROFILE'] ?? '';
    return '$profile\\.config\\cfw_flutter\\profile_urls.json';
  }

  /// 从 URL 下载并应用配置
  Future<void> downloadProfile(String url) async {
    if (url.isEmpty || !url.startsWith('http')) throw Exception('无效的 URL');
    try {
      final res = await _extDio.get(url);
      final content = res.data.toString();
      // 用时间戳生成文件名
      final filename = 'profile_${DateTime.now().millisecondsSinceEpoch}.yaml';
      final file = File('$_profilesDir\\$filename');
      if (!(await file.parent.exists())) await file.parent.create(recursive: true);
      await file.writeAsString(content);

      // 保存 URL 映射记录以便后续更新
      final urlMapFile = File(_profileUrlsPath);
      Map<String, dynamic> urls = {};
      if (await urlMapFile.exists()) urls = jsonDecode(await urlMapFile.readAsString());
      urls[file.absolute.path] = url;
      if (!(await urlMapFile.parent.exists())) await urlMapFile.parent.create(recursive: true);
      await urlMapFile.writeAsString(jsonEncode(urls));

      await loadProfiles();
      await switchProfile(file);
    } catch (e) {
      throw Exception('下载失败: $e');
    }
  }

  // 核心修复 3：接入原生的 FilePicker
  Future<void> importProfile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['yaml', 'yml'],
      );

      if (result != null && result.files.single.path != null) {
        final sourceFile = File(result.files.single.path!);
        final filename = sourceFile.path.split(Platform.pathSeparator).last;
        final dir = Directory(_profilesDir);
        if (!await dir.exists()) await dir.create(recursive: true);
        final targetFile = File('${dir.path}\\$filename');

        await sourceFile.copy(targetFile.path);
        debugPrint('📂 [配置管理] 成功导入文件: $filename');

        await loadProfiles();
        await switchProfile(targetFile);
      }
    } catch (e) {
      throw Exception('导入文件失败: $e');
    }
  }

  /// 更新所有从 URL 下载的配置
  Future<void> updateAllProfiles() async {
    final urlMapFile = File(_profileUrlsPath);
    if (!await urlMapFile.exists()) return;
    try {
      final urls = jsonDecode(await urlMapFile.readAsString()) as Map<String, dynamic>;
      for (var entry in urls.entries) {
        final path = entry.key;
        final url = entry.value;
        if (File(path).existsSync()) {
          debugPrint('🔄 [配置更新] 正在更新: $path');
          final res = await _extDio.get(url);
          await File(path).writeAsString(res.data.toString());
        }
      }
      // 如果当前正在使用某配置，重新触发重载
      if (activeProfilePath.value.isNotEmpty) {
        await switchProfile(File(activeProfilePath.value));
      }
    } catch (e) {
      throw Exception('更新全部失败: $e');
    }
  }

  /// 新建并保存本地配置
  Future<void> createNewProfile(String name, String content) async {
    final dir = Directory(_profilesDir);
    if (!await dir.exists()) await dir.create(recursive: true); // 确保目录存在

    final safeName = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final file = File('${dir.path}\\$safeName.yaml');

    // flush: true 强制立刻刷入 Windows 磁盘，防止 loadProfiles 读不到
    await file.writeAsString(content, flush: true);
    // 等待文件系统稳定（Windows 上可能需要短暂延迟释放句柄）
    await Future.delayed(const Duration(milliseconds: 100));

    await loadProfiles();
    await switchProfile(file);
  }

  /// 加载本地配置文件列表
  Future<void> loadProfiles() async {
    try {
      final dir = Directory(_profilesDir);
      if (!await dir.exists()) await dir.create(recursive: true);

      final List<File> files = [];
      final defaultConfig = File(_runningConfigPath);
      if (await defaultConfig.exists()) {
        files.add(defaultConfig);
      }

      final localFiles = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.yaml') || f.path.endsWith('.yml')).toList();
      files.addAll(localFiles);

      // 核心修复：强制切断引用，确保 ValueNotifier 必定触发 UI 重绘
      profiles.value = [];
      await Future.delayed(const Duration(milliseconds: 50)); // 给予 UI 线程响应清空状态的极短间隙
      profiles.value = List<File>.from(files);

      debugPrint('📂 [配置管理] 成功加载 ${files.length} 个配置文件');

      if (activeProfilePath.value.isEmpty && defaultConfig.existsSync()) {
        activeProfilePath.value = defaultConfig.absolute.path;
      }
    } catch (e) {
      debugPrint('📂 [配置管理] 加载列表失败: $e');
    }
  }

  Future<void> switchProfile(File file) async {
    debugPrint('📂 [配置管理] 尝试切换配置: ${file.path}');
    try {
      // 核心修复：不再覆写 config.yaml，直接将选中的绝对路径传给内核
      final absolutePath = file.absolute.path;
      await _dio.put('/configs', queryParameters: {'force': 'false'}, data: {'path': absolutePath});
      
      activeProfilePath.value = absolutePath;
      await syncConfig();
      await fetchProxies();
      
      // 持久化当前选中的路径
      try {
        await _saveLocalSettings();
      } catch (e) {
        debugPrint('💾 [持久化] 保存当前配置路径失败: $e');
      }
      debugPrint('✅ [配置管理] 切换成功: $absolutePath');
    } on DioException catch (e) {
      // 如果配置有语法错误，内核会报错。此时强行回退到默认的 config.yaml
      debugPrint('❌ [配置管理] 切换失败，正在回退到默认配置...');
      activeProfilePath.value = _runningConfigPath;
      try {
        await _dio.put('/configs', queryParameters: {'force': 'false'}, data: {'path': _runningConfigPath});
        await syncConfig();
        await fetchProxies();
        await _saveLocalSettings();
      } catch (_) {}

      final errorMsg = e.response?.data?['message'] ?? e.message ?? '未知语法错误';
      throw Exception('配置文件格式有误，内核拒绝加载，已回退到默认配置:\n$errorMsg');
    } catch (e) {
      throw Exception('文件读取或切换失败: $e');
    }
  }

/// 更新某个配置项
  Future<void> updateConfig(String key, dynamic value) async {
    debugPrint('🔧 [配置更新] 准备修改: $key -> $value');
    try {
      await _dio.patch('/configs', data: {key: value});
      await syncConfig();
      // 持久化本地设置
      try {
        await _saveLocalSettings();
      } catch (e) {
        debugPrint('💾 [持久化] 保存失败: $e');
      }
      debugPrint('✅ [配置更新] 成功: $key -> $value');
    } catch (e) {
      // ⚠️ 删除了 rethrow; 防止 UI 崩溃
      debugPrint('❌ [配置更新] 失败: $key, 错误: $e (内核可能未启动)');
    }
  }

  /// 更新 TUN 模式状态
  Future<void> updateTunConfig(bool enable) async {
    debugPrint('🔧 [TUN更新] 准备修改: enable -> $enable');
    try {
      await _dio.patch('/configs', data: {
        "tun": {"enable": enable}
      });
      await syncConfig();
      try {
        await _saveLocalSettings();
      } catch (e) {
        debugPrint('💾 [持久化] 保存失败: $e');
      }
      debugPrint('✅ [TUN更新] 成功');
    } catch (e) {
      // ⚠️ 删除了 rethrow; 防止 UI 崩溃
      debugPrint('❌ [TUN更新] 失败: 错误: $e (内核可能未启动)');
    }
  }

  /// 切换服务模式（使用任务计划），并刷新状态
  Future<void> toggleServiceMode(bool enable) async {
    try {
      await SystemToolManager.toggleServiceMode(enable);
      isServiceModeEnabled.value = await SystemToolManager.isServiceModeEnabled();
    } catch (e) {
      debugPrint('🛠️ [服务模式] 切换失败: $e');
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
          if (key != 'GLOBAL') groups.add(key); // 剔除 GLOBAL
        }
      });

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
      final baseUrl = _dio.options.baseUrl.replaceFirst('http', 'ws');
      final secret = _dio.options.headers['Authorization']?.replaceAll('Bearer ', '') ?? '';
      _logSocket = await WebSocket.connect('$baseUrl/logs?level=info&token=$secret');
      _logSocket!.listen((data) {
        try {
          final json = jsonDecode(data);
          parseLog((json['type'] ?? 'info').toString(), json['payload'] ?? '');
        } catch (_) {
          // 避免在频繁的日志回调中打印信息导致 UI/控制台阻塞
        }
      }, onError: (e) {
        // 保留错误打印以便定位连接/协议问题
        debugPrint('log socket error: $e');
      });
    } catch (e) {
          debugPrint('connectLogSocket failed: $e');
    }
  }

  String _formatBytes(int bytes) {
    if (bytes == 0) return '0 B/s';
    if (bytes < 1024) return bytes.toString() + ' B/s';
    if (bytes < 1024 * 1024) return (bytes / 1024).toStringAsFixed(1) + ' KB/s';
    return (bytes / (1024 * 1024)).toStringAsFixed(2) + ' MB/s';
  }

  Future<void> connectTrafficSocket() async {
    try {
      final baseUrl = _dio.options.baseUrl.replaceFirst('http', 'ws');
      final secret = _dio.options.headers['Authorization']?.replaceAll('Bearer ', '') ?? '';
      _trafficSocket = await WebSocket.connect('$baseUrl/traffic?token=$secret');
      _trafficSocket!.listen((data) {
        try {
          final json = jsonDecode(data);
          upSpeed.value = _formatBytes(json['up'] ?? 0);
          downSpeed.value = _formatBytes(json['down'] ?? 0);
        } catch (_) {}
      }, onError: (_) {}, onDone: () {});
    } catch (e) {
      debugPrint('Traffic socket error: $e');
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
    final port = config.value['port'] ?? 7891;
    if (enabled) {
      try {
        await SystemToolManager.enableSystemProxy(port);
        isSystemProxyEnabled.value = true;
        try {
          await _saveLocalSettings();
        } catch (e) {
          debugPrint('💾 [持久化] 保存失败: $e');
        }
      } catch (e) {
        if (kDebugMode) print('enableSystemProxy failed: $e');
        isSystemProxyEnabled.value = false;
      }
    } else {
      try {
        await SystemToolManager.disableSystemProxy();
        isSystemProxyEnabled.value = false;
        try {
          await _saveLocalSettings();
        } catch (e) {
          debugPrint('💾 [持久化] 保存失败: $e');
        }
      } catch (e) {
        if (kDebugMode) print('disableSystemProxy failed: $e');
      }
    }
  }

  /// 切换开机自启动
  Future<void> toggleAutoStart(bool enable) async {
    await SystemToolManager.setAutoStart(enable);
    try {
      isAutoStartEnabled.value = await SystemToolManager.isAutoStartEnabled();
    } catch (_) {
      isAutoStartEnabled.value = false;
    }
  }

  /// 触发防火墙切换
  Future<void> toggleFirewall() async {
    isFirewallLoading.value = true;
    try {
      final targetState = !isFirewallAllowed.value;
      isFirewallAllowed.value = await SystemToolManager.toggleFirewallRule(targetState);
      debugPrint('🛡️ [防火墙] 当前状态: ${isFirewallAllowed.value}');
    } finally {
      isFirewallLoading.value = false;
    }
  }

  /// 获取配置文件文本
  Future<String> getConfigFileContent() async {
    try {
      final file = File(_runningConfigPath);
      if (await file.exists()) {
        return await file.readAsString();
      }
      return '未找到 config.yaml';
    } catch (e) {
      return '读取配置失败: $e';
    }
  }

  /// 调用内核 DNS 查询
  Future<Map<String, dynamic>> queryDns(String host, String type) async {
    try {
      debugPrint('🌍 [DNS查询] 请求: $host, 类型: $type');
      final res = await _dio.get('/dns/query', queryParameters: {'name': host, 'type': type});
      return res.data;
    } on DioException catch (e) {
      debugPrint('🌍 [DNS查询] Dio拦截异常: ${e.response?.statusCode}');
      if (e.response != null) {
        try {
          final data = e.response?.data;
          if (data is Map && data.containsKey('message')) return {'error': data['message']};
          return {'error': data ?? 'HTTP ${e.response?.statusCode}: 解析失败'};
        } catch (_) {
          return {'error': 'HTTP ${e.response?.statusCode}: 解析失败'};
        }
      }
      return {'error': e.message};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// 将窗口位置/大小保存到本地 settings.json
  Future<void> saveWindowBounds(double w, double h, double x, double y) async {
    try {
      final file = File(_settingsPath);
      Map<String, dynamic> map = {};
      if (await file.exists()) {
        try {
          final s = await file.readAsString();
          map = (jsonDecode(s) as Map<String, dynamic>?) ?? {};
        } catch (_) {
          map = {};
        }
      } else {
        if (!(await file.parent.exists())) await file.parent.create(recursive: true);
      }
      map['window_width'] = w;
      map['window_height'] = h;
      map['window_x'] = x;
      map['window_y'] = y;
      await file.writeAsString(jsonEncode(map));
    } catch (e) {
      debugPrint('💾 [持久化] 保存窗口信息失败: $e');
    }
  }

  /// 从本地 settings.json 获取窗口位置/大小（不存在时返回 null）
  Future<Map<String, double>?> getWindowBounds() async {
    try {
      final file = File(_settingsPath);
      if (!await file.exists()) return null;
      final s = await file.readAsString();
      final map = jsonDecode(s) as Map<String, dynamic>?;
      if (map == null) return null;
      if (map.containsKey('window_width') && map.containsKey('window_height')) {
        double? w = (map['window_width'] is num) ? (map['window_width'] as num).toDouble() : double.tryParse(map['window_width'].toString());
        double? h = (map['window_height'] is num) ? (map['window_height'] as num).toDouble() : double.tryParse(map['window_height'].toString());
        double? x = (map['window_x'] is num) ? (map['window_x'] as num).toDouble() : double.tryParse(map['window_x']?.toString() ?? '0');
        double? y = (map['window_y'] is num) ? (map['window_y'] as num).toDouble() : double.tryParse(map['window_y']?.toString() ?? '0');
        if (w != null && h != null && x != null && y != null) {
          return {'w': w, 'h': h, 'x': x, 'y': y};
        }
      }
    } catch (e) {
      debugPrint('💾 [持久化] 读取窗口信息失败: $e');
    }
    return null;
  }

  /// 切换混合配置开关并持久化
  Future<void> toggleMixin(bool enable) async {
    isMixinEnabled.value = enable;
    try {
      await _saveLocalSettings();
    } catch (e) {
      debugPrint('💾 [持久化] 保存 mixin 状态失败: $e');
    }
  }

  /// 保存混合配置文本
  Future<void> saveMixinText(String text) async {
    mixinText.value = text;
    try {
      await _saveLocalSettings();
    } catch (e) {
      debugPrint('💾 [持久化] 保存 mixin 文本失败: $e');
    }
  }

  /// 保存高级 TUN 配置到本地 settings
  Future<void> saveTunAdvancedConfig(Map<String, dynamic> data) async {
    tunAdvanced.value = Map<String, dynamic>.from(data);
    try {
      await _saveLocalSettings();
    } catch (e) {
      debugPrint('💾 [持久化] 保存 tun 高级配置失败: $e');
    }
  }

  /// 切换代理组折叠状态并持久化
  Future<void> toggleGroupCollapse(String groupName) async {
    final state = getGroupCollapseState(groupName);
    state.value = !state.value;
    try {
      await _saveLocalSettings();
    } catch (e) {
      debugPrint('💾 [持久化] 保存折叠状态失败: $e');
    }
  }

  // ---- 本地配置持久化（Windows 用户目录下 .config/cfw_flutter/settings.json） ----
  String get _settingsPath {
    final profile = Platform.environment['USERPROFILE'] ?? '';
    return '$profile\\.config\\cfw_flutter\\settings.json';
  }

  Future<void> _saveLocalSettings() async {
    try {
      final file = File(_settingsPath);
      if (!(await file.parent.exists())) await file.parent.create(recursive: true);
      final current = Map<String, dynamic>.from(config.value);
      current['system-proxy'] = isSystemProxyEnabled.value;
      // mixin 状态
      current['mixin_enabled'] = isMixinEnabled.value;
      current['mixin_text'] = mixinText.value;
      // tun 高级配置
      current['tun_advanced'] = tunAdvanced.value;
      
      // 序列化折叠状态
      Map<String, bool> collapseMap = {};
      groupCollapseStates.forEach((key, notifier) {
        collapseMap[key] = notifier.value;
      });
      current['collapse_states'] = collapseMap;
      // 保存当前选中的配置文件路径
      current['active_profile'] = activeProfilePath.value;
      // 如果已有窗口信息则合并（避免覆盖）
      try {
        if (await file.exists()) {
          final s = await file.readAsString();
          final prev = (jsonDecode(s) as Map<String, dynamic>?) ?? {};
          // 保留 prev 的 window_* 字段（如果存在）
          for (var k in ['window_width', 'window_height', 'window_x', 'window_y']) {
            if (prev.containsKey(k) && !current.containsKey(k)) current[k] = prev[k];
          }
        }
      } catch (_) {}
      await file.writeAsString(jsonEncode(current));
    } catch (e) {
      debugPrint('💾 [持久化] 保存失败: $e');
    }
  }

  Future<void> _loadLocalSettings() async {
    try {
      final file = File(_settingsPath);
      if (await file.exists()) {
        final str = await file.readAsString();
        final map = jsonDecode(str) as Map<String, dynamic>;
        debugPrint('💾 [持久化] 读取到本地配置，准备注入...');
        // 恢复本地保存的 mixin 与 tun 高级配置到内存
        try {
          if (map.containsKey('mixin_enabled')) isMixinEnabled.value = map['mixin_enabled'] == true;
          if (map.containsKey('mixin_text')) mixinText.value = (map['mixin_text'] ?? '').toString();
          if (map.containsKey('tun_advanced') && map['tun_advanced'] is Map) tunAdvanced.value = Map<String, dynamic>.from(map['tun_advanced']);
          
          // 恢复折叠状态
          if (map.containsKey('collapse_states') && map['collapse_states'] is Map) {
            final states = map['collapse_states'] as Map;
            states.forEach((k, v) {
              groupCollapseStates[k.toString()] = ValueNotifier<bool>(v == true);
            });
          }
          
          // 恢复当前选中的配置文件路径
          if (map.containsKey('active_profile')) {
            activeProfilePath.value = map['active_profile']?.toString() ?? '';
          }
        } catch (_) {}
        // 注入回内核内存
        await _dio.patch('/configs', data: map);
        // 恢复系统代理状态
        if (map['system-proxy'] == true) await setSystemProxyEnabled(true);
      }
    } catch (e) {
      debugPrint('💾 [持久化] 读取失败: $e');
    }
  }
}
