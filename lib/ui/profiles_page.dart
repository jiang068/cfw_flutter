import 'dart:io';
import 'package:flutter/material.dart';
import '../core/mihomo_manager.dart';

class ProfilesPage extends StatefulWidget {
  final MihomoManager manager;
  const ProfilesPage({Key? key, required this.manager}) : super(key: key);

  @override
  State<ProfilesPage> createState() => _ProfilesPageState();
}

class _ProfilesPageState extends State<ProfilesPage> {
  final TextEditingController _urlCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.manager.loadProfiles();
  }

  Widget _buildTopButton(String text, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF383842),
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 13)),
    );
  }

  void _showNewProfileDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C36),
        title: const Text('新建配置文件', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: SizedBox(
          width: 600,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(hintText: '配置名称 (如: my_proxy)', hintStyle: TextStyle(color: Colors.white24), filled: true, fillColor: Color(0xFF1E1E24), border: InputBorder.none),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: TextField(
                  controller: contentCtrl,
                  maxLines: 20,
                  style: const TextStyle(color: Colors.white, fontFamily: 'Consolas', fontSize: 13),
                  decoration: const InputDecoration(hintText: '在此粘贴 YAML 配置内容...', hintStyle: TextStyle(color: Colors.white24), filled: true, fillColor: Color(0xFF1E1E24), border: InputBorder.none),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消', style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () async {
              if (nameCtrl.text.isEmpty || contentCtrl.text.isEmpty) return;
              try {
                await widget.manager.createNewProfile(nameCtrl.text, contentCtrl.text);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('创建并应用成功'), backgroundColor: Colors.green));
                }
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
              }
            },
            child: const Text('保存并应用', style: TextStyle(color: Colors.green)),
          ),
        ],
      ),
    );
  }

  void _handleSwitch(File file) async {
    try {
      await widget.manager.switchProfile(file);
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF2C2C36),
          title: const Text('配置加载失败', style: TextStyle(color: Colors.redAccent, fontSize: 16)),
          content: SelectableText(e.toString(), style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('确定', style: TextStyle(color: Colors.blue)))
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 顶部操作栏 (单行极致压缩)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
          color: const Color(0xFF22222B),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 32,
                  child: TextField(
                    controller: _urlCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    textAlignVertical: TextAlignVertical.center,
                    decoration: const InputDecoration(
                      hintText: '输入配置订阅 URL...',
                      hintStyle: TextStyle(color: Colors.white24),
                      isDense: true,
                      filled: true, fillColor: Color(0xFF1E1E24),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(borderSide: BorderSide.none),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 5),
              _buildTopButton('下载', () async {
                if (_urlCtrl.text.isEmpty) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在下载...'), duration: Duration(seconds: 1)));
                try {
                  await widget.manager.downloadProfile(_urlCtrl.text);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('下载并应用成功'), backgroundColor: Colors.green));
                    _urlCtrl.clear();
                  }
                } catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
                }
              }),
              const SizedBox(width: 5),
              _buildTopButton('更新全部', () async {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在更新所有配置...'), duration: Duration(seconds: 1)));
                try {
                  await widget.manager.updateAllProfiles();
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('全部更新完成'), backgroundColor: Colors.green));
                } catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
                }
              }),
              const SizedBox(width: 5),
              _buildTopButton('导入', () async {
                try {
                  await widget.manager.importProfile();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('导入并应用成功'), backgroundColor: Colors.green));
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
                  }
                }
              }),
              const SizedBox(width: 5),
              _buildTopButton('新建配置', () => _showNewProfileDialog(context)),
            ],
          ),
        ),
        // 配置列表
        Expanded(
          child: ValueListenableBuilder<List<File>>(
            valueListenable: widget.manager.profiles,
            builder: (context, files, _) {
              if (files.isEmpty) return const Center(child: Text('暂无配置文件，请点击导入或下载', style: TextStyle(color: Colors.white24)));
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 10),
                itemCount: files.length,
                itemBuilder: (context, index) {
                  final file = files[index];
                  final filename = file.path.split(Platform.pathSeparator).last;
                  return ValueListenableBuilder<String>(
                    valueListenable: widget.manager.activeProfilePath,
                    builder: (context, activePath, _) {
                      final isActive = activePath == file.absolute.path;
                      return Card(
                        color: isActive ? const Color(0xFF3A4B3A) : const Color(0xFF2C2C36),
                        margin: const EdgeInsets.only(bottom: 10),
                        child: InkWell(
                          onTap: () => _handleSwitch(file),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                            child: Row(
                              children: [
                                Icon(Icons.description, color: isActive ? Colors.green : Colors.white54, size: 24),
                                const SizedBox(width: 15),
                                Expanded(child: Text(filename, style: TextStyle(color: isActive ? Colors.greenAccent : Colors.white, fontSize: 15, fontWeight: isActive ? FontWeight.bold : FontWeight.normal))),
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
