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

  // 核心修复：完全手动控制窗口，不用 waitUntilReadyToShow
  // 先隐藏，设好所有参数，等第一帧渲染完再 show，彻底消除闪烁和跳变
  try {
    await windowManager.hide();
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    await windowManager.setMinimumSize(const Size(700, 500));
    await windowManager.setBackgroundColor(const Color(0xFF282832));
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
        scaffoldBackgroundColor: const Color(0xFF282832),
        fontFamily: 'Microsoft YaHei',
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

    // 第一帧渲染完毕后，显示窗口并启动内核
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
    color: const Color(0xFF22222B),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          alignment: Alignment.center,
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
                      const SizedBox(height: 12),
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
        _buildNavItem('主页', 0),
        _buildNavItem('代理', 1),
        _buildNavItem('配置', 2),
        _buildNavItem('日志', 3),
        const Spacer(),
        Container(
          height: 80,
          alignment: Alignment.center,
          child: const Text('01 : 21 : 27\n● 已连接', textAlign: TextAlign.center, style: TextStyle(color: Colors.green)),
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
          color: isSelected ? const Color(0xFF454555) : Colors.transparent,
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

  Widget _buildTitleBar() {
    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        height: 40,
        alignment: Alignment.centerRight,
        color: Colors.transparent,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.minimize, size: 16), onPressed: () => windowManager.minimize()),
            IconButton(icon: const Icon(Icons.crop_square, size: 16), onPressed: () => windowManager.maximize()),
            IconButton(icon: const Icon(Icons.close, size: 16), hoverColor: Colors.red, onPressed: () => windowManager.close()),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _buildSidebar(),
          Expanded(
            child: Column(
              children: [
                _buildTitleBar(),
                Expanded(
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: [
                      HomePage(manager: _manager),
                      ProxiesPage(manager: _manager),
                      ProfilesPage(manager: _manager),
                      LogsPage(manager: _manager),
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