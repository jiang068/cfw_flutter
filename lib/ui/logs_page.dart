import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/mihomo_manager.dart';

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
    _localLogs = List.from(widget.manager.logs.value);
    widget.manager.logs.addListener(_onLogsChanged);

    // 初始化读取日志级别状态
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
        _localLogs = List.from(widget.manager.logs.value);
      });
    }
  }

  // 过滤后的日志
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
    return Column(
      children: [
        // 顶部工具栏
        _buildHeaderBar(),
        // 底部日志列表区
        Expanded(
          child: Container(
            color: const Color(0xFF282832),
            child: ListView.builder(
              reverse: true, // 核心机制：让 index 0（最新日志）始终在最底部并往上顶
              itemCount: _filteredLogs.length,
              itemBuilder: (context, index) {
                final log = _filteredLogs[index];
                return _buildLogItem(log);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderBar() {
    return Container(
      height: 75,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: const Color(0xFF22222B),
      child: Row(
        children: [
          // 左侧：标题与模式
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
                  // 简单的中文化映射
                  String modeText = mode == 'RULE' ? '规则' : (mode == 'GLOBAL' ? '全局' : (mode == 'DIRECT' ? '直连' : mode));
                  return Text('模式: $modeText', style: const TextStyle(fontSize: 13, color: Colors.white70));
                },
              ),
            ],
          ),
          const SizedBox(width: 25),
          
          // 中间：搜索框
          Expanded(
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E24),
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
          
          // 右侧功能区：连体切换按钮 + 动作按钮
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 模式切换
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
              
              // 清除按钮
              Material(
                color: Colors.green, // 经典绿色
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
              
              // 暂停/开始按钮
              Material(
                color: _isPaused ? const Color(0xFF2196F3) : const Color(0xFFE53935), // 蓝 / 红
                borderRadius: BorderRadius.circular(4),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _isPaused = !_isPaused;
                      if (!_isPaused) {
                        // 恢复时立即同步最新日志
                        _localLogs = List.from(widget.manager.logs.value);
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    width: 60,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(_isPaused ? '开始' : '暂停', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 渲染单条日志块
  Widget _buildLogItem(LogItem log) {
    // 状态判定
    bool isError = log.type == 'error' || log.type == 'err';
    bool isWarn = log.type == 'warn' || log.type == 'warning';
    
    String emoji = isError ? '❌' : (isWarn ? '⚠️' : '✅');
    Color msgColor = isError ? Colors.redAccent : (isWarn ? Colors.orangeAccent : Colors.green);

    // 智能提取目标地址：优先用 parseLog 提取的 dest，若无则尝试按 "-->" 切割
    String dest = log.destination;
    if (dest.isEmpty && log.msg.contains('-->')) {
      final parts = log.msg.split('-->');
      if (parts.length > 1) dest = parts[1].trim();
    }
    if (dest.isEmpty) dest = 'Unknown Destination';

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
            // 第一行：状态符号 [TCP] 127.0.0.1:xxx --> yyy + 时间
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(text: '$emoji ', style: const TextStyle(fontSize: 12)),
                        TextSpan(text: log.msg, style: TextStyle(color: msgColor, fontSize: 13, fontFamily: 'Consolas')),
                      ],
                    ),
                  ),
                ),
                Text(log.time, style: const TextStyle(color: Colors.white54, fontSize: 12, fontFamily: 'Consolas')),
              ],
            ),
            
            // 如果是详细模式，展示下面两行
            if (_isDetailed) ...[
              const SizedBox(height: 3),
              // 第二行：▼ 目标地址
              Row(
                children: [
                  const Text('▼ ', style: TextStyle(color: Colors.white54, fontSize: 10)),
                  Expanded(
                    child: Text(dest, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              // 第三行：RULE → 规则  PROXY → 节点
              RichText(
                text: TextSpan(
                  style: const TextStyle(fontSize: 12, fontFamily: 'Consolas'),
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

  // 呼出右键复制菜单
  void _showRightClickMenu(BuildContext context, Offset position, String rawMsg) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      color: const Color(0xFF2C2C36),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      items: [
        PopupMenuItem(
          height: 35,
          child: const Text('复制日志 (Copy Payload)', style: TextStyle(color: Colors.white, fontSize: 13)),
          onTap: () {
            Clipboard.setData(ClipboardData(text: rawMsg));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已复制到剪贴板', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green, duration: Duration(seconds: 1)),
            );
          },
        ),
      ],
    );
  }
}

// ---- CFW 风格的连体切换按钮组件 ----
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
    const activeColor = Color(0xFF1396B2); // CFW 经典的青蓝色
    const inactiveColor = Color(0xFF383842); // 深灰背景
    
    return Container(
      height: 24,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: inactiveColor,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 左侧按钮
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
          // 右侧按钮
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