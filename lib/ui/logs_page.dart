import 'package:flutter/material.dart';
import '../core/mihomo_manager.dart';

class LogsPage extends StatelessWidget {
  final MihomoManager manager;
  const LogsPage({Key? key, required this.manager}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          color: const Color(0xFF1E1E24),
          child: const Row(
            children: [
              SizedBox(width: 80, child: Text('Time', style: TextStyle(color: Colors.white54)) ),
              SizedBox(width: 80, child: Text('Type', style: TextStyle(color: Colors.white54)) ),
              Expanded(flex: 3, child: Text('Payload', style: TextStyle(color: Colors.white54)) ),
              Expanded(flex: 1, child: Text('Rule', style: TextStyle(color: Colors.white54)) ),
            ],
          ),
        ),
        Expanded(
          child: ValueListenableBuilder<List<LogItem>>(
            valueListenable: manager.logs,
            builder: (context, logs, _) {
              return ListView.builder(
                itemCount: logs.length,
                itemBuilder: (context, index) {
                  final log = logs[index];
                  Color typeColor = Colors.blue;
                  if (log.type == 'warn') typeColor = Colors.orange;
                  if (log.type == 'error') typeColor = Colors.red;

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 80, child: Text(log.time, style: const TextStyle(fontSize: 12, color: Colors.white70)) ),
                        SizedBox(width: 80, child: Text(log.type.toUpperCase(), style: TextStyle(fontSize: 12, color: typeColor, fontWeight: FontWeight.bold)) ),
                        Expanded(flex: 3, child: SelectableText(log.msg, style: const TextStyle(fontSize: 12)) ),
                        Expanded(flex: 1, child: Text(log.rule, style: const TextStyle(fontSize: 12, color: Colors.grey)) ),
                      ],
                    ),
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
