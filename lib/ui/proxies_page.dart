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
              if (currentMode == 'global') return _CollapsibleProxyGroup(manager: manager, groupName: 'GLOBAL'); // 独立渲染全局节点

              // 规则模式：流式布局，按组折叠
              return ValueListenableBuilder<List<String>>(
                valueListenable: manager.groupNames,
                builder: (context, groups, _) {
                  if (groups.isEmpty) return const Center(child: Text('没有获取到代理组', style: TextStyle(color: Colors.white54)));
                  return ListView.builder(
                    key: const PageStorageKey<String>('proxies_rule_list_scroll'), // 核心：记忆规则模式的滚动位置
                    padding: const EdgeInsets.all(20),
                    itemCount: groups.length,
                    itemBuilder: (context, index) {
                      return _CollapsibleProxyGroup(manager: manager, groupName: groups[index]);
                    },
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

class _CollapsibleProxyGroup extends StatelessWidget {
  final MihomoManager manager;
  final String groupName;

  const _CollapsibleProxyGroup({Key? key, required this.manager, required this.groupName}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: manager.proxiesData,
      builder: (context, proxiesData, _) {
        final groupData = proxiesData[groupName] ?? {};
        final List<dynamic> allNodes = groupData['all'] ?? [];
        final String nowSelected = groupData['now'] ?? '';
        final String type = groupData['type'] ?? '';

        if (allNodes.isEmpty) return const SizedBox();

        return ValueListenableBuilder<bool>(
          valueListenable: manager.getGroupCollapseState(groupName),
            builder: (context, isCollapsed, _) {
            return Container(
              margin: const EdgeInsets.only(bottom: 3), // 核心修改：大幅压缩组与组之间的间距
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 组标题头部 (点击折叠/展开)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => manager.toggleGroupCollapse(groupName),
                      borderRadius: BorderRadius.circular(6),
                      hoverColor: Colors.white10,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                        child: Row(
                          children: [
                            Icon(isCollapsed ? Icons.chevron_right : Icons.expand_more, color: Colors.white54, size: 20),
                            const SizedBox(width: 8),
                            Text(groupName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                            const SizedBox(width: 10),

                            // 显示当前选中的节点名称
                            if (nowSelected.isNotEmpty) ...[
                              Expanded(
                                child: Text(
                                  nowSelected,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13, color: Colors.greenAccent),
                                ),
                              ),
                              const SizedBox(width: 10),
                            ] else ...[
                              const Spacer(),
                            ],

                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: const Color(0xFF383842), borderRadius: BorderRadius.circular(4)),
                              child: Text(type, style: const TextStyle(fontSize: 11, color: Colors.white54)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2), // 核心修改：压缩标题和下方网格之间的间距
                  // 节点网格区
                  if (!isCollapsed)
                    GridView.builder(
                      shrinkWrap: true, // 核心：允许嵌套在 ListView 中
                      physics: const NeverScrollableScrollPhysics(), // 禁掉自身滚动，交由外层 ListView 统一滚动
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2, // 强制 2 列
                        mainAxisExtent: 60, // 节点高度
                        crossAxisSpacing: 15,
                        mainAxisSpacing: 15,
                      ),
                      itemCount: allNodes.length,
                      itemBuilder: (context, index) {
                        final nodeName = allNodes[index].toString();
                        final nodeData = proxiesData[nodeName] ?? {};
                        final nodeType = nodeData['type'] ?? 'Unknown';
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
                                    Text(nodeType, style: const TextStyle(fontSize: 11, color: Colors.white54)),
                                    const Text('测速', style: TextStyle(fontSize: 11, color: Colors.white24)),
                                  ],
                                )
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            );
          }
        );
      },
    );
  }
}
