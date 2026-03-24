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
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
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
                _buildSettingRow('端口', cfg['port']?.toString() ?? '7890', extraIcon: Icons.edit, onTap: _showPortDialog),
                _buildSettingRow('允许局域网', null, isToggle: true, value: cfg['allow-lan'] ?? false, onChanged: (v) => manager.updateConfig('allow-lan', v)),
                _buildSettingRow('日志级别', (cfg['log-level'] ?? 'info').toString().toUpperCase(), onTap: () {
                  const lvls = ['info', 'warning', 'error', 'debug', 'silent'];
                  final cur = cfg['log-level'] ?? 'info';
                  final idx = (lvls.indexOf(cur) + 1) % lvls.length;
                  manager.updateConfig('log-level', lvls[idx]);
                }),
                _buildSettingRow('IPv6', null, isToggle: true, value: cfg['ipv6'] ?? false, highlight: true, onChanged: (v) => manager.updateConfig('ipv6', v)),
                ValueListenableBuilder<String>(
                  valueListenable: manager.coreVersion,
                  builder: (context, v, _) => _buildSettingRow('Clash 内核', v, extraIcon: Icons.security),
                ),
                _buildSettingRow('主目录', '打开文件夹', extraIcon: Icons.folder_open, onTap: () => Process.run('explorer.exe', [Directory.current.path])),
                const Divider(color: Colors.white10, height: 30),

                _buildSettingRow('UWP 应用联网限制', '启动助手', onTap: () => SystemToolManager.openUwpLoopback()),
                _buildSettingRow('虚拟网卡安装', '安装 TAP', onTap: () => Process.run('./bin/tap-driver.exe', [])),
                _buildSettingRow('TAP 模式', '管理', isToggle: true, value: false, onChanged: (v) {}),
                _buildSettingRow('服务模式', '管理', extraIcon: Icons.settings_applications, onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已预留 XML 注册框架，需提权写入 C 盘')));
                }),
                _buildSettingRow('TUN 模式', null, isToggle: true, value: false, onChanged: (v) {}),
                _buildSettingRow('混合配置', null, isToggle: true, value: false, extraIcon: Icons.edit, onTap: () {}),

                const Divider(color: Colors.white10, height: 30),
                // 系统代理开关：绑定到 MihomoManager.isSystemProxyEnabled
                ValueListenableBuilder<bool>(
                  valueListenable: manager.isSystemProxyEnabled,
                  builder: (context, enabled, _) {
                    return InkWell(
                      onTap: null,
                      child: Container(
                        height: 48, padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(color: Colors.transparent, borderRadius: BorderRadius.circular(4)),
                        child: Row(
                          children: [
                            const Text('系统代理', style: TextStyle(fontSize: 15)),
                            const Spacer(),
                            Switch(value: enabled, onChanged: (v) async {
                              await manager.setSystemProxyEnabled(v);
                              setState(() {});
                            }, activeThumbColor: Colors.green, inactiveThumbColor: Colors.red),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                _buildSettingRow('开机自启动', null, isToggle: true, value: false, onChanged: (v) {}),
              ],
            );
          },
        ),
      ],
    );
  }

  void _showPortDialog() {
    final manager = widget.manager;
    TextEditingController ctrl = TextEditingController(text: manager.config.value['port']?.toString() ?? '7890');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C36),
        title: const Text('Port', style: TextStyle(color: Colors.white, fontSize: 16)),
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
              if (p != null) manager.updateConfig('port', p);
              Navigator.pop(context);
            },
            child: const Text('Save', style: TextStyle(color: Colors.green)),
          )
        ],
      ),
    );
  }

  Widget _buildSettingRow(String title, String? trailing, {bool isToggle = false, bool value = false, Function(bool)? onChanged, VoidCallback? onTap, IconData? extraIcon, bool highlight = false}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 48, padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: highlight ? const Color(0xFF383842) : Colors.transparent, borderRadius: BorderRadius.circular(4)),
        child: Row(
          children: [
            Text(title, style: const TextStyle(fontSize: 15)),
            if (extraIcon != null) Padding(padding: const EdgeInsets.only(left: 8), child: Icon(extraIcon, size: 14, color: Colors.grey)),
            const Spacer(),
            if (isToggle) Switch(value: value, onChanged: onChanged, activeThumbColor: Colors.green, inactiveThumbColor: Colors.red)
            else if (trailing != null) Text(trailing, style: const TextStyle(color: Colors.white54)),
          ],
        ),
      ),
    );
  }
}
