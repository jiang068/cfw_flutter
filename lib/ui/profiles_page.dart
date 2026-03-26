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
        // 顶部操作栏 (拆分为两行以防止溢出)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
          color: const Color(0xFF22222B),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 第一行：URL 输入与下载
              Row(
                children: [
                  const Text('从URL下载', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: TextField(
                        controller: _urlCtrl,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        textAlignVertical: TextAlignVertical.center, // 居中对齐
                        decoration: const InputDecoration(
                          isDense: true, // 开启紧凑模式，修复无法点击的 Bug
                          filled: true, fillColor: Color(0xFF1E1E24),
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8), // 调整内边距
                          border: OutlineInputBorder(borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 16, color: Colors.white54), 
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () {},
                  ),
                  const SizedBox(width: 5),
                  ElevatedButton(
                    onPressed: () {}, 
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF383842), minimumSize: const Size(60, 32)), 
                    child: const Text('下载', style: TextStyle(color: Colors.white))
                  ),
                ],
              ),
              const SizedBox(height: 10), // 两行之间的间距
              // 第二行：其它操作按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton(
                    onPressed: () {}, 
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF383842), minimumSize: const Size(60, 32)), 
                    child: const Text('更新全部', style: TextStyle(color: Colors.white))
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: () {}, 
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF383842), minimumSize: const Size(60, 32)), 
                    child: const Text('导入', style: TextStyle(color: Colors.white))
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: () {}, 
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF383842), minimumSize: const Size(60, 32)), 
                    child: const Text('新建配置', style: TextStyle(color: Colors.white))
                  ),
                ],
              ),
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
