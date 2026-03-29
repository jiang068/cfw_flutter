import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/mihomo_manager.dart';
import '../main.dart'; 

class LogsPage extends StatefulWidget {
  final MihomoManager manager;
  const LogsPage({Key? key, required this.manager}) : super(key: key);

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  String _searchQuery = '';
  bool _isDetailed = true;
  bool _isDebug = false;
  bool _isPaused = false;

  List<LogItem> _localLogs = [];

  @override
  void initState() {
    super.initState();
    _localLogs = widget.manager.logs.value.take(50).toList();
    widget.manager.logs.addListener(_onLogsChanged);

    final currentLevel = widget.manager.config.value['log-level']?.toString().toLowerCase();
    _isDebug = currentLevel == 'debug';
  }

  @override
  void dispose() {
    widget.manager.logs.removeListener(_onLogsChanged);
    super.dispose();
  }

  void _onLogsChanged() {
    if (!_isPaused) {
      setState(() {
        _localLogs = widget.manager.logs.value.take(50).toList();
      });
    }
  }

  List<LogItem> get _filteredLogs {
    if (_searchQuery.isEmpty) return _localLogs;
    final q = _searchQuery.toLowerCase();
    return _localLogs.where((log) {
      return log.msg.toLowerCase().contains(q) ||
             log.rule.toLowerCase().contains(q) ||
             log.proxy.toLowerCase().contains(q) ||
             log.destination.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return SubPageLayout(
      header: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('请求日志', style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              ValueListenableBuilder<Map<String, dynamic>>(
                valueListenable: widget.manager.config,
                builder: (context, config, _) {
                  final mode = config['mode']?.toString().toUpperCase() ?? 'RULE';
                  String modeText = mode == 'RULE' ? '规则' : (mode == 'GLOBAL' ? '全局' : (mode == 'DIRECT' ? '直连' : mode));
                  return Text('模式: $modeText', style: const TextStyle(fontSize: 13, color: Colors.white70));
                },
              ),
            ],
          ),
          const SizedBox(width: 25),
          
          Expanded(
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF373542),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white12),
              ),
              child: TextField(
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                  hintText: '搜索',
                  hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: InputBorder.none,
                  isDense: true,
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              ),
            ),
          ),
          const SizedBox(width: 20),
          
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _SegmentedButton(
                    leftText: '简略',
                    rightText: '详细',
                    isRightSelected: _isDetailed,
                    onChanged: (isDetailed) => setState(() => _isDetailed = isDetailed),
                  ),
                  const SizedBox(height: 6),
                  _SegmentedButton(
                    leftText: '信息',
                    rightText: '调试',
                    isRightSelected: _isDebug,
                    onChanged: (isDebug) {
                      setState(() => _isDebug = isDebug);
                      widget.manager.updateConfig('log-level', isDebug ? 'debug' : 'info');
                    },
                  ),
                ],
              ),
              const SizedBox(width: 15),
              Material(
                color: const Color(0xFF00AA00),
                borderRadius: BorderRadius.circular(4),
                child: InkWell(
                  onTap: () {
                    widget.manager.logs.value = [];
                    setState(() => _localLogs = []);
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: const Text('清除', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Material(
                color: _isPaused ? const Color(0xFF2196F3) : const Color(0xFFE53935),
                borderRadius: BorderRadius.circular(4),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _isPaused = !_isPaused;
                      if (!_isPaused) {
                        _localLogs = widget.manager.logs.value.take(50).toList();
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(_isPaused ? '开始' : '暂停', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      content: ListView.builder(
        reverse: true,
        itemCount: _filteredLogs.length,
        itemBuilder: (context, index) {
          final log = _filteredLogs[index];
          return _buildLogItem(log);
        },
      ),
    );
  }

  Widget _buildLogItem(LogItem log) {
    bool isError = log.type == 'error' || log.type == 'err';
    bool isWarn = log.type == 'warn' || log.type == 'warning';
    
    String emoji = isError ? '❌' : (isWarn ? '⚠️' : '✅');
    Color msgColor = isError ? const Color(0xFF92484E) : (isWarn ? Colors.orangeAccent : const Color(0xFF00AA00));

    String dest = log.destination;
    if (dest.isEmpty && log.msg.contains('-->')) {
      final parts = log.msg.split('-->');
      if (parts.length > 1) dest = parts[1].trim();
    }
    
    // 核心修正：判断是否为纯系统级别的日志（无路由、无代理、无目标）
    bool isSystemLog = log.rule.isEmpty && log.proxy.isEmpty && dest.isEmpty;

    // 如果不是系统日志，且没有提取到目标，才兜底显示 Unknown Destination
    if (dest.isEmpty && !isSystemLog) {
      dest = 'Unknown Destination';
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) => _showRightClickMenu(context, details.globalPosition, log.msg),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white10, width: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: '$emoji ', style: const TextStyle(fontSize: 12)),
                        TextSpan(text: log.msg, style: TextStyle(color: msgColor, fontSize: 13)),
                      ],
                    ),
                  ),
                ),
                Text(log.time, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
            // 核心修正：如果是系统日志，即使开启了 _isDetailed，也不渲染任何路由详情
            if (_isDetailed && !isSystemLog) ...[
              const SizedBox(height: 3),
              Row(
                children: [
                  const Text('▼ ', style: TextStyle(color: Colors.white54, fontSize: 10)),
                  Expanded(
                    child: Text(dest, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text.rich(
                TextSpan(
                  style: const TextStyle(fontSize: 12),
                  children: [
                    const TextSpan(text: 'RULE ', style: TextStyle(color: Colors.lightBlueAccent, fontWeight: FontWeight.bold)),
                    const TextSpan(text: '→ ', style: TextStyle(color: Colors.white54)),
                    TextSpan(text: log.rule, style: const TextStyle(color: Colors.white70)),
                    const TextSpan(text: '    PROXY ', style: TextStyle(color: Colors.lightBlueAccent, fontWeight: FontWeight.bold)),
                    const TextSpan(text: '→ ', style: TextStyle(color: Colors.white54)),
                    TextSpan(text: log.proxy, style: const TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }

  void _showRightClickMenu(BuildContext context, Offset position, String rawMsg) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      color: const Color(0xFF373542),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      items: [
        PopupMenuItem(
          height: 35,
          child: const Text('复制日志 (Copy Payload)', style: TextStyle(color: Colors.white, fontSize: 13)),
          onTap: () {
            Clipboard.setData(ClipboardData(text: rawMsg));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已复制到剪贴板', style: TextStyle(color: Colors.white)), backgroundColor: Color(0xFF00AA00), duration: Duration(seconds: 1)),
            );
          },
        ),
      ],
    );
  }
}

class _SegmentedButton extends StatelessWidget {
  final String leftText;
  final String rightText;
  final bool isRightSelected;
  final ValueChanged<bool> onChanged;

  const _SegmentedButton({
    required this.leftText,
    required this.rightText,
    required this.isRightSelected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFF2196F3); 
    const inactiveColor = Color(0xFF373542); 
    
    return Container(
      height: 24,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: inactiveColor,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => onChanged(false),
            child: Container(
              width: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: !isRightSelected ? activeColor : Colors.transparent,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(4)),
              ),
              child: Text(leftText, style: TextStyle(color: !isRightSelected ? Colors.white : Colors.white70, fontSize: 12)),
            ),
          ),
          GestureDetector(
            onTap: () => onChanged(true),
            child: Container(
              width: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isRightSelected ? activeColor : Colors.transparent,
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
              ),
              child: Text(rightText, style: TextStyle(color: isRightSelected ? Colors.white : Colors.white70, fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }
}