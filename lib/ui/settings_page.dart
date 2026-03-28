import 'package:flutter/material.dart';
import '../core/mihomo_manager.dart';
import '../main.dart'; 

class SettingsPage extends StatefulWidget {
  final MihomoManager manager;
  const SettingsPage({Key? key, required this.manager}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _timeoutController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final config = widget.manager.config.value;
    _urlController.text = config['test_url']?.toString() ?? '';
    _timeoutController.text = config['test_timeout']?.toString() ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return SubPageLayout(
      header: const Text('设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
      content: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
        children: [
          _buildInputRow(
            '延迟测试网址',
            _urlController,
            'http://www.gstatic.com/generate_204',
            (val) => widget.manager.updateConfig('test_url', val),
          ),
          const SizedBox(height: 15),
          _buildInputRow(
            '延迟测试超时',
            _timeoutController,
            '3000',
            (val) {
              final timeout = int.tryParse(val);
              if (timeout != null) {
                widget.manager.updateConfig('test_timeout', timeout);
              }
            },
            isNumber: true,
            suffix: 'ms',
          ),
        ],
      ),
    );
  }

  Widget _buildInputRow(String label, TextEditingController controller, String hint, Function(String) onChanged, {bool isNumber = false, String? suffix}) {
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: const TextStyle(fontSize: 15, color: Colors.white70)),
        ),
        Expanded(
          child: TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            keyboardType: isNumber ? TextInputType.number : TextInputType.text,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.white24),
              filled: true,
              // 修改：输入框背景色改为 #373542
              fillColor: const Color(0xFF373542),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              suffixText: suffix,
              suffixStyle: const TextStyle(color: Colors.white54),
            ),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}