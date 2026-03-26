import 'package:flutter/material.dart';
import '../core/mihomo_manager.dart';

class ProxiesPage extends StatelessWidget {
  final MihomoManager manager;
  const ProxiesPage({Key? key, required this.manager}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 顶部模式切换栏
        Container(
          height: 60,
          color: const Color(0xFF22222B),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ValueListenableBuilder<Map<String, dynamic>>(
            valueListenable: manager.config,
            builder: (context, config, _) {
              final currentMode = (config['mode'] ?? 'rule').toString().toLowerCase();
              return Row(
                children: [
                  _buildModeButton('全局', 'global', Icons.language, currentMode),
                  const SizedBox(width: 10),
                  _buildModeButton('规则', 'rule', Icons.call_split, currentMode),
                  const SizedBox(width: 10),
                  _buildModeButton('直连', 'direct', Icons.keyboard_double_arrow_right, currentMode),
                  const SizedBox(width: 10),
                  _buildModeButton('脚本', 'script', Icons.code, currentMode),
                ],
              );
            },
          ),
        ),
        // 底部内容区
        Expanded(
          child: ValueListenableBuilder<Map<String, dynamic>>(
            valueListenable: manager.config,
            builder: (context, config, _) {
              final currentMode = (config['mode'] ?? 'rule').toString().toLowerCase();
              if (currentMode == 'direct') return const Center(child: Text('所有流量都会直连', style: TextStyle(color: Colors.white54, fontSize: 16)));
              if (currentMode == 'script') return const Center(child: Text('脚本模式 (暂未实现)', style: TextStyle(color: Colors.white54, fontSize: 16)));
              if (currentMode == 'global') return _ProxyGroupGrid(manager: manager, groupName: 'GLOBAL'); // 独立渲染全局节点

              // 规则模式：渲染多 Tab
              return ValueListenableBuilder<List<String>>(
                valueListenable: manager.groupNames,
                builder: (context, groups, _) {
                  if (groups.isEmpty) return const Center(child: Text('没有获取到代理组', style: TextStyle(color: Colors.white54)));
                  return DefaultTabController(
                    length: groups.length,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: TabBar(
                            isScrollable: true,
                            indicatorColor: Colors.green, labelColor: Colors.green, unselectedLabelColor: Colors.white60,
                            dividerColor: Colors.transparent, // 去除下划线
                            tabs: groups.map((g) => Tab(text: g)).toList(),
                          ),
                        ),
                        Expanded(
                          child: TabBarView(
                            children: groups.map((g) => _ProxyGroupGrid(manager: manager, groupName: g)).toList(),
                          ),
                        ),
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

  Widget _buildModeButton(String title, String modeKey, IconData icon, String currentMode) {
    final isSelected = currentMode == modeKey;
    return Material(
      color: isSelected ? const Color(0xFF3A4B3A) : const Color(0xFF383842),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: () => manager.updateConfig('mode', modeKey),
        borderRadius: BorderRadius.circular(6),
        hoverColor: Colors.white10,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: TextStyle(color: isSelected ? Colors.greenAccent : Colors.white70, fontSize: 14, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
              const SizedBox(width: 6),
              Icon(icon, size: 16, color: isSelected ? Colors.greenAccent : Colors.white54),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProxyGroupGrid extends StatelessWidget {
  final MihomoManager manager;
  final String groupName;

  const _ProxyGroupGrid({Key? key, required this.manager, required this.groupName}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 局部监听 proxiesData，避免全局重绘导致滚轮重置
    return ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: manager.proxiesData,
      builder: (context, proxiesData, _) {
        final groupData = proxiesData[groupName] ?? {};
        final List<dynamic> allNodes = groupData['all'] ?? [];
        final String nowSelected = groupData['now'] ?? '';

        if (allNodes.isEmpty) return const Center(child: Text('无节点', style: TextStyle(color: Colors.white24)));

        return GridView.builder(
          key: PageStorageKey<String>(groupName), // 核心：切换 Tab 时保留此网格的滚动位置
          padding: const EdgeInsets.all(20),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, // 强制 2 列
            mainAxisExtent: 60, // 压缩节点高度
            crossAxisSpacing: 15,
            mainAxisSpacing: 15,
          ),
          itemCount: allNodes.length,
          itemBuilder: (context, index) {
            final nodeName = allNodes[index].toString();
            final nodeData = proxiesData[nodeName] ?? {};
            final type = nodeData['type'] ?? 'Unknown';
            final isSelected = nowSelected == nodeName;

            return InkWell(
              onTap: () => manager.switchProxy(groupName, nodeName),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF3A4B3A) : const Color(0xFF2C2C36),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: isSelected ? Colors.green : Colors.transparent, width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(nodeName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: isSelected ? Colors.greenAccent : Colors.white, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(type, style: const TextStyle(fontSize: 11, color: Colors.white54)),
                        const Text('测速', style: TextStyle(fontSize: 11, color: Colors.white24)), // 暂留测速占位
                      ],
                    )
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
