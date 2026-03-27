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
              if (currentMode == 'global') return _CollapsibleProxyGroup(manager: manager, groupName: 'GLOBAL'); 

              // 规则模式：流式布局，按组折叠
              return ValueListenableBuilder<List<String>>(
                valueListenable: manager.groupNames,
                builder: (context, groups, _) {
                  if (groups.isEmpty) return const Center(child: Text('没有获取到代理组', style: TextStyle(color: Colors.white54)));
                  return ListView.builder(
                    key: const PageStorageKey<String>('proxies_rule_list_scroll'), 
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
              margin: const EdgeInsets.only(bottom: 3),
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

                            // CFW 风格的测速按钮
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
                              decoration: BoxDecoration(color: const Color(0xFF383842), borderRadius: BorderRadius.circular(4)),
                              child: Text(type, style: const TextStyle(fontSize: 11, color: Colors.white54)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  // 节点网格区
                  if (!isCollapsed)
                    GridView.builder(
                      shrinkWrap: true, 
                      physics: const NeverScrollableScrollPhysics(), 
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2, 
                        mainAxisExtent: 60, 
                        crossAxisSpacing: 15,
                        mainAxisSpacing: 15,
                      ),
                      itemCount: allNodes.length,
                      itemBuilder: (context, index) {
                        final nodeName = allNodes[index].toString();
                        final nodeData = proxiesData[nodeName] ?? {};
                        final nodeType = nodeData['type'] ?? 'Unknown';
                        final isSelected = nowSelected == nodeName;

                        // 动态获取历史延迟数据
                        final history = nodeData['history'] as List<dynamic>?;
                        bool isTested = false;
                        int delay = 0;

                        if (history != null && history.isNotEmpty) {
                          isTested = true;
                          delay = history.last['delay'] ?? 0;
                        } else if (nodeData.containsKey('delay')) {
                          // 兼容有些节点初始自带 delay 的情况
                          isTested = true;
                          delay = nodeData['delay'] ?? 0;
                        }

                        String delayStr;
                        Color delayColor;

                        // 状态判断逻辑
                        if (!isTested) {
                          delayStr = '测速';
                          delayColor = Colors.white54;
                        } else if (delay <= 0) {
                          delayStr = '超时';
                          delayColor = Colors.redAccent; // 超时显示红字
                        } else {
                          delayStr = '${delay}ms';
                          // 传统 CFW 配色逻辑
                          delayColor = delay < 800 ? Colors.greenAccent : (delay < 1200 ? Colors.orangeAccent : Colors.redAccent);
                        }

                        return InkWell(
                          onTap: () => manager.switchProxy(groupName, nodeName),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            // 【微调1】将上下内边距从 8 缩小到 6，腾出 4 像素
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                                // 【微调2】将两行文字之间的间距从 4 缩小到 2，腾出 2 像素
                                const SizedBox(height: 2),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(nodeType, style: const TextStyle(fontSize: 11, color: Colors.white54)),
                                    // 纯悬浮高亮按钮，无边框，极简高度
                                    Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () => manager.testProxyDelay(nodeName),
                                        borderRadius: BorderRadius.circular(4),
                                        hoverColor: Colors.white12, // 悬浮时的背景高亮色
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