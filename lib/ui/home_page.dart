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
  @override
  Widget build(BuildContext context) {
    final manager = widget.manager;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 10),
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
                    height: 36, padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        const Text('端口', style: TextStyle(fontSize: 14)),
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
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: Text(cfg['mixed-port']?.toString() ?? cfg['port']?.toString() ?? '7890', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _buildSettingRow('允许局域网', null, isToggle: true, value: cfg['allow-lan'] ?? false, onChanged: (v) => manager.updateConfig('allow-lan', v)),
                // 绑定地址行（当允许局域网时显示）
                if (cfg['allow-lan'] == true) _buildSettingRow('绑定地址', cfg['bind-address'] ?? '*', onTap: _showBindAddressDialog),
                _buildSettingRow('日志级别', (cfg['log-level'] ?? 'info').toString().toUpperCase(), onTap: () {
                  _showLogLevelDialog(cfg['log-level'] ?? 'info');
                }),
                _buildSettingRow('IPv6', null, isToggle: true, value: cfg['ipv6'] ?? false, onChanged: (v) => manager.updateConfig('ipv6', v)),
                ValueListenableBuilder<String>(
                  valueListenable: manager.coreVersion,
                  builder: (context, version, _) {
                    return _HoverRow(
                      child: Container(
                        height: 36, padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            const Text('Clash 内核', style: TextStyle(fontSize: 14)),
                            const SizedBox(width: 12),
                            // 防火墙盾牌按钮
                            ValueListenableBuilder<bool>(
                              valueListenable: manager.isFirewallLoading,
                              builder: (context, isLoading, _) {
                                return ValueListenableBuilder<bool>(
                                  valueListenable: manager.isFirewallAllowed,
                                  builder: (context, isAllowed, _) {
                                    if (isLoading) {
                                      return const Padding(padding: EdgeInsets.all(8.0), child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)));
                                    }
                                    return IconButton(
                                      icon: Icon(isAllowed ? Icons.gpp_good : Icons.gpp_maybe, size: 18, color: isAllowed ? Colors.green : Colors.grey),
                                      tooltip: isAllowed ? '移除防火墙规则' : '添加防火墙规则 (允许LAN)',
                                      onPressed: () => manager.toggleFirewall(),
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
                _buildSettingRow('主目录', '打开文件夹', onTap: () => Process.run('explorer.exe', [Directory.current.path])),
                const Divider(color: Colors.white10, height: 12),

                _buildSettingRow('UWP 应用联网限制', '启动助手', onTap: () => SystemToolManager.openUwpLoopback()),
                _buildSettingRow('虚拟网卡安装', '安装 TAP', onTap: () => Process.run('./bin/tap-driver.exe', [])),
                _buildSettingRow('TAP 模式', '管理', isToggle: true, value: false, onChanged: (v) {}),
                _buildSettingRow('服务模式', '管理', onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已预留 XML 注册框架，需提权写入 C 盘')));
                }),
                _buildSettingRow(
                  'TUN 模式',
                  null,
                  isToggle: true,
                  value: cfg['tun-enable'] ?? false,
                  onChanged: (v) => manager.updateTunConfig(v),
                ),
                _buildSettingRow('混合配置', null, isToggle: true, value: false, onTap: () {}),

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
                            const Text('系统代理', style: TextStyle(fontSize: 14)),
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

  Widget _buildSettingRow(String title, String? trailing, {bool isToggle = false, bool value = false, Function(bool)? onChanged, VoidCallback? onTap, Widget? customTrailing}) {
    Widget trailingWidget;
    if (customTrailing != null) {
      trailingWidget = customTrailing;
    } else if (isToggle) {
      trailingWidget = Transform.scale(
        scale: 0.8,
        child: Switch(value: value, onChanged: onChanged, activeThumbColor: Colors.green, inactiveThumbColor: const Color(0xFF5A5A67)),
      );
    } else if (trailing != null) {
      trailingWidget = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        hoverColor: Colors.white10,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(trailing, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ),
      );
    } else {
      trailingWidget = const SizedBox();
    }

    return _HoverRow(
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Text(title, style: const TextStyle(fontSize: 14)),
            const Spacer(),
            trailingWidget,
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

