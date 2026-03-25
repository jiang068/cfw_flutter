import 'dart:io';

import 'package:flutter/material.dart';
import '../core/mihomo_manager.dart';
import '../core/system_tool_manager.dart';

class HomePage extends StatefulWidget {
  final MihomoManager manager;
  const HomePage({Key? key, required this.manager}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const double _kFontSize = 15.0;
  @override
  Widget build(BuildContext context) {
    final manager = widget.manager;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 10),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.pets, size: 40, color: Colors.blueAccent),
            const SizedBox(width: 15),
            const Text('Clash for Windows', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 20),

        ValueListenableBuilder<Map<String, dynamic>>(
          valueListenable: manager.config,
          builder: (context, cfg, _) {
            return Column(
              children: [
                // 端口行：支持随机端口按钮（行高 36，右侧端口文本可点）
                _HoverRow(
                  child: Container(
                    height: 34, padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text('端口', style: TextStyle(fontSize: _kFontSize)),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.casino, size: 18, color: Colors.white54),
                          tooltip: '随机端口',
                          onPressed: () {
                            final randomPort = 10000 + DateTime.now().millisecond % 50000;
                            debugPrint('🎲 [随机端口] 生成端口: $randomPort');
                            manager.updateConfig('mixed-port', randomPort);
                          },
                        ),
                        InkWell(
                          onTap: _showPortDialog,
                          hoverColor: Colors.white10,
                          splashColor: Colors.white24,
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: Text(cfg['mixed-port']?.toString() ?? cfg['port']?.toString() ?? '7890', style: const TextStyle(color: Colors.white70, fontSize: _kFontSize)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _buildSettingRow(
                  '允许局域网',
                  null,
                  customTrailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (cfg['allow-lan'] == true)
                        InkWell(
                          onTap: _showBindAddressDialog,
                          hoverColor: Colors.white10,
                          splashColor: Colors.white24,
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.only(right: 15),
                            child: Text('绑定地址: ${cfg['bind-address'] ?? '*'}', style: const TextStyle(color: Colors.white70, fontSize: _kFontSize)),
                          ),
                        ),
                      Transform.scale(
                        scale: 0.8,
                        child: Switch(value: cfg['allow-lan'] ?? false, onChanged: (v) => manager.updateConfig('allow-lan', v), activeThumbColor: Colors.green, inactiveThumbColor: const Color(0xFF5A5A67)),
                      ),
                    ],
                  ),
                ),
                _buildSettingRow('日志级别', (cfg['log-level'] ?? 'info').toString().toUpperCase(), onTap: () {
                  _showLogLevelDialog(cfg['log-level'] ?? 'info');
                }),
                _buildSettingRow('IPv6', null, isToggle: true, value: cfg['ipv6'] ?? false, onChanged: (v) => manager.updateConfig('ipv6', v)),
                ValueListenableBuilder<String>(
                  valueListenable: manager.coreVersion,
                  builder: (context, version, _) {
                    return _HoverRow(
                      child: Container(
                        height: 34, padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Text('Clash 内核', style: TextStyle(fontSize: _kFontSize)),
                            const SizedBox(width: 12),
                            // 防火墙盾牌按钮（固定尺寸以避免状态切换抖动）
                            ValueListenableBuilder<bool>(
                              valueListenable: manager.isFirewallLoading,
                              builder: (context, isLoading, _) {
                                return ValueListenableBuilder<bool>(
                                  valueListenable: manager.isFirewallAllowed,
                                  builder: (context, isAllowed, _) {
                                    return SizedBox(
                                      width: 32,
                                      height: 32,
                                      child: Center(
                                        child: isLoading
                                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                            : IconButton(
                                                padding: EdgeInsets.zero,
                                                icon: Icon(isAllowed ? Icons.gpp_good : Icons.gpp_maybe, size: 18, color: isAllowed ? Colors.green : Colors.grey),
                                                tooltip: isAllowed ? '移除防火墙规则' : '添加防火墙规则 (允许LAN)',
                                                onPressed: () => manager.toggleFirewall(),
                                              ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.memory, size: 18),
                              tooltip: '预览配置文件',
                              onPressed: () async {
                                final content = await manager.getConfigFileContent();
                                if (!context.mounted) return;
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    backgroundColor: const Color(0xFF2C2C36),
                                    title: const Text('配置文件预览 (config.yaml)', style: TextStyle(color: Colors.white, fontSize: 16)),
                                    content: SizedBox(
                                      width: 600, height: 400,
                                      child: SingleChildScrollView(child: SelectableText(content, style: const TextStyle(color: Colors.white70, fontFamily: 'Consolas', fontSize: 12))),
                                    ),
                                    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭', style: TextStyle(color: Colors.blue)))],
                                  ),
                                );
                              }
                            ),
                            IconButton(
                              icon: const Icon(Icons.dns, size: 18),
                              tooltip: '解析 Host',
                              onPressed: () {
                                TextEditingController hostCtrl = TextEditingController();
                                String selectedType = 'A';
                                ValueNotifier<String> resultNotifier = ValueNotifier<String>('');

                                showDialog(
                                  context: context,
                                  builder: (context) => StatefulBuilder(
                                    builder: (context, setDialogState) {
                                      return AlertDialog(
                                        backgroundColor: const Color(0xFF2C2C36),
                                        title: const Text('DNS查询 : 主机(Host)', style: TextStyle(color: Colors.white, fontSize: 16)),
                                        content: SizedBox(
                                          width: 400,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: TextField(
                                                      controller: hostCtrl,
                                                      style: const TextStyle(color: Colors.white),
                                                      decoration: const InputDecoration(filled: true, fillColor: Color(0xFF1E1E24), border: InputBorder.none, hintText: '例如: google.com', hintStyle: TextStyle(color: Colors.white24)),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  DropdownButton<String>(
                                                    value: selectedType,
                                                    dropdownColor: const Color(0xFF1E1E24),
                                                    items: ['A', 'AAAA', 'MX'].map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(color: Colors.white)))).toList(),
                                                    onChanged: (v) => setDialogState(() => selectedType = v!),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 15),
                                              ValueListenableBuilder<String>(
                                                valueListenable: resultNotifier,
                                                builder: (context, res, _) => res.isEmpty ? const SizedBox() : Container(
                                                  width: double.infinity, padding: const EdgeInsets.all(8), color: Colors.black26,
                                                  child: SelectableText(res, style: const TextStyle(color: Colors.greenAccent, fontFamily: 'Consolas', fontSize: 12)),
                                                ),
                                              )
                                            ],
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () async {
                                              if (hostCtrl.text.isEmpty) return;
                                              resultNotifier.value = '查询中...';
                                              final res = await manager.queryDns(hostCtrl.text, selectedType);
                                              if (res.containsKey('error')) {
                                                resultNotifier.value = '错误: ${res['error']}';
                                              } else if (res['Answer'] != null) {
                                                resultNotifier.value = (res['Answer'] as List).map((e) => '${e['name']} -> ${e['data']} (TTL: ${e['TTL']})').join('\n');
                                              } else {
                                                resultNotifier.value = '无结果或请求格式错误\n$res';
                                              }
                                            },
                                            child: const Text('检索', style: TextStyle(color: Colors.green)),
                                          ),
                                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭', style: TextStyle(color: Colors.grey)))
                                        ],
                                      );
                                    }
                                  ),
                                );
                              }
                            ),
                            const Spacer(),
                            Text(version, style: const TextStyle(color: Colors.white54)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                _buildSettingRow(
                  '主目录', null,
                  customTrailing: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        final profile = Platform.environment['USERPROFILE'] ?? '';
                        Process.run('explorer.exe', ['$profile\\.config\\cfw_flutter']);
                      },
                      hoverColor: Colors.white10,
                      splashColor: Colors.white12,
                      borderRadius: BorderRadius.circular(4),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        child: Text('打开文件夹', style: TextStyle(color: Colors.white70, fontSize: 15)),
                      ),
                    ),
                  ),
                ),
                const Divider(color: Colors.white10, height: 12),

                _buildSettingRow(
                  'UWP 应用联网限制', null,
                  customTrailing: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => SystemToolManager.openUwpLoopback(),
                      hoverColor: Colors.white10,
                      splashColor: Colors.white12,
                      borderRadius: BorderRadius.circular(4),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        child: Text('启动助手', style: TextStyle(color: Colors.white70, fontSize: 15)),
                      ),
                    ),
                  ),
                ),
                // TAP 模式已彻底移除，以消除旧有性能和交互问题
                ValueListenableBuilder<bool>(
                  valueListenable: manager.isServiceModeEnabled,
                  builder: (context, isService, _) {
                    return _buildSettingRow(
                      '服务模式', null,
                      titleTrailing: Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Icon(Icons.public, size: 18, color: isService ? Colors.green : Colors.white24),
                      ),
                      customTrailing: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => manager.toggleServiceMode(!isService),
                          hoverColor: Colors.white10,
                          splashColor: Colors.white12,
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            child: Text(isService ? '卸载' : '安装', style: const TextStyle(color: Colors.white70, fontSize: 15)),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                _buildSettingRow(
                  'TUN 模式', null,
                  titleTrailing: IconButton(
                    icon: const Icon(Icons.settings, size: 16, color: Colors.white54),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                    splashRadius: 16,
                    tooltip: 'TUN 配置',
                    onPressed: () => _showTunConfigDialog(context),
                  ),
                  isToggle: true,
                  value: cfg['tun-enable'] ?? false,
                  onChanged: (v) => manager.updateTunConfig(v),
                ),

                // 混合配置行：带齿轮与开关
                ValueListenableBuilder<bool>(
                  valueListenable: manager.isMixinEnabled,
                  builder: (context, isMixin, _) {
                    return _buildSettingRow(
                      '混合配置', null,
                      titleTrailing: IconButton(
                        icon: const Icon(Icons.settings, size: 16, color: Colors.white54),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                        splashRadius: 16,
                        tooltip: '混合配置',
                        onPressed: () => _showMixinDialog(context),
                      ),
                      isToggle: true,
                      value: isMixin,
                      onChanged: (v) => manager.toggleMixin(v),
                    );
                  },
                ),

                const Divider(color: Colors.white10, height: 12),
                // 系统代理开关：绑定到 MihomoManager.isSystemProxyEnabled
                ValueListenableBuilder<bool>(
                  valueListenable: manager.isSystemProxyEnabled,
                  builder: (context, enabled, _) {
                    return _HoverRow(
                      child: Container(
                        height: 36, padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            const Text('系统代理', style: TextStyle(fontSize: 16)),
                            const Spacer(),
                            Transform.scale(
                              scale: 0.8,
                              child: Switch(value: enabled, onChanged: (v) async {
                                await manager.setSystemProxyEnabled(v);
                                setState(() {});
                              }, activeThumbColor: Colors.green, inactiveThumbColor: const Color(0xFF5A5A67)),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: manager.isAutoStartEnabled,
                  builder: (context, autoStartEnabled, _) {
                    return _buildSettingRow(
                      '开机自启动',
                      null,
                      isToggle: true,
                      value: autoStartEnabled,
                      onChanged: (v) => manager.toggleAutoStart(v),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  void _showPortDialog() {
    final manager = widget.manager;
    TextEditingController ctrl = TextEditingController(text: manager.config.value['mixed-port']?.toString() ?? manager.config.value['port']?.toString() ?? '7890');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C36),
        title: const Text('更改混合端口 (mixed = http + socks)', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white),
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(filled: true, fillColor: Color(0xFF1E1E24), border: InputBorder.none),
        ),
        actions: [
          TextButton(
            onPressed: () {
              int? p = int.tryParse(ctrl.text);
              if (p != null) manager.updateConfig('mixed-port', p);
              Navigator.pop(context);
            },
            child: const Text('Save', style: TextStyle(color: Colors.green)),
          )
        ],
      ),
    );
  }

  void _showBindAddressDialog() {
    final manager = widget.manager;
    TextEditingController ctrl = TextEditingController(text: manager.config.value['bind-address']?.toString() ?? '*');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C36),
        title: const Text('绑定地址', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8.0),
              child: Text('允许LAN只会绑定到您设置的地址，*表示所有接口', style: TextStyle(color: Colors.white70)),
            ),
            TextField(
              controller: ctrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(filled: true, fillColor: Color(0xFF1E1E24), border: InputBorder.none),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              manager.updateConfig('bind-address', ctrl.text);
              Navigator.pop(context);
            },
            child: const Text('Save', style: TextStyle(color: Colors.green)),
          )
        ],
      ),
    );
  }

  void _showLogLevelDialog(String currentLevel) {
    final manager = widget.manager;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C36),
        title: const Text('日志级别', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8.0),
              child: Text('静默将阻止.log文件在下次启动时生成，而调试将收集所有运行信息至.log 文件。', style: TextStyle(color: Colors.white70)),
            ),
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton(onPressed: () { manager.updateConfig('log-level', 'silent'); Navigator.pop(context); }, child: const Text('静默')),
                ElevatedButton(onPressed: () { manager.updateConfig('log-level', 'error'); Navigator.pop(context); }, child: const Text('错误')),
                ElevatedButton(onPressed: () { manager.updateConfig('log-level', 'warning'); Navigator.pop(context); }, child: const Text('警告')),
                ElevatedButton(onPressed: () { manager.updateConfig('log-level', 'info'); Navigator.pop(context); }, child: const Text('信息')),
                ElevatedButton(onPressed: () { manager.updateConfig('log-level', 'debug'); Navigator.pop(context); }, child: const Text('调试')),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildSettingRow(String title, String? trailingText, {bool isToggle = false, bool value = false, Function(bool)? onChanged, VoidCallback? onTap, Widget? customTrailing, Widget? titleTrailing}) {
    Widget trailingWidget;
    if (customTrailing != null) {
      trailingWidget = customTrailing;
    } else if (isToggle) {
      trailingWidget = Transform.scale(
        scale: 0.8,
        child: Switch(value: value, onChanged: onChanged, activeThumbColor: Colors.green, inactiveThumbColor: const Color(0xFF5A5A67)),
      );
    } else if (trailingText != null) {
      trailingWidget = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        hoverColor: Colors.white10,
        splashColor: Colors.white24,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(trailingText, style: const TextStyle(color: Colors.white70, fontSize: _kFontSize)),
        ),
      );
    } else {
      trailingWidget = const SizedBox();
    }

    return _HoverRow(
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(title, style: const TextStyle(fontSize: _kFontSize)),
            if (titleTrailing != null) Padding(padding: const EdgeInsets.only(left: 6), child: titleTrailing),
            const Spacer(),
            trailingWidget,
          ],
        ),
      ),
    );
  }

}

// ---- 混合配置弹窗 ----
extension on _HomePageState {
  void _showMixinDialog(BuildContext context) {
    final manager = widget.manager;
    TextEditingController ctrl = TextEditingController(text: manager.mixinText.value);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C36),
        title: const Text('混合配置 (YAML)', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: SizedBox(
          width: 600,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                style: const TextStyle(color: Colors.white),
                maxLines: 15,
                decoration: const InputDecoration(filled: true, fillColor: Color(0xFF1E1E24), border: InputBorder.none),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消', style: TextStyle(color: Colors.grey))),
          TextButton(onPressed: () async { await manager.saveMixinText(ctrl.text); Navigator.pop(context); }, child: const Text('保存', style: TextStyle(color: Colors.green))),
        ],
      ),
    );
  }

  void _showTunConfigDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => TunConfigDialog(manager: widget.manager),
    );
  }
}

// ---- TunConfigDialog ----
class TunConfigDialog extends StatefulWidget {
  final MihomoManager manager;
  const TunConfigDialog({Key? key, required this.manager}) : super(key: key);

  @override
  State<TunConfigDialog> createState() => _TunConfigDialogState();
}

class _TunConfigDialogState extends State<TunConfigDialog> {
  bool dnsIpv6 = false;
  TextEditingController dnsServersCtrl = TextEditingController();
  TextEditingController backupDnsCtrl = TextEditingController();
  TextEditingController defaultNsCtrl = TextEditingController();
  TextEditingController fakeIpFiltersCtrl = TextEditingController();
  TextEditingController domainPolicyCtrl = TextEditingController();
  TextEditingController dnsHijackCtrl = TextEditingController();
  String tunStack = 'system';
  bool autoDetectIface = false;
  static const double _kTunFont = 15.0;

  @override
  void initState() {
    super.initState();
    final data = widget.manager.tunAdvanced.value;
    // PM 提供的默认值
    const String defaultDnsServers = "114.114.114.114\n223.5.5.5\n8.8.8.8";
    const String defaultFakeIpFilters = "+.stun.**\n+.stun.***\n+.stun.*.***\n+.stun.*****\n+.stun.playstation.net\nxbox.*.*.microsoft.com\n***.xboxlive.com\n*.msftncsi.com\n*.msftconnecttest.com\nWORKGROUP";
    const String defaultDnsHijack = "any:53";
    const String defaultTunStack = "gvisor";
    try {
      dnsIpv6 = data['dns_ipv6'] == true;
      dnsServersCtrl.text = (data['dns_servers'] ?? defaultDnsServers).toString();
      backupDnsCtrl.text = (data['backup_dns'] ?? '').toString();
      defaultNsCtrl.text = (data['default_nameserver'] ?? '').toString();
      fakeIpFiltersCtrl.text = (data['fake_ip_filters'] ?? defaultFakeIpFilters).toString();
      domainPolicyCtrl.text = (data['domain_policy'] ?? '').toString();
      dnsHijackCtrl.text = (data['dns_hijack'] ?? defaultDnsHijack).toString();
      tunStack = (data['tun_stack'] ?? defaultTunStack).toString();
      autoDetectIface = data['auto_detect_iface'] == true;
    } catch (_) {}
  }

  String _buildYaml() {
    final dnsServers = dnsServersCtrl.text.trim();
    final backup = backupDnsCtrl.text.trim();
    final fakeFilters = fakeIpFiltersCtrl.text.trim();
    final domainPolicy = domainPolicyCtrl.text.trim();
    final hijack = dnsHijackCtrl.text.trim();
    return '''dns:
  ipv6: ${dnsIpv6 ? 'true' : 'false'}
  servers: |
    ${dnsServers.replaceAll('\n', '\n    ')}
  backup: |
    ${backup.replaceAll('\n', '\n    ')}
  default_nameserver: ${defaultNsCtrl.text}
  fake_ip_filters: |
    ${fakeFilters.replaceAll('\n', '\n    ')}
  domain_policy: |
    ${domainPolicy.replaceAll('\n', '\n    ')}
  hijack: ${hijack}
tun:
  stack: ${tunStack}
  auto_detect_interface: ${autoDetectIface ? 'true' : 'false'}
''';
  }

  void _resetDefaults() {
    setState(() {
      dnsIpv6 = false;
      dnsServersCtrl.clear();
      backupDnsCtrl.clear();
      defaultNsCtrl.clear();
      fakeIpFiltersCtrl.clear();
      domainPolicyCtrl.clear();
      dnsHijackCtrl.clear();
      tunStack = 'system';
      autoDetectIface = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF2C2C36),
      content: SizedBox(
        width: 800, height: 500,
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      child: ListView(
                        children: [
                          SwitchListTile(title: const Text('DNS IPv6', style: TextStyle(color: Colors.white, fontSize: _kTunFont)), value: dnsIpv6, onChanged: (v) => setState(() => dnsIpv6 = v)),
                          const SizedBox(height: 8),
                          const Text('DNS 服务器 (每行一个)', style: TextStyle(color: Colors.white70, fontSize: _kTunFont)),
                          TextField(controller: dnsServersCtrl, maxLines: 3, style: const TextStyle(color: Colors.white, fontSize: _kTunFont), decoration: const InputDecoration(filled: true, fillColor: Color(0xFF1E1E24), border: InputBorder.none)),
                          const SizedBox(height: 8),
                          const Text('后备DNS 服务器', style: TextStyle(color: Colors.white70, fontSize: _kTunFont)),
                          TextField(controller: backupDnsCtrl, maxLines: 2, style: const TextStyle(color: Colors.white, fontSize: _kTunFont), decoration: const InputDecoration(filled: true, fillColor: Color(0xFF1E1E24), border: InputBorder.none)),
                          const SizedBox(height: 8),
                          const Text('默认名称服务器', style: TextStyle(color: Colors.white70, fontSize: _kTunFont)),
                          TextField(controller: defaultNsCtrl, style: const TextStyle(color: Colors.white, fontSize: _kTunFont), decoration: const InputDecoration(filled: true, fillColor: Color(0xFF1E1E24), border: InputBorder.none)),
                          const SizedBox(height: 8),
                          const Text('Fake IP 过滤器', style: TextStyle(color: Colors.white70, fontSize: _kTunFont)),
                          TextField(controller: fakeIpFiltersCtrl, maxLines: 3, style: const TextStyle(color: Colors.white, fontSize: _kTunFont), decoration: const InputDecoration(filled: true, fillColor: Color(0xFF1E1E24), border: InputBorder.none)),
                          const SizedBox(height: 8),
                          const Text('域名服务器政策', style: TextStyle(color: Colors.white70, fontSize: _kTunFont)),
                          TextField(controller: domainPolicyCtrl, maxLines: 2, style: const TextStyle(color: Colors.white, fontSize: _kTunFont), decoration: const InputDecoration(filled: true, fillColor: Color(0xFF1E1E24), border: InputBorder.none)),
                          const SizedBox(height: 8),
                          const Text('DNS 劫持', style: TextStyle(color: Colors.white70, fontSize: _kTunFont)),
                          TextField(controller: dnsHijackCtrl, style: const TextStyle(color: Colors.white, fontSize: _kTunFont), decoration: const InputDecoration(filled: true, fillColor: Color(0xFF1E1E24), border: InputBorder.none)),
                          const SizedBox(height: 8),
                          const Text('TUN 栈', style: TextStyle(color: Colors.white70, fontSize: _kTunFont)),
                          DropdownButton<String>(value: tunStack, dropdownColor: const Color(0xFF1E1E24), items: ['gvisor', 'system', 'mixed'].map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(color: Colors.white, fontSize: _kTunFont)))).toList(), onChanged: (v) => setState(() => tunStack = v ?? 'system')),
                          const SizedBox(height: 8),
                          SwitchListTile(title: const Text('自动检测接口', style: TextStyle(color: Colors.white, fontSize: _kTunFont)), value: autoDetectIface, onChanged: (v) => setState(() => autoDetectIface = v)),
                        ],
                      ),
                    ),
                  ),
                  Container(width: 1, color: Colors.white12),
                  Expanded(
                    child: Container(
                      color: const Color(0xFF1E1E24), padding: const EdgeInsets.all(12),
                      child: SingleChildScrollView(child: SelectableText(_buildYaml(), style: const TextStyle(color: Colors.white70, fontFamily: 'Consolas'))),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => _resetDefaults(), child: const Text('重置', style: TextStyle(color: Colors.orange))),
                const SizedBox(width: 8),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消', style: TextStyle(color: Colors.grey))),
                const SizedBox(width: 8),
                TextButton(onPressed: () async {
                  final map = {
                    'dns_ipv6': dnsIpv6,
                    'dns_servers': dnsServersCtrl.text,
                    'backup_dns': backupDnsCtrl.text,
                    'default_nameserver': defaultNsCtrl.text,
                    'fake_ip_filters': fakeIpFiltersCtrl.text,
                    'domain_policy': domainPolicyCtrl.text,
                    'dns_hijack': dnsHijackCtrl.text,
                    'tun_stack': tunStack,
                    'auto_detect_iface': autoDetectIface,
                  };
                  await widget.manager.saveTunAdvancedConfig(map);
                  if (context.mounted) Navigator.pop(context);
                }, child: const Text('保存', style: TextStyle(color: Colors.green))),
              ],
            )
          ],
        ),
      ),
    );
  }
}

// ---- 局部悬停高亮包装器 ----
class _HoverRow extends StatefulWidget {
  final Widget child;
  const _HoverRow({required this.child});

  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: Container(
        decoration: BoxDecoration(
          color: _isHovering ? const Color(0xFF383842) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: widget.child,
      ),
    );
  }
}

