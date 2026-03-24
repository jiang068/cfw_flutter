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
}
