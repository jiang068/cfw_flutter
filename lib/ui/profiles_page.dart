import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/mihomo_manager.dart';
import '../main.dart'; 

class ProfilesPage extends StatefulWidget {
  final MihomoManager manager;
  const ProfilesPage({Key? key, required this.manager}) : super(key: key);

  @override
  State<ProfilesPage> createState() => _ProfilesPageState();
}

class _ProfilesPageState extends State<ProfilesPage> {
  final TextEditingController _urlCtrl = TextEditingController();
  Map<String, String> _urlMap = {};

  @override
  void initState() {
    super.initState();
    widget.manager.loadProfiles();
    _loadUrlMap();
  }

  Future<void> _loadUrlMap() async {
    final profile = Platform.environment['USERPROFILE'] ?? '';
    final file = File('$profile\\.config\\cfw_flutter\\profile_urls.json');
    if (await file.exists()) {
      try {
        final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _urlMap = map.map((k, v) => MapEntry(k, v.toString()));
          });
        }
      } catch (_) {}
    }
  }

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return '几秒前';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    return '${diff.inDays} 天前';
  }

  String _formatBytes(double bytes) {
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  String _formatDate(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  Widget _buildTopButton(String text, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF5A5A67),
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        elevation: 0,
      ),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 13)),
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
          backgroundColor: const Color(0xFF373542),
          title: const Text('配置加载失败', style: TextStyle(color: Color(0xFF92484E), fontSize: 16)),
          content: SelectableText(e.toString(), style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('确定', style: TextStyle(color: Colors.blue)))
          ],
        ),
      );
    }
  }

  void _showRightClickMenu(BuildContext context, Offset position, File file, String? url, String currentName) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      color: const Color(0xFF373542),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      items: [
        PopupMenuItem(value: 'open_web', child: const Text('打开配置网站', style: TextStyle(color: Colors.white, fontSize: 13))),
        PopupMenuItem(value: 'edit', child: const Text('编辑', style: TextStyle(color: Colors.white, fontSize: 13))),
        PopupMenuItem(value: 'update', child: const Text('更新', style: TextStyle(color: Colors.white, fontSize: 13))),
        PopupMenuItem(value: 'open_dir', child: const Text('打开文件所在位置', style: TextStyle(color: Colors.white, fontSize: 13))),
        PopupMenuItem(value: 'settings', child: const Text('设置', style: TextStyle(color: Colors.white, fontSize: 13))),
        PopupMenuItem(value: 'delete', child: const Text('删除', style: TextStyle(color: Color(0xFF92484E), fontSize: 13))),
      ],
    ).then((value) async {
      if (value == null) return;
      
      switch (value) {
        case 'open_web':
          if (url != null && url.isNotEmpty) {
            try {
               final uri = Uri.parse(url);
               final rootUrl = '${uri.scheme}://${uri.host}';
               Process.run('cmd', ['/c', 'start', rootUrl.replaceAll('&', '^&')]);
            } catch (_) {}
          } else {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('本地配置无网站信息')));
          }
          break;
        case 'edit':
          _showEditContentDialog(file);
          break;
        case 'update':
          if (url != null && url.isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在更新...'), duration: Duration(seconds: 1)));
            try {
              await widget.manager.updateSingleProfile(file, url);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('更新成功'), backgroundColor: Color(0xFF00AA00)));
            } catch (e) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('更新失败: $e'), backgroundColor: const Color(0xFF92484E)));
            }
          } else {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('本地配置无法更新')));
          }
          break;
        case 'open_dir':
          Process.run('explorer.exe', ['/select,', file.absolute.path]);
          break;
        case 'settings':
          _showProfileSettingsDialog(file, currentName, url);
          break;
        case 'delete':
          await widget.manager.deleteProfile(file);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已删除'), backgroundColor: Colors.orange));
          break;
      }
    });
  }

  void _showEditContentDialog(File file) async {
    final content = await file.readAsString();
    final ctrl = TextEditingController(text: content);
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF373542),
        title: const Text('编辑配置文件 (YAML)', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: SizedBox(
          width: 700,
          height: 500,
          child: TextField(
            controller: ctrl,
            maxLines: null,
            expands: true,
            style: const TextStyle(color: Colors.white70, fontFamily: 'Consolas', fontSize: 13),
            // 修改：输入框背景色改为右侧底色 #2C2A38，形成对比
            decoration: const InputDecoration(filled: true, fillColor: Color(0xFF2C2A38), border: InputBorder.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消', style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () async {
              await file.writeAsString(ctrl.text);
              widget.manager.loadProfiles();
              if (widget.manager.activeProfilePath.value == file.absolute.path) {
                 await widget.manager.switchProfile(file);
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('保存', style: TextStyle(color: Color(0xFF00AA00)))
          ),
        ],
      )
    );
  }

  void _showProfileSettingsDialog(File file, String currentName, String? currentUrl) {
    final nameCtrl = TextEditingController(text: currentName);
    final urlCtrl = TextEditingController(text: currentUrl ?? '');
    final headerCtrl = TextEditingController(text: 'key1:value1\nkey2:value2'); 
    final intervalCtrl = TextEditingController(text: '24');
    final cronCtrl = TextEditingController(text: '0 0 * * *');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF373542),
        title: const Text('编辑配置信息', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSettingInput('名字 *', nameCtrl),
                const SizedBox(height: 12),
                _buildSettingInput('URL', urlCtrl, maxLines: 3),
                const SizedBox(height: 12),
                _buildSettingInput('标头', headerCtrl, maxLines: 3),
                const SizedBox(height: 12),
                _buildSettingInput('更新间隔（小时）', intervalCtrl),
                const SizedBox(height: 12),
                _buildSettingInput('更新定时程序Cron (UNIX)', cronCtrl),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消', style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () async {
              try {
                 final lines = await file.readAsLines();
                 lines.removeWhere((l) => l.trim().toLowerCase().startsWith('# name:'));
                 lines.insert(0, '# name: ${nameCtrl.text}');
                 await file.writeAsString(lines.join('\n'));
                 widget.manager.loadProfiles();
              } catch (_) {}
              
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('确定', style: TextStyle(color: Color(0xFF00AA00)))
          ),
        ],
      )
    );
  }

  Widget _buildSettingInput(String label, TextEditingController ctrl, {int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          maxLines: maxLines,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: const InputDecoration(
            filled: true,
            // 修改：输入框背景色改为右侧底色 #2C2A38
            fillColor: Color(0xFF2C2A38),
            border: OutlineInputBorder(borderSide: BorderSide.none),
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            isDense: true,
          ),
        ),
      ],
    );
  }

  Widget _buildProfileCard(File file, String? url, bool isActive, bool isSwitching) {
    final stat = file.statSync();
    final timeStr = _timeAgo(stat.modified);
    String host = 'local file';
    bool isRemote = url != null && url.isNotEmpty; 

    if (isRemote) {
      try {
        host = Uri.parse(url!).authority; 
      } catch (_) {}
    }

    String name = file.path.split(Platform.pathSeparator).last;
    name = name.replaceAll('.yaml', '').replaceAll('.yml', ''); 

    double? up, down, total;
    int? expire;

    try {
      final lines = file.readAsLinesSync().take(20);
      for (var line in lines) {
        final l = line.toLowerCase();
        if (l.startsWith('# upload:')) up = double.tryParse(l.split(':')[1].trim());
        if (l.startsWith('# download:')) down = double.tryParse(l.split(':')[1].trim());
        if (l.startsWith('# total:')) total = double.tryParse(l.split(':')[1].trim());
        if (l.startsWith('# expire:')) expire = int.tryParse(l.split(':')[1].trim());
        if (l.startsWith('# name:')) name = line.substring(7).trim(); 
      }
    } catch (_) {}

    bool hasTraffic = total != null && total > 0;
    double used = (up ?? 0) + (down ?? 0);
    double ratio = hasTraffic ? (used / total).clamp(0.0, 1.0) : 0;
    // 修改：流量条绿色 #00AA00，红色 #92484E
    Color barColor = ratio > 0.9 ? const Color(0xFF92484E) : (ratio > 0.7 ? Colors.orangeAccent : const Color(0xFF00AA00));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) => _showRightClickMenu(context, details.globalPosition, file, url, name),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 4,
            height: 66,
            child: Stack(
              children: [
                Container(
                  width: 4,
                  height: 66,
                  decoration: BoxDecoration(
                    // 修改：指示器凹槽颜色微调
                    color: const Color(0xFF2C2A38),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                SizedBox(
                  width: 4,
                  height: 66,
                  child: _CfwIndicator(isActive: isActive, isSwitching: isSwitching),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Container(
              height: 72,
              constraints: const BoxConstraints(minWidth: 293), 
              decoration: BoxDecoration(
                // 修改：配置项颜色 #373542
                color: const Color(0xFF373542), 
                borderRadius: BorderRadius.circular(4),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Stack(
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _handleSwitch(file),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 14, right: 40),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                name, 
                                maxLines: 1, 
                                overflow: TextOverflow.ellipsis, 
                                style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.1, fontWeight: FontWeight.w500)
                              ),
                              const SizedBox(height: 4), 
                              Text(
                                '$host ($timeStr)', 
                                maxLines: 1, 
                                overflow: TextOverflow.ellipsis, 
                                style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.1)
                              ),
                              if (hasTraffic) ...[
                                const SizedBox(height: 6),
                                IntrinsicWidth(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            '${_formatBytes(used)}  ${_formatBytes(total!)}', 
                                            style: const TextStyle(color: Colors.white54, fontSize: 11, height: 1.1)
                                          ),
                                          const SizedBox(width: 12), 
                                          if (expire != null)
                                            Text(
                                              _formatDate(expire), 
                                              style: const TextStyle(color: Colors.white54, fontSize: 11, height: 1.1)
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 3), 
                                      Container(
                                        height: 2.0, 
                                        alignment: Alignment.centerLeft,
                                        // 修改：流量条凹槽颜色微调
                                        color: const Color(0xFF2C2A38), 
                                        child: FractionallySizedBox(
                                          widthFactor: ratio, 
                                          child: Container(color: barColor) 
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ]
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 8,
                      top: 0,
                      bottom: 0, 
                      child: Center(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            hoverColor: Colors.white10,
                            onTap: () async {
                              if (isRemote) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在更新...'), duration: Duration(seconds: 1)));
                                try {
                                  await widget.manager.updateSingleProfile(file, url!);
                                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('更新成功'), backgroundColor: Color(0xFF00AA00)));
                                } catch (e) {
                                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('更新失败: $e'), backgroundColor: const Color(0xFF92484E)));
                                }
                              } else {
                                _showEditContentDialog(file);
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(6.0),
                              child: Icon(
                                isRemote ? Icons.refresh : Icons.code, 
                                color: Colors.white70, 
                                size: 18, 
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SubPageLayout(
      header: Row(
        children: [
          Expanded(
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                // 修改：输入框背景色改为 #373542
                color: const Color(0xFF373542),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white12, width: 1),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _urlCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: const InputDecoration(
                        hintText: '从URL下载',
                        hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.content_paste, color: Colors.white54, size: 18),
                    tooltip: '从剪贴板粘贴',
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data != null && data.text != null) {
                        setState(() => _urlCtrl.text = data.text!);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 15),
          _buildTopButton('下载', () async {
            if (_urlCtrl.text.isEmpty) return;
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在下载...'), duration: Duration(seconds: 1)));
            try {
              await widget.manager.downloadProfile(_urlCtrl.text);
              await _loadUrlMap();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('下载并应用成功'), backgroundColor: Color(0xFF00AA00)));
                _urlCtrl.clear();
              }
            } catch (e) {
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: const Color(0xFF92484E)));
            }
          }),
          const SizedBox(width: 10),
          _buildTopButton('更新全部', () async {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在更新所有配置...'), duration: Duration(seconds: 1)));
            try {
              await widget.manager.updateAllProfiles();
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('全部更新完成'), backgroundColor: Color(0xFF00AA00)));
            } catch (e) {
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: const Color(0xFF92484E)));
            }
          }),
          const SizedBox(width: 10),
          _buildTopButton('导入', () async {
            try {
              await widget.manager.importProfile();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('导入并应用成功'), backgroundColor: Color(0xFF00AA00)));
              }
            } catch (e) {
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: const Color(0xFF92484E)));
            }
          }),
        ],
      ),
      content: ValueListenableBuilder<List<File>>(
        valueListenable: widget.manager.profiles,
        builder: (context, files, _) {
          if (files.isEmpty) return const Center(child: Text('暂无配置文件，请点击导入或下载', style: TextStyle(color: Colors.white24)));
          return GridView.builder(
            padding: const EdgeInsets.all(20),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, 
              mainAxisExtent: 72,
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
            ),
            itemCount: files.length,
            itemBuilder: (context, index) {
              final file = files[index];
              return ValueListenableBuilder<String>(
                valueListenable: widget.manager.activeProfilePath,
                builder: (context, activePath, _) {
                  return ValueListenableBuilder<String>(
                    valueListenable: widget.manager.switchingProfilePath,
                    builder: (context, switchingPath, _) {
                      final isSwitching = switchingPath == file.absolute.path;
                      final isActive = (activePath == file.absolute.path) && switchingPath.isEmpty;
                      final url = _urlMap[file.absolute.path];
                      return _buildProfileCard(file, url, isActive, isSwitching);
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _CfwIndicator extends StatefulWidget {
  final bool isActive;
  final bool isSwitching;

  const _CfwIndicator({required this.isActive, required this.isSwitching});

  @override
  State<_CfwIndicator> createState() => _CfwIndicatorState();
}

class _CfwIndicatorState extends State<_CfwIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _bounceController;
  late Animation<Alignment> _bounceAnim;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _bounceAnim = AlignmentTween(begin: const Alignment(0, -0.9), end: const Alignment(0, 0.9)).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeInOutSine),
    );

    if (widget.isSwitching) {
      _bounceController.repeat(reverse: true); 
    }
  }

  @override
  void didUpdateWidget(_CfwIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSwitching && !oldWidget.isSwitching) {
      _bounceController.repeat(reverse: true);
    } else if (!widget.isSwitching && oldWidget.isSwitching) {
      _bounceController.stop();
    }
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double targetFraction = widget.isActive ? 1.0 : (widget.isSwitching ? 0.6 : 0.0);

    return AnimatedBuilder(
      animation: _bounceController,
      builder: (context, child) {
        Alignment targetAlignment = widget.isActive ? Alignment.center : (widget.isSwitching ? _bounceAnim.value : Alignment.center);

        return AnimatedAlign(
          duration: const Duration(milliseconds: 400), 
          curve: Curves.easeOutCubic,
          alignment: targetAlignment,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: targetFraction),
            duration: const Duration(milliseconds: 500), 
            curve: Curves.easeOutBack, 
            builder: (context, fraction, child) {
              final safeFraction = fraction.clamp(0.0, 1.0);
              
              if (safeFraction == 0.0) return const SizedBox();
              return FractionallySizedBox(
                heightFactor: safeFraction,
                child: Container(
                  decoration: BoxDecoration(
                    // 修改：指示器条绿色 #00AA00
                    color: const Color(0xFF00AA00), 
                    borderRadius: BorderRadius.circular(4), 
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}