import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:windows_single_instance/windows_single_instance.dart';

import 'core/mihomo_manager.dart';
import 'ui/home_page.dart';
import 'ui/proxies_page.dart';
import 'ui/logs_page.dart';

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
  WindowOptions windowOptions = const WindowOptions(
    size: Size(900, 650),
    minimumSize: Size(850, 600),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

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
    // 启动内核并初始化数据
    _manager.startMihomo();
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
  void onTrayIconMouseDown() async { await windowManager.show(); await windowManager.focus(); }
  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();
  @override
  void onTrayMenuItemClick(MenuItem item) {
    if (item.key == 'show_window') onTrayIconMouseDown();
    else if (item.key == 'exit_app') { _manager.dispose(); exit(0); }
  }

  Widget _buildSidebar() => Container(
    width: 180, color: const Color(0xFF22222B),
    child: Column(
      children: [
        Container(height: 90, alignment: Alignment.center, child: const Text('网速面板 (待对接)', style: TextStyle(color: Colors.white54))),
        _buildNavItem('主页', 0), _buildNavItem('代理', 1), _buildNavItem('配置', 2), _buildNavItem('日志', 3),
        const Spacer(),
        Container(height: 80, alignment: Alignment.center, child: const Text('01 : 21 : 27\n● 已连接', textAlign: TextAlign.center, style: TextStyle(color: Colors.green))),
      ],
    ),
  );

  Widget _buildNavItem(String title, int index) {
    bool isSelected = _selectedIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedIndex = index),
      child: Container(
        height: 45, margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(color: isSelected ? const Color(0xFF454555) : Colors.transparent, borderRadius: BorderRadius.circular(6)),
        alignment: Alignment.center,
        child: Text(title, style: TextStyle(color: isSelected ? Colors.white : Colors.white60, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  Widget _buildTitleBar() {
    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        height: 40, alignment: Alignment.centerRight, color: Colors.transparent,
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
                      const Center(child: Text('配置管理')),
                      LogsPage(manager: _manager),
                    ],
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
