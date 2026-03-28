import 'package:flutter/material.dart';
import '../core/mihomo_manager.dart';
import '../main.dart'; 

class ProxiesPage extends StatelessWidget {
  final MihomoManager manager;
  const ProxiesPage({Key? key, required this.manager}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SubPageLayout(
      header: ValueListenableBuilder<Map<String, dynamic>>(
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
      content: ValueListenableBuilder<Map<String, dynamic>>(
        valueListenable: manager.config,
        builder: (context, config, _) {
          final currentMode = (config['mode'] ?? 'rule').toString().toLowerCase();
          if (currentMode == 'direct') return const Center(child: Text('所有流量都会直连', style: TextStyle(color: Colors.white54, fontSize: 16)));
          if (currentMode == 'script') return const Center(child: Text('脚本模式 (暂未实现)', style: TextStyle(color: Colors.white54, fontSize: 16)));

          return ValueListenableBuilder<Map<String, dynamic>>(
            valueListenable: manager.proxiesData,
            builder: (context, proxiesData, _) {
              return ValueListenableBuilder<int>(
                valueListenable: manager.collapseTrigger,
                builder: (context, _, __) {
                  return ValueListenableBuilder<List<String>>(
                    valueListenable: manager.groupNames,
                    builder: (context, groups, _) {
                      List<String> targetGroups = currentMode == 'global' ? ['GLOBAL'] : groups;
                      if (targetGroups.isEmpty) return const Center(child: Text('没有获取到代理组', style: TextStyle(color: Colors.white54)));
                      
                      return CustomScrollView(
                        key: const PageStorageKey<String>('proxies_rule_list_scroll'),
                        slivers: [
                          const SliverPadding(padding: EdgeInsets.only(top: 20)),
                          for (final groupName in targetGroups)
                            _buildGroupSliver(groupName, proxiesData),
                          const SliverPadding(padding: EdgeInsets.only(bottom: 20)),
                        ],
                      );
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

  Widget _buildGroupSliver(String groupName, Map<String, dynamic> proxiesData) {
    final groupData = proxiesData[groupName] ?? {};
    final List<dynamic> allNodes = groupData['all'] ?? [];
    final String nowSelected = groupData['now'] ?? '';
    final String type = groupData['type'] ?? '';
    final bool isCollapsed = manager.getGroupCollapseState(groupName).value;

    if (allNodes.isEmpty) return const SliverToBoxAdapter(child: SizedBox());

    return SliverMainAxisGroup(
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _GroupHeaderDelegate(
            manager: manager,
            groupName: groupName,
            nowSelected: nowSelected,
            type: type,
            isCollapsed: isCollapsed,
          ),
        ),
        if (!isCollapsed)
          SliverPadding(
            padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20, top: 5),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisExtent: 60,
                crossAxisSpacing: 15,
                mainAxisSpacing: 15,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final nodeName = allNodes[index].toString();
                  return _buildNodeCard(groupName, nodeName, proxiesData, nowSelected);
                },
                childCount: allNodes.length,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildNodeCard(String groupName, String nodeName, Map<String, dynamic> proxiesData, String nowSelected) {
    final nodeData = proxiesData[nodeName] ?? {};
    final nodeType = nodeData['type'] ?? 'Unknown';
    final isSelected = nowSelected == nodeName;

    final history = nodeData['history'] as List<dynamic>?;
    bool isTested = false;
    int delay = 0;

    if (history != null && history.isNotEmpty) {
      isTested = true;
      delay = history.last['delay'] ?? 0;
    } else if (nodeData.containsKey('delay')) {
      isTested = true;
      delay = nodeData['delay'] ?? 0;
    }

    String delayStr;
    Color delayColor;

    if (!isTested) {
      delayStr = '测速';
      delayColor = Colors.white54;
    } else if (delay <= 0) {
      delayStr = '超时';
      delayColor = Colors.redAccent;
    } else {
      delayStr = '${delay}ms';
      delayColor = delay < 800 ? Colors.greenAccent : (delay < 1200 ? Colors.orangeAccent : Colors.redAccent);
    }

    return InkWell(
      onTap: () => manager.switchProxy(groupName, nodeName),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          // 修改：节点项颜色 #373542，选中时加浅绿色半透明
          color: isSelected ? const Color(0x3300AA00) : const Color(0xFF373542),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? const Color(0xFF00AA00) : Colors.transparent, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(nodeName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: isSelected ? const Color(0xFF00FF00) : Colors.white, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(nodeType, style: const TextStyle(fontSize: 11, color: Colors.white54)),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => manager.testProxyDelay(nodeName),
                    borderRadius: BorderRadius.circular(4),
                    hoverColor: Colors.white12,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Text(
                        delayStr,
                        style: TextStyle(fontSize: 11, color: delayColor, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  // 修改：选中颜色 #3AA1CC，未选中颜色 #42424E
  Widget _buildModeButton(String title, String modeKey, IconData icon, String currentMode) {
    final isSelected = currentMode == modeKey;
    return Material(
      color: isSelected ? const Color(0xFF3AA1CC) : const Color(0xFF42424E),
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
              Text(title, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 14, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
              const SizedBox(width: 6),
              Icon(icon, size: 16, color: isSelected ? Colors.white : Colors.white54),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupHeaderDelegate extends SliverPersistentHeaderDelegate {
  final MihomoManager manager;
  final String groupName;
  final String nowSelected;
  final String type;
  final bool isCollapsed;

  _GroupHeaderDelegate({
    required this.manager,
    required this.groupName,
    required this.nowSelected,
    required this.type,
    required this.isCollapsed,
  });

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      // 修改：吸顶头部背景色改为右侧底色 #2C2A38
      color: const Color(0xFF2C2A38),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: Alignment.center,
      child: Material(
        color: overlapsContent ? const Color(0xFF373542) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: () => manager.toggleGroupCollapse(groupName),
          borderRadius: BorderRadius.circular(6),
          hoverColor: Colors.white10,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: Row(
              children: [
                Icon(isCollapsed ? Icons.chevron_right : Icons.expand_more, color: Colors.white54, size: 20),
                const SizedBox(width: 8),
                Text(groupName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(width: 10),
                if (nowSelected.isNotEmpty) ...[
                  Expanded(
                    child: Text(
                      nowSelected,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // 修改：组头中当前节点颜色改为 #00FF00
                      style: const TextStyle(fontSize: 13, color: Color(0xFF00FF00)),
                    ),
                  ),
                  const SizedBox(width: 10),
                ] else ...[
                  const Spacer(),
                ],
                IconButton(
                  icon: const Icon(Icons.network_ping, size: 18, color: Colors.white54),
                  tooltip: '组测速',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                  splashRadius: 16,
                  onPressed: () => manager.testGroupDelay(groupName),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  // 修改：组类型标签背景色 #373542
                  decoration: BoxDecoration(color: const Color(0xFF373542), borderRadius: BorderRadius.circular(4)),
                  child: Text(type, style: const TextStyle(fontSize: 11, color: Colors.white54)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  double get maxExtent => 48.0;

  @override
  double get minExtent => 48.0;

  @override
  bool shouldRebuild(covariant _GroupHeaderDelegate oldDelegate) {
    return oldDelegate.groupName != groupName ||
        oldDelegate.nowSelected != nowSelected ||
        oldDelegate.type != type ||
        oldDelegate.isCollapsed != isCollapsed;
  }
}