import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:windows_single_instance/windows_single_instance.dart';

import 'core/mihomo_manager.dart';
import 'ui/home_page.dart';
import 'ui/proxies_page.dart';
import 'ui/logs_page.dart';
import 'ui/profiles_page.dart';
import 'ui/settings_page.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows) {
    await WindowsSingleInstance.ensureSingleInstance(
      args,
      "cfw_flutter_unique_id",
      onSecondWindow: (args) async {
        if (await windowManager.isMinimized()) await windowManager.restore();
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

  await windowManager.ensureInitialized();

  double? savedW;
  double? savedH;
  double? savedX;
  double? savedY;

  try {
    final profile = Platform.environment['USERPROFILE'] ?? '';
    final file = File('$profile\\.config\\cfw_flutter\\settings.json');
    if (await file.exists()) {
      final s = await file.readAsString();
      final map = jsonDecode(s) as Map<String, dynamic>?;
      if (map != null && map.containsKey('window_width') && map.containsKey('window_height')) {
        savedW = (map['window_width'] is num) ? (map['window_width'] as num).toDouble() : double.tryParse(map['window_width'].toString());
        savedH = (map['window_height'] is num) ? (map['window_height'] as num).toDouble() : double.tryParse(map['window_height'].toString());
        savedX = (map['window_x'] is num) ? (map['window_x'] as num).toDouble() : double.tryParse(map['window_x']?.toString() ?? '0') ?? 0.0;
        savedY = (map['window_y'] is num) ? (map['window_y'] as num).toDouble() : double.tryParse(map['window_y']?.toString() ?? '0') ?? 0.0;
      }
    }
  } catch (_) {}

  try {
    await windowManager.hide();
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    await windowManager.setMinimumSize(const Size(700, 500));
    // Scaffold 背景色统一改为右侧底色 #2C2A38
    await windowManager.setBackgroundColor(const Color(0xFF2C2A38));
    if (savedW != null && savedH != null) {
      await windowManager.setSize(Size(savedW, savedH));
    } else {
      await windowManager.setSize(const Size(750, 600));
    }
    if (savedX != null && savedY != null) {
      await windowManager.setPosition(Offset(savedX, savedY));
    } else {
      await windowManager.setAlignment(Alignment.center);
    }
  } catch (_) {}

  runApp(const CFWFlutterApp());
}

class CFWFlutterApp extends StatelessWidget {
  const CFWFlutterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        // Scaffold 背景色统一改为右侧底色 #2C2A38
        scaffoldBackgroundColor: const Color(0xFF2C2A38),
        fontFamily: 'Microsoft YaHei',
        fontFamilyFallback: const [
          'TwemojiMozilla',
          'Segoe UI Emoji',
        ],
      ),
      home: const MainLayout(),
    );
  }
}

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> with WindowListener, TrayListener {
  int _selectedIndex = 0;
  final MihomoManager _manager = MihomoManager();

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    trayManager.addListener(this);
    windowManager.setPreventClose(true);
    _initTray();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await windowManager.show();
        await windowManager.focus();
      } catch (_) {}
      _manager.startMihomo();
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    trayManager.destroy();
    _manager.dispose();
    super.dispose();
  }

  @override
  void onWindowClose() async => await windowManager.hide();

  @override
  void onWindowResized() async {
    try {
      final size = await windowManager.getSize();
      final pos = await windowManager.getPosition();
      _manager.saveWindowBounds(size.width, size.height, pos.dx, pos.dy);
    } catch (_) {}
  }

  @override
  void onWindowMoved() async {
    try {
      final size = await windowManager.getSize();
      final pos = await windowManager.getPosition();
      _manager.saveWindowBounds(size.width, size.height, pos.dx, pos.dy);
    } catch (_) {}
  }

  Future<void> _initTray() async {
    try {
      await trayManager.setIcon('assets/tray.png');
      _updateTrayMenu();
    } catch (_) {}
  }

  void _updateTrayMenu() async {
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(label: '显示窗口', key: 'show_window'),
      MenuItem.separator(),
      MenuItem(label: '退出', key: 'exit_app'),
    ]));
  }

  @override
  void onTrayIconMouseDown() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem item) async {
    if (item.key == 'show_window') {
      onTrayIconMouseDown();
    } else if (item.key == 'exit_app') {
      await _manager.dispose();
      exit(0);
    }
  }

  Widget _buildSidebar() => Container(
    width: 180,
    // 左侧背景色统一改为 #42424E
    color: const Color(0xFF42424E),
    child: Column(
      children: [
        // 第一象限：网速区 (背景色 #42424E)
        Container(
          height: 75,
          alignment: Alignment.center,
          // 移除这里单独的底边线，改由主体结构统一绘制
          child: ValueListenableBuilder<String>(
            valueListenable: _manager.upSpeed,
            builder: (context, up, _) {
              return ValueListenableBuilder<String>(
                valueListenable: _manager.downSpeed,
                builder: (context, down, _) {
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.arrow_upward, color: Colors.greenAccent, size: 16),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 80,
                            child: Text(up, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.arrow_downward, color: Colors.blueAccent, size: 16),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 80,
                            child: Text(down, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.blueAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
        // 核心微调：在这里绘制贯穿左侧的 1px 灰色分割线
        Container(height: 1, color: Colors.white10),
        // 第三象限：侧边菜单区 (背景色 #42424E)
        Expanded(
          child: Column(
            children: [
              const SizedBox(height: 10),
              _buildNavItem('主页', 0),
              _buildNavItem('代理', 1),
              _buildNavItem('配置', 2),
              _buildNavItem('日志', 3),
              _buildNavItem('设置', 4),
              const Spacer(),
              Container(
                height: 80,
                alignment: Alignment.center,
                child: const Text('01 : 21 : 27\n● 已连接', textAlign: TextAlign.center, style: TextStyle(color: Colors.green)),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildNavItem(String title, int index) {
    bool isSelected = _selectedIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedIndex = index),
      child: Container(
        height: 45,
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
          // 选中项颜色微调以适应新背景
          color: isSelected ? const Color(0xFF50505E) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(title,
            style: TextStyle(
                color: isSelected ? Colors.white : Colors.white60,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  // 修改：框叉顶栏颜色 #343442
  Widget _buildTitleBar() {
    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        height: 36,
        color: const Color(0xFF343442),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(icon: const Icon(Icons.minimize, size: 16, color: Colors.white70), onPressed: () => windowManager.minimize(), splashRadius: 16),
            IconButton(icon: const Icon(Icons.crop_square, size: 16, color: Colors.white70), onPressed: () => windowManager.maximize(), splashRadius: 16),
            IconButton(icon: const Icon(Icons.close, size: 16, color: Colors.white70), hoverColor: Colors.red, onPressed: () => windowManager.close(), splashRadius: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildTitleBar(),
          Expanded(
            child: Row(
              children: [
                _buildSidebar(),
                Expanded(
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: [
                      HomePage(manager: _manager),
                      ProxiesPage(manager: _manager),
                      ProfilesPage(manager: _manager),
                      LogsPage(manager: _manager),
                      SettingsPage(manager: _manager),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 统一的右侧布局引擎
// ==========================================
class SubPageLayout extends StatelessWidget {
  final Widget? header;
  final Widget content;

  const SubPageLayout({super.key, this.header, required this.content});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 第二象限 (Top-Right)：背景色 #2C2A38
        Container(
          height: 75,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          color: const Color(0xFF2C2A38),
          alignment: Alignment.centerLeft,
          child: header ?? const SizedBox.shrink(),
        ),
        // 核心微调：在这里绘制贯穿右侧的 1px 灰色分割线，与左侧连成一线
        Container(height: 1, color: Colors.white10),
        // 第四象限 (Bottom-Right)：背景色 #2C2A38
        Expanded(
          child: Container(
            color: const Color(0xFF2C2A38),
            child: content,
          ),
        ),
      ],
    );
  }
}