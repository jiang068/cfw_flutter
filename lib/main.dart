import 'dart:async';
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
    await windowManager.setAsFrameless();
    await windowManager.setHasShadow(false);
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    await windowManager.setMinimumSize(const Size(700, 500));
    await windowManager.setBackgroundColor(Colors.transparent);
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

  bool _isPinned = false; 
  bool _isConnected = true; 
  DateTime? _connectedTime; 
  Timer? _uptimeTimer; 
  String _uptimeStr = '00 : 00 : 00';

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    trayManager.addListener(this);
    windowManager.setPreventClose(true);
    _initTray();

    _connectedTime = DateTime.now();
    _uptimeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_connectedTime != null && _isConnected) {
        final diff = DateTime.now().difference(_connectedTime!);
        final h = diff.inHours.toString().padLeft(2, '0');
        final m = (diff.inMinutes % 60).toString().padLeft(2, '0');
        final s = (diff.inSeconds % 60).toString().padLeft(2, '0');
        setState(() => _uptimeStr = '$h : $m : $s');
      }
    });

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
    _uptimeTimer?.cancel();
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

  Widget _buildSpeedRow(IconData icon, String speedStr) {
    final match = RegExp(r'^([\d\.]+)\s*(.*)$').firstMatch(speedStr.trim());
    String val = '0';
    String unit = 'B/s';
    if (match != null) {
      val = match.group(1) ?? '0';
      unit = match.group(2) ?? 'B/s';
      if (unit.isEmpty) unit = 'B/s';
    } else {
      val = speedStr;
    }

    return SizedBox(
      width: 120, 
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 24, 
            child: Align(
              alignment: Alignment.centerLeft,
              child: Icon(icon, color: Colors.white, size: 12) 
            )
          ),
          Expanded(
            child: Text(
              val, 
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white, 
                fontSize: 14, 
                fontWeight: FontWeight.bold, 
                fontFamily: 'Consolas'
              )
            ),
          ),
          SizedBox(
            width: 34, 
            child: Align(
              alignment: Alignment.centerRight, 
              child: Text(
                unit, 
                textAlign: TextAlign.right, 
                style: const TextStyle(
                  color: Colors.white, 
                  fontSize: 11 
                )
              )
            )
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() => Container(
    width: 172,
    color: const Color(0xFF42424E),
    child: Column(
      children: [
        Container(
          height: 77,
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
                      _buildSpeedRow(Icons.arrow_upward, up),
                      const SizedBox(height: 8),
                      _buildSpeedRow(Icons.arrow_downward, down),
                    ],
                  );
                },
              );
            },
          ),
        ),
        Container(height: 1, color: Colors.white10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, 
            children: [
              _buildNavItem('主页', 0),
              _buildNavItem('代理', 1),
              _buildNavItem('配置', 2),
              _buildNavItem('日志', 3),
              _buildNavItem('设置', 4),
              const Spacer(),
              Container(
                height: 80,
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _uptimeStr,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'Consolas'),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isConnected ? const Color(0xFF00AA00) : const Color(0xFF92484E),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isConnected ? '已连接' : '未连接',
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                ),
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
        height: 54, 
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2C2A38) : Colors.transparent,
        ),
        alignment: Alignment.center,
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white60,
            fontSize: 16,
            // 核心修复：移除加粗，保持选中和未选中样式一致
          )
        ),
      ),
    );
  }

  Widget _buildWindowBtn(IconData icon, VoidCallback onTap, {bool isClose = false, bool isActive = false}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: isClose ? const Color(0xFFE81123) : Colors.white24,
        child: SizedBox(
          width: 44, 
          height: 24, 
          child: Icon(
            icon, 
            size: 14, 
            color: isActive ? Colors.white : Colors.white70 
          ),
        ),
      ),
    );
  }

  Widget _buildTitleBar() {
    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        height: 24,
        color: const Color(0xFF343442),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _buildWindowBtn(
              _isPinned ? Icons.push_pin : Icons.push_pin_outlined, 
              () async {
                setState(() => _isPinned = !_isPinned);
                await windowManager.setAlwaysOnTop(_isPinned);
              }, 
              isActive: _isPinned
            ),
            _buildWindowBtn(Icons.minimize, () => windowManager.minimize()),
            _buildWindowBtn(Icons.crop_square, () => windowManager.maximize()),
            _buildWindowBtn(Icons.close, () => windowManager.close(), isClose: true),
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
        Container(
          height: 77, 
          padding: const EdgeInsets.symmetric(horizontal: 20),
          color: const Color(0xFF2C2A38),
          alignment: Alignment.centerLeft,
          child: header ?? const SizedBox.shrink(),
        ),
        Container(height: 1, color: Colors.white10),
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