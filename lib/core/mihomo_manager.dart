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
  // ==========================================
  // 智能配置嗅探与下载引擎
  // ==========================================

  /// 核心嗅探器：使用多套战术轮询，直到获取到真正的 YAML 配置
  Future<Response> _smartFetchYaml(String url) async {
    // 定义多套伪装战术（适配市面上 99.9% 的机场面板与高级协议）
    final strategies = [
      // 战术1：Clash Verge Rev 现代伪装 (首选！直接告诉服务器我支持 Meta/Mihomo 高级特性，不要给我过滤节点)
      {'ua': 'clash-verge/v1.7.7', 'suffix': ''},
      // 战术2：Clash Meta 原生伪装 + 参数 (部分新面板专属)
      {'ua': 'clash.meta', 'suffix': 'flag=meta'},
      // 战术3：纯净原版 CFW 伪装 (专治死板的老旧机场，只认老大哥)
      {'ua': 'ClashforWindows/0.20.39', 'suffix': ''},
      // 战术4：V2Board 强制 flag 伪装 (不认 UA，必须带参数才下发 YAML 的面板，如之前的肥猫云)
      {'ua': 'clash', 'suffix': 'flag=clash'},
      // 战术5：Subconverter 通用转换伪装 (终极兜底，强迫后端走万能转换逻辑)
      {'ua': 'ClashforWindows/0.20.39', 'suffix': 'target=clash'},
    ];

    Response? lastResponse;
    for (var s in strategies) {
      String targetUrl = url;
      if (s['suffix']!.isNotEmpty) {
        // 智能拼接参数，防止 URL 损坏
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
          // 判断是否拿到了 YAML 格式的配置 (必须包含 proxies 等关键字)
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

  /// 提取 HTTP 头部隐藏的配置信息并打包成注释
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

  /// 从 URL 下载并应用配置
  Future<void> downloadProfile(String rawUrl) async {
    String url = rawUrl.trim();
    String extractedName = '';

    // 1. 自动解析 clash:// 链接，提取真实 URL 和附带的名称
    if (url.startsWith('clash://install-config')) {
      final urlMatch = RegExp(r'url=([^&]+)').firstMatch(url);
      if (urlMatch != null) url = Uri.decodeComponent(urlMatch.group(1)!);

      final nameMatch = RegExp(r'name=([^&]+)').firstMatch(rawUrl);
      if (nameMatch != null) extractedName = Uri.decodeComponent(nameMatch.group(1)!);
    }

    if (url.isEmpty || !url.startsWith('http')) throw Exception('无效的 URL 或协议');
    
    try {
      // 使用智能嗅探器获取响应
      final res = await _smartFetchYaml(url);
      String content = res.data.toString();

      // 提取头部并注入
      String injectedHeaders = _extractHeadersAsComments(res.headers, extractedName);
      if (injectedHeaders.isNotEmpty) content = injectedHeaders + content;

      final filename = 'profile_${DateTime.now().millisecondsSinceEpoch}.yaml';
      final file = File('$_profilesDir\\$filename');
      if (!(await file.parent.exists())) await file.parent.create(recursive: true);
      await file.writeAsString(content);

      // 保存完整的原始链接以便更新
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

  /// 单独更新某一个配置文件
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
      // 同样使用智能嗅探器更新
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
          debugPrint('🔄 [配置更新] 正在智能更新: $path');
          // 复用单次更新逻辑，自动走智能嗅探
          await updateSingleProfile(File(path), url);
        }
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

      // ===============================================
      // 核心修复：移除导致闪烁的暴力清空逻辑
      // 直接赋予新的 List 对象，触发 UI 无缝平滑重绘！
      // ===============================================
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
    
    // ===============================================
    // 核心优化：防闪烁延迟加载机制
    // 如果内核切换耗时 < 150ms（秒出），绝不显示动画避免闪烁。
    // 如果耗时 > 150ms（卡顿），才亮起绿条滚动动画告诉用户正在加载。
    // ===============================================
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
    } on DioException catch (e) {
      // 错误回退处理保持不变... (省略，保持你现有的报错回退逻辑即可)
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
      // 无论成功还是失败，打上完成标记
      isCompleted = true;
      // 如果之前已经触发了动画，现在把它关掉
      if (switchingProfilePath.value == absolutePath) {
        switchingProfilePath.value = '';
      }
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
      
      // 核心修复：读取当前配置的真实日志级别，不再写死 info
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
    collapseTrigger.value++; // 核心修复：通知 UI 极速重绘展开/折叠状态
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
      // 成功测速
      final delay = res.data['delay'] ?? 0;
      _updateProxyDelayLocally(proxyName, delay);
    } catch (e) {
      // 测速超时或失败，传入 0 作为超时标识
      _updateProxyDelayLocally(proxyName, 0); 
    }
  }

  /// 依次测试代理组内所有节点（智能混合测速）
  Future<void> testGroupDelay(String groupName) async {
    final groupData = proxiesData.value[groupName];
    if (groupData == null) return;
    
    final String type = groupData['type'] ?? '';
    final List<dynamic> allNodes = groupData['all'] ?? [];

    // 针对自动组 (URLTest / Fallback / LoadBalance)：
    // 直接调用原生 API，让内核在后台高并发测速，并强制触发其底层的“自动选择/故障转移”重新计算逻辑
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
        // 等待一小会儿让内核完成切换，然后拉取最新状态刷新 UI
        await Future.delayed(const Duration(milliseconds: 500));
        await fetchProxies();
      } catch (e) {
        debugPrint('🌐 [API 请求失败] 自动组测速失败: $e');
      }
      return; // 结束，不执行下方的自定义逻辑
    }

    // 针对手动组 (Selector)：
    // 坚决不用原生 API，防止内核清空用户的手动选择。
    // 使用自定义的并发轮询（并发数5），只更新 UI 的延迟数字，不干涉内核状态。
    debugPrint('🐢 [智能测速] 执行安全的前端手动组并发测速: $groupName');
    const int concurrency = 5;
    for (int i = 0; i < allNodes.length; i += concurrency) {
      final chunk = allNodes.sublist(i, min(i + concurrency, allNodes.length));
      await Future.wait(chunk.map((nodeName) => testProxyDelay(nodeName.toString())));
    }
  }

  /// 本地更新 proxiesData 的延迟数据以触发 UI 刷新
  void _updateProxyDelayLocally(String proxyName, int delay) {
    final currentData = Map<String, dynamic>.from(proxiesData.value);
    if (currentData.containsKey(proxyName)) {
      final proxyNode = Map<String, dynamic>.from(currentData[proxyName]);
      List history = List.from(proxyNode['history'] ?? []);
      
      // 追加新的历史记录，delay 0 代表超时
      history.add({
        'time': DateTime.now().toUtc().toIso8601String(),
        'delay': delay
      });
      
      proxyNode['history'] = history;
      currentData[proxyName] = proxyNode;
      proxiesData.value = currentData; 
    }
  }

  // ==========================================
  // 单个配置操作 (更新、删除)
  // ==========================================

  /// 删除配置文件
  Future<void> deleteProfile(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
    
    // 清除 url_map 里的记录
    final urlMapFile = File(_profileUrlsPath);
    if (await urlMapFile.exists()) {
      try {
        Map<String, dynamic> urls = jsonDecode(await urlMapFile.readAsString());
        urls.remove(file.absolute.path);
        await urlMapFile.writeAsString(jsonEncode(urls));
      } catch (_) {}
    }

    await loadProfiles();
    
    // 如果删除的是当前正激活的文件，退回到默认配置
    if (activeProfilePath.value == file.absolute.path) {
      final defaultConfig = File(_runningConfigPath);
      if (await defaultConfig.exists()) {
        await switchProfile(defaultConfig);
      }
    }
  }
}
