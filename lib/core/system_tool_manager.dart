import 'dart:io';
import 'package:flutter/foundation.dart';

/// SystemToolManager - 独立工具调用封装（静态方法）
class SystemToolManager {
  /// 启用系统代理，使用 CFW 标准的绕过局域网参数
  static Future<ProcessResult> enableSystemProxy(int port) async {
    // 如果传入的端口无效，强制回退到默认的 7890 端口
    int safePort = (port <= 0) ? 7890 : port;
    final addr = '127.0.0.1:$safePort';
    final args = ['global', addr, 'localhost;127.*;10.*;172.16.*;192.168.*;<local>'];
    try {
  if (kDebugMode) debugPrint('🛠️ [Sysproxy 调用] cmd: ./bin/sysproxy.exe ${args.join(' ')} (safePort=$safePort)');
  final result = await Process.run('./bin/sysproxy.exe', args);
  if (kDebugMode) debugPrint("🛠️ [Sysproxy 开启] safePort=$safePort ExitCode: ${result.exitCode}, 输出: ${result.stdout}, 错误: ${result.stderr}");
      return result;
    } catch (e) {
      if (kDebugMode) debugPrint('🛠️ [Sysproxy 开启] 调用异常: $e');
      rethrow;
    }
  }

  /// 禁用/清除系统代理
  static Future<ProcessResult> disableSystemProxy() async {
    final args = ['set', '1', '-', '-', '-'];
    try {
      if (kDebugMode) debugPrint('🛠️ [Sysproxy 调用] cmd: ./bin/sysproxy.exe ${args.join(' ')}');
      final result = await Process.run('./bin/sysproxy.exe', args);
      if (kDebugMode) debugPrint("🛠️ [Sysproxy 关闭] ExitCode: ${result.exitCode}, 输出: ${result.stdout}, 错误: ${result.stderr}");
      return result;
    } catch (e) {
      if (kDebugMode) debugPrint('🛠️ [Sysproxy 关闭] 调用异常: $e');
      rethrow;
    }
  }

  /// 打开 UWP Loopback 工具（带 GUI，使用 start 不等待）
  static Future<Process> openUwpLoopback() async {
    if (kDebugMode) debugPrint('🛠️ [EnableLoopback] 启动 ./bin/EnableLoopback.exe');
    return await Process.start('./bin/EnableLoopback.exe', []);
  }

  // ---- 开机自启 (Windows) ----
  static const String _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const String _appName = 'CFW_Flutter_Mihomo';

  /// 检查是否已开启开机自启
  static Future<bool> isAutoStartEnabled() async {
    if (!Platform.isWindows) return false;
    try {
      final result = await Process.run('reg', ['query', _runKey, '/v', _appName]);
      // exitCode 为 0 说明键值存在，即已开启自启
      return result.exitCode == 0;
    } catch (e) {
      if (kDebugMode) debugPrint('🛠️ [自启动] 检查失败: $e');
      return false;
    }
  }

  /// 设置开机自启
  static Future<void> setAutoStart(bool enable) async {
    if (!Platform.isWindows) return;
    try {
      if (enable) {
        final exePath = Platform.resolvedExecutable;
        // 添加注册表项，路径必须用双引号包裹以防有空格
        await Process.run('reg', ['add', _runKey, '/v', _appName, '/t', 'REG_SZ', '/d', '"$exePath"', '/f']);
      } else {
        // 删除注册表项
        await Process.run('reg', ['delete', _runKey, '/v', _appName, '/f']);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('🛠️ [自启动] 设置失败: $e');
    }
  }

  // ---- 防火墙规则管理 (Windows) ----
  static const String _fwRuleName = 'CFW_Flutter_Mihomo_Core';

  /// 检查防火墙规则是否存在
  static Future<bool> isFirewallRuleExists() async {
    if (!Platform.isWindows) return false;
    try {
      final result = await Process.run('netsh', ['advfirewall', 'firewall', 'show', 'rule', 'name=$_fwRuleName']);
      return result.exitCode == 0; // 0 表示找到了规则
    } catch (e) {
      return false;
    }
  }

  /// 提权添加/移除防火墙规则
  static Future<bool> toggleFirewallRule(bool enable) async {
    if (!Platform.isWindows) return false;
    try {
      final exeDir = Directory.current.path;
      final corePath = '$exeDir\\mihomo.exe';
      String args = '';
      if (enable) {
        // 添加入站放行规则
        args = 'netsh advfirewall firewall add rule name="$_fwRuleName" dir=in action=allow program="$corePath" enable=yes';
      } else {
        // 删除规则
        args = 'netsh advfirewall firewall delete rule name="$_fwRuleName"';
      }
      
      // 使用 PowerShell 触发 UAC 提权执行
      await Process.run('powershell', [
        '-Command',
        'Start-Process cmd -ArgumentList \'/c $args\' -Verb RunAs -WindowStyle Hidden'
      ]);
      
      // 给系统一点时间应用规则
      await Future.delayed(const Duration(seconds: 1));
      return await isFirewallRuleExists();
    } catch (e) {
      if (kDebugMode) debugPrint('🛠️ [防火墙] 操作失败: $e');
      return false;
    }
  }
}
