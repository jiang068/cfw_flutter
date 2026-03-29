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

  // 核心修复：坚固的本地测速缓存，防止被内核空数据覆盖
  final Map<String, int> proxyDelaysCache = {};
  // 核心修复：自动测速会话锁，防并发堵塞
  int _speedTestSessionId = 0;

  // 正在切换的配置文件路径 (用于 UI 动画显示)
  final ValueNotifier<String> switchingProfilePath = ValueNotifier<String>('');
  // 代理组折叠触发器 (用于 Sliver 架构极速重绘)
  final ValueNotifier<int> collapseTrigger = ValueNotifier<int>(0);

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
  
  // 外部下载请求使用的独立 Dio，伪装 User-Agent 强迫机场下发 YAML 配置
  final Dio _extDio = Dio(BaseOptions(
    headers: {'User-Agent': 'ClashforWindows/0.20.39'}
  ));

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

  Future<void> startMihomo({String exe = './mihomo.exe', List<String> args = const ['-f', 'config.yaml', '-d', '.']}) async {
    try {
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
      
      try {
        await Process.run('taskkill', ['/F', '/IM', 'mihomo.exe']);
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 500));

      final homeDirectory = Directory(_homeDir);
      if (!await homeDirectory.exists()) {
        await homeDirectory.create(recursive: true);
      }

      final configFile = File(_runningConfigPath);
      if (!await configFile.exists()) {
        debugPrint('⚠️ [内核守护] 未检测到 config.yaml，正在生成默认保底配置...');
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

      final random = Random();
      final apiPort = 50000 + random.nextInt(9000); // 50000 - 58999
      final apiSecret = List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

      _dio.options.baseUrl = 'http://127.0.0.1:$apiPort';
      _dio.options.headers['Authorization'] = 'Bearer $apiSecret';

      await _ensureCoreResources();

      final safeArgs = [
        '-d', _homeDir,
        '-f', _runningConfigPath,
        '-ext-ctl', '127.0.0.1:$apiPort',
        '-secret', apiSecret,
      ];

      _mihomoProcess = await Process.start(exe, safeArgs, runInShell: false);

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
      _mihomoProcess!.exitCode.then((code) {
        debugPrint('❌ 内核进程已意外退出！ exitCode: $code');
      });

      for (int i = 0; i < 50; i++) { // 最多等 5 秒
        try {
          await Future.delayed(const Duration(milliseconds: 100));
          final res = await _dio.get('/version');
          if (res.statusCode == 200) {
            debugPrint('🟢 [内核] 启动就绪，耗时: ${i * 100} ms');
            await _loadLocalSettings(); // 先将本地记忆注入内核
            await syncConfig();         // 再同步一次状态给 UI
            await fetchVersion();
            await fetchProxies();
            
            try {
              await loadProfiles();
              if (activeProfilePath.value.isNotEmpty && activeProfilePath.value != _runningConfigPath) {
                final activeFile = File(activeProfilePath.value);
                if (await activeFile.exists()) {
                  debugPrint('🔄 [配置管理] 启动恢复: 正在应用上次记忆的配置');
                  await _dio.put('/configs', queryParameters: {'force': 'false'}, data: {'path': activeFile.absolute.path});
                  await syncConfig();
                  await fetchProxies();
                } else {
                  activeProfilePath.value = _runningConfigPath;
                  await _saveLocalSettings();
                }
              }
            } catch (e) {
              debugPrint('📂 [配置管理] 启动加载 profiles 失败: $e');
            }
            connectLogSocket();
            try {
              await connectTrafficSocket();
            } catch (e) {
              debugPrint('📡 [流量] 连接失败: $e');
            }
            
            // 核心功能：应用冷启动完毕，自动测速激活配置
            runGlobalSpeedTest();
            break;
          }
        } catch (_) {}
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Mihomo start failed: $e');
    }
  }

  Future<void> dispose() async {
    _speedTestSessionId++; // 中断所有测速
    try {
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

  Future<void> syncConfig() async {
    try {
      final res = await _dio.get('/configs');
      final data = res.data;
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

  Future<Response> _smartFetchYaml(String url) async {
    final strategies = [
      {'ua': 'clash-verge/v1.7.7', 'suffix': ''},
      {'ua': 'clash.meta', 'suffix': 'flag=meta'},
      {'ua': 'ClashforWindows/0.20.39', 'suffix': ''},
      {'ua': 'clash', 'suffix': 'flag=clash'},
      {'ua': 'ClashforWindows/0.20.39', 'suffix': 'target=clash'},
    ];

    Response? lastResponse;
    for (var s in strategies) {
      String targetUrl = url;
      if (s['suffix']!.isNotEmpty) {
        targetUrl += (targetUrl.contains('?') ? '&' : '?') + s['suffix']!;
      }

      try {
        debugPrint('🌐 [智能嗅探] 尝试战术 -> UA: ${s['ua']}, URL: $targetUrl');
        final res = await _extDio.get(
          targetUrl,
          options: Options(
            headers: {
              'User-Agent': s['ua'],
              'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
            },
            validateStatus: (status) => true, 
          ),
        );

        if (res.statusCode == 200) {
          final contentLower = res.data.toString().toLowerCase();
          if (contentLower.contains('proxies:') || contentLower.contains('proxy-groups:')) {
            debugPrint('✅ [智能嗅探] 战术成功！命中 UA: ${s['ua']}');
            return res;
          }
        }
        lastResponse = res;
      } catch (e) {
        debugPrint('⚠️ [智能嗅探] 战术失败: $e');
      }
    }
    throw Exception('智能解析失败。服务器可能拒绝连接或返回了无法识别的纯 Base64。\n最后一次状态码: ${lastResponse?.statusCode}');
  }

  String _extractHeadersAsComments(Headers headers, String fallbackName) {
    String profileName = fallbackName;
    final cdList = headers['content-disposition'] ?? <String>[];
    if (cdList.isNotEmpty) {
      final cd = cdList.first;
      final utf8Match = RegExp(r"filename\s*\*=\s*UTF-8''([^;]+)", caseSensitive: false).firstMatch(cd);
      if (utf8Match != null) {
        profileName = Uri.decodeComponent(utf8Match.group(1)!);
      } else {
        final nameMatch = RegExp(r'filename="([^"]+)"', caseSensitive: false).firstMatch(cd);
        if (nameMatch != null) profileName = Uri.decodeComponent(nameMatch.group(1)!);
      }
    }
    profileName = profileName.replaceAll('.yaml', '').replaceAll('.yml', '');

    String upload = '', download = '', total = '', expire = '';
    final subInfoList = headers['subscription-userinfo'] ?? <String>[];
    if (subInfoList.isNotEmpty) {
      final subInfo = subInfoList.first;
      final uMatch = RegExp(r'upload=(\d+)').firstMatch(subInfo);
      if (uMatch != null) upload = uMatch.group(1)!;
      final dMatch = RegExp(r'download=(\d+)').firstMatch(subInfo);
      if (dMatch != null) download = dMatch.group(1)!;
      final tMatch = RegExp(r'total=(\d+)').firstMatch(subInfo);
      if (tMatch != null) total = tMatch.group(1)!;
      final eMatch = RegExp(r'expire=(\d+)').firstMatch(subInfo);
      if (eMatch != null) expire = eMatch.group(1)!;
    }

    String injectedHeaders = '';
    if (profileName.isNotEmpty) injectedHeaders += '# name: $profileName\n';
    if (upload.isNotEmpty) injectedHeaders += '# upload: $upload\n';
    if (download.isNotEmpty) injectedHeaders += '# download: $download\n';
    if (total.isNotEmpty) injectedHeaders += '# total: $total\n';
    if (expire.isNotEmpty) injectedHeaders += '# expire: $expire\n';

    return injectedHeaders;
  }

  Future<void> downloadProfile(String rawUrl) async {
    String url = rawUrl.trim();
    String extractedName = '';

    if (url.startsWith('clash://install-config')) {
      final urlMatch = RegExp(r'url=([^&]+)').firstMatch(url);
      if (urlMatch != null) url = Uri.decodeComponent(urlMatch.group(1)!);

      final nameMatch = RegExp(r'name=([^&]+)').firstMatch(rawUrl);
      if (nameMatch != null) extractedName = Uri.decodeComponent(nameMatch.group(1)!);
    }

    if (url.isEmpty || !url.startsWith('http')) throw Exception('无效的 URL 或协议');
    
    try {
      final res = await _smartFetchYaml(url);
      String content = res.data.toString();

      String injectedHeaders = _extractHeadersAsComments(res.headers, extractedName);
      if (injectedHeaders.isNotEmpty) content = injectedHeaders + content;

      final filename = 'profile_${DateTime.now().millisecondsSinceEpoch}.yaml';
      final file = File('$_profilesDir\\$filename');
      if (!(await file.parent.exists())) await file.parent.create(recursive: true);
      await file.writeAsString(content);

      final urlMapFile = File(_profileUrlsPath);
      Map<String, dynamic> urls = {};
      if (await urlMapFile.exists()) urls = jsonDecode(await urlMapFile.readAsString());
      urls[file.absolute.path] = rawUrl.trim(); 
      if (!(await urlMapFile.parent.exists())) await urlMapFile.parent.create(recursive: true);
      await urlMapFile.writeAsString(jsonEncode(urls));

      await loadProfiles();
      await switchProfile(file);
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  Future<void> updateSingleProfile(File file, String rawUrl) async {
    String url = rawUrl.trim();
    String extractedName = '';

    if (url.startsWith('clash://install-config')) {
      final urlMatch = RegExp(r'url=([^&]+)').firstMatch(url);
      if (urlMatch != null) url = Uri.decodeComponent(urlMatch.group(1)!);

      final nameMatch = RegExp(r'name=([^&]+)').firstMatch(rawUrl);
      if (nameMatch != null) extractedName = Uri.decodeComponent(nameMatch.group(1)!);
    }
    
    try {
      final res = await _smartFetchYaml(url);
      String content = res.data.toString();

      String injectedHeaders = _extractHeadersAsComments(res.headers, extractedName);
      if (injectedHeaders.isNotEmpty) content = injectedHeaders + content;

      await file.writeAsString(content);
      await loadProfiles();

      if (activeProfilePath.value == file.absolute.path) {
        await switchProfile(file);
      }
    } catch (e) {
      throw Exception('更新失败: $e');
    }
  }

  Future<void> updateAllProfiles() async {
    final urlMapFile = File(_profileUrlsPath);
    if (!await urlMapFile.exists()) return;
    try {
      final urls = jsonDecode(await urlMapFile.readAsString()) as Map<String, dynamic>;
      for (var entry in urls.entries) {
        final path = entry.key;
        final url = entry.value;
        if (File(path).existsSync()) {
          debugPrint('🔄 [配置更新] 正在智能更新: $path');
          await updateSingleProfile(File(path), url);
        }
      }
    } catch (e) {
      throw Exception('更新全部失败: $e');
    }
  }

  Future<void> createNewProfile(String name, String content) async {
    final dir = Directory(_profilesDir);
    if (!await dir.exists()) await dir.create(recursive: true); 

    final safeName = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final file = File('${dir.path}\\$safeName.yaml');

    await file.writeAsString(content, flush: true);
    await Future.delayed(const Duration(milliseconds: 100));

    await loadProfiles();
    await switchProfile(file);
  }

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
    final absolutePath = file.absolute.path;
    
    // 清除上一个配置的本地测速缓存
    proxyDelaysCache.clear();
    // 递增会话，打断上一轮任何还没跑完的测速
    _speedTestSessionId++;

    bool isCompleted = false;
    Future.delayed(const Duration(milliseconds: 150), () {
      if (!isCompleted) {
        switchingProfilePath.value = absolutePath;
      }
    });

    try {
      final currentPort = config.value['port'] ?? 7891;
      final currentAllowLan = config.value['allow-lan'] ?? false;
      final currentMode = config.value['mode'] ?? 'rule';

      await _dio.put('/configs', queryParameters: {'force': 'true'}, data: {'path': absolutePath});
      
      final overrideData = {
        'port': currentPort,
        'mixed-port': currentPort,
        'allow-lan': currentAllowLan,
        'mode': currentMode,
      };
      await _dio.patch('/configs', data: overrideData);

      activeProfilePath.value = absolutePath;
      await syncConfig(); 
      await fetchProxies();
      
      try {
        await _saveLocalSettings();
      } catch (e) {}
      debugPrint('✅ [配置管理] 切换并覆写本地设置成功: $absolutePath');

      // 核心功能：每次切换完毕，立即触发自动全局测速
      runGlobalSpeedTest();

    } on DioException catch (e) {
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
    } finally {
      isCompleted = true;
      if (switchingProfilePath.value == absolutePath) {
        switchingProfilePath.value = '';
      }
    }
  }

  Future<void> updateConfig(String key, dynamic value) async {
    debugPrint('🔧 [配置更新] 准备修改: $key -> $value');
    try {
      await _dio.patch('/configs', data: {key: value});
      await syncConfig();
      try {
        await _saveLocalSettings();
      } catch (e) {
        debugPrint('💾 [持久化] 保存失败: $e');
      }
      debugPrint('✅ [配置更新] 成功: $key -> $value');
    } catch (e) {
      debugPrint('❌ [配置更新] 失败: $key, 错误: $e (内核可能未启动)');
    }
  }

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
      debugPrint('❌ [TUN更新] 失败: 错误: $e (内核可能未启动)');
    }
  }

  Future<void> toggleServiceMode(bool enable) async {
    try {
      await SystemToolManager.toggleServiceMode(enable);
      isServiceModeEnabled.value = await SystemToolManager.isServiceModeEnabled();
    } catch (e) {
      debugPrint('🛠️ [服务模式] 切换失败: $e');
    }
  }

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

  Future<void> fetchProxies() async {
    isLoadingProxies.value = true;
    try {
      final res = await _dio.get('/proxies');
      Map<String, dynamic> allProxies = Map<String, dynamic>.from(res.data['proxies'] ?? {});

      List<String> groups = [];
      allProxies.forEach((key, value) {
        if (value is Map) {
          // 核心修复：在这里优先将本地缓存的测速结果覆写进去，防止被内核空数据刷掉
          final history = value['history'] as List<dynamic>?;
          if (history != null && history.isNotEmpty) {
            // 如果后端传来了真正的测速历史，同步更新本地缓存
            proxyDelaysCache[key] = history.last['delay'] ?? 0;
          } else if (proxyDelaysCache.containsKey(key)) {
            // 如果后端返回空，说明没记录，强制从缓存恢复
            value['delay'] = proxyDelaysCache[key];
          }

          if (value['type'] == 'Selector' || value['type'] == 'URLTest' || value['type'] == 'Fallback') {
            if (key != 'GLOBAL') groups.add(key); 
          }
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

  Future<void> switchProxy(String groupName, String nodeName) async {
    try {
      await _dio.put('/proxies/$groupName', data: {"name": nodeName});
      await fetchProxies();
    } catch (e) {
      debugPrint('🌐 [API 请求失败] switchProxy: $e');
    }
  }

  Future<void> connectLogSocket() async {
    try {
      final baseUrl = _dio.options.baseUrl.replaceFirst('http', 'ws');
      final secret = _dio.options.headers['Authorization']?.replaceAll('Bearer ', '') ?? '';
      
      final currentLevel = config.value['log-level'] ?? 'info';
      
      _logSocket = await WebSocket.connect('$baseUrl/logs?level=$currentLevel&token=$secret');
      _logSocket!.listen((data) {
        try {
          final json = jsonDecode(data);
          parseLog((json['type'] ?? 'info').toString(), json['payload'] ?? '');
        } catch (_) {}
      }, onError: (e) {
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

  Future<void> toggleAutoStart(bool enable) async {
    await SystemToolManager.setAutoStart(enable);
    try {
      isAutoStartEnabled.value = await SystemToolManager.isAutoStartEnabled();
    } catch (_) {
      isAutoStartEnabled.value = false;
    }
  }

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

  Future<void> toggleMixin(bool enable) async {
    isMixinEnabled.value = enable;
    try {
      await _saveLocalSettings();
    } catch (e) {
      debugPrint('💾 [持久化] 保存 mixin 状态失败: $e');
    }
  }

  Future<void> saveMixinText(String text) async {
    mixinText.value = text;
    try {
      await _saveLocalSettings();
    } catch (e) {
      debugPrint('💾 [持久化] 保存 mixin 文本失败: $e');
    }
  }

  Future<void> saveTunAdvancedConfig(Map<String, dynamic> data) async {
    tunAdvanced.value = Map<String, dynamic>.from(data);
    try {
      await _saveLocalSettings();
    } catch (e) {
      debugPrint('💾 [持久化] 保存 tun 高级配置失败: $e');
    }
  }

  Future<void> toggleGroupCollapse(String groupName) async {
    final state = getGroupCollapseState(groupName);
    state.value = !state.value;
    collapseTrigger.value++; 
    try {
      await _saveLocalSettings();
    } catch (e) {
      debugPrint('💾 [持久化] 保存折叠状态失败: $e');
    }
  }

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
      current['mixin_enabled'] = isMixinEnabled.value;
      current['mixin_text'] = mixinText.value;
      current['tun_advanced'] = tunAdvanced.value;
      
      Map<String, bool> collapseMap = {};
      groupCollapseStates.forEach((key, notifier) {
        collapseMap[key] = notifier.value;
      });
      current['collapse_states'] = collapseMap;
      current['active_profile'] = activeProfilePath.value;
      try {
        if (await file.exists()) {
          final s = await file.readAsString();
          final prev = (jsonDecode(s) as Map<String, dynamic>?) ?? {};
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
        try {
          if (map.containsKey('mixin_enabled')) isMixinEnabled.value = map['mixin_enabled'] == true;
          if (map.containsKey('mixin_text')) mixinText.value = (map['mixin_text'] ?? '').toString();
          if (map.containsKey('tun_advanced') && map['tun_advanced'] is Map) tunAdvanced.value = Map<String, dynamic>.from(map['tun_advanced']);
          
          if (map.containsKey('collapse_states') && map['collapse_states'] is Map) {
            final states = map['collapse_states'] as Map;
            states.forEach((k, v) {
              groupCollapseStates[k.toString()] = ValueNotifier<bool>(v == true);
            });
          }
          
          if (map.containsKey('active_profile')) {
            activeProfilePath.value = map['active_profile']?.toString() ?? '';
          }
        } catch (_) {}
        await _dio.patch('/configs', data: map);
        if (map['system-proxy'] == true) await setSystemProxyEnabled(true);
      }
    } catch (e) {
      debugPrint('💾 [持久化] 读取失败: $e');
    }
  }

  // ==========================================
  // 测速相关功能
  // ==========================================

  /// 测试单个节点延迟
  Future<void> testProxyDelay(String proxyName) async {
    final timeout = config.value['test_timeout'] ?? 3000;
    var url = config.value['test_url']?.toString() ?? '';
    if (url.isEmpty) url = 'http://www.gstatic.com/generate_204';

    try {
      final res = await _dio.get('/proxies/${Uri.encodeComponent(proxyName)}/delay', queryParameters: {
        'timeout': timeout,
        'url': url,
      });
      final delay = res.data['delay'] ?? 0;
      _updateProxyDelayLocally(proxyName, delay);
    } catch (e) {
      _updateProxyDelayLocally(proxyName, 0); 
    }
  }

  /// 依次测试代理组内所有节点（智能混合测速）
  Future<void> testGroupDelay(String groupName) async {
    final groupData = proxiesData.value[groupName];
    if (groupData == null) return;
    
    final String type = groupData['type'] ?? '';
    final List<dynamic> allNodes = groupData['all'] ?? [];

    if (type == 'URLTest' || type == 'Fallback' || type == 'LoadBalance') {
      final timeout = config.value['test_timeout'] ?? 3000;
      var url = config.value['test_url']?.toString() ?? '';
      if (url.isEmpty) url = 'http://www.gstatic.com/generate_204';

      try {
        debugPrint('🚀 [智能测速] 触发原生自动组重新评估: $groupName');
        await _dio.get('/group/${Uri.encodeComponent(groupName)}/delay', queryParameters: {
          'url': url,
          'timeout': timeout,
        });
        await Future.delayed(const Duration(milliseconds: 500));
        await fetchProxies();
      } catch (e) {
        debugPrint('🌐 [API 请求失败] 自动组测速失败: $e');
      }
      return; 
    }

    debugPrint('🐢 [智能测速] 执行安全的前端手动组并发测速: $groupName');
    const int concurrency = 5;
    for (int i = 0; i < allNodes.length; i += concurrency) {
      final chunk = allNodes.sublist(i, min(i + concurrency, allNodes.length));
      await Future.wait(chunk.map((nodeName) => testProxyDelay(nodeName.toString())));
    }
  }

  /// 本地更新 proxiesData 的延迟数据以触发 UI 刷新，并更新缓存
  void _updateProxyDelayLocally(String proxyName, int delay) {
    // 将测速结果锁入缓存
    proxyDelaysCache[proxyName] = delay;
    
    final currentData = Map<String, dynamic>.from(proxiesData.value);
    if (currentData.containsKey(proxyName)) {
      final proxyNode = Map<String, dynamic>.from(currentData[proxyName]);
      List history = List.from(proxyNode['history'] ?? []);
      
      history.add({
        'time': DateTime.now().toUtc().toIso8601String(),
        'delay': delay
      });
      
      proxyNode['history'] = history;
      proxyNode['delay'] = delay; // 强制设置显式的 delay 属性
      currentData[proxyName] = proxyNode;
      proxiesData.value = currentData; 
    }
  }

  /// 核心功能：全局并发节点自动测速，带有防连切防抖功能
  Future<void> runGlobalSpeedTest() async {
    final session = ++_speedTestSessionId;
    await Future.delayed(const Duration(milliseconds: 500)); // 等待 UI 稳定和节点完全加载
    if (_speedTestSessionId != session) return;

    final proxies = proxiesData.value;
    if (proxies.isEmpty) return;

    List<String> nodesToTest = [];
    proxies.forEach((k, v) {
      if (v is Map) {
        final type = (v['type'] ?? '').toString();
        // 排除策略组和内置代理点，只测真正的节点
        if (!['Selector', 'URLTest', 'Fallback', 'LoadBalance', 'Direct', 'Reject', 'Pass'].contains(type)) {
          if (k != 'GLOBAL' && k != 'DIRECT' && k != 'REJECT') {
            nodesToTest.add(k);
          }
        }
      }
    });

    debugPrint('🚀 [自动测速] 启动全局并发测速，共 ${nodesToTest.length} 个节点 (Session: $session)');
    const int concurrency = 10; // 并发数为 10
    for (int i = 0; i < nodesToTest.length; i += concurrency) {
      if (_speedTestSessionId != session) {
        debugPrint('🛑 [自动测速] 检测到配置切换，已终止当前测速循环 (Session: $session)');
        return;
      }
      final chunk = nodesToTest.sublist(i, min(i + concurrency, nodesToTest.length));
      await Future.wait(chunk.map((name) => testProxyDelay(name)));
    }
    debugPrint('✅ [自动测速] 全局测速完毕 (Session: $session)');
  }

  // ==========================================
  // 单个配置操作 (更新、删除)
  // ==========================================

  Future<void> deleteProfile(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
    
    final urlMapFile = File(_profileUrlsPath);
    if (await urlMapFile.exists()) {
      try {
        Map<String, dynamic> urls = jsonDecode(await urlMapFile.readAsString());
        urls.remove(file.absolute.path);
        await urlMapFile.writeAsString(jsonEncode(urls));
      } catch (_) {}
    }

    await loadProfiles();
    
    if (activeProfilePath.value == file.absolute.path) {
      final defaultConfig = File(_runningConfigPath);
      if (await defaultConfig.exists()) {
        await switchProfile(defaultConfig);
      }
    }
  }
}