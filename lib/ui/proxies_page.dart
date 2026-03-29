import 'package:flutter/material.dart';
import '../core/mihomo_manager.dart';
import '../main.dart'; 

class ProxiesPage extends StatefulWidget {
  final MihomoManager manager;
  const ProxiesPage({Key? key, required this.manager}) : super(key: key);

  @override
  State<ProxiesPage> createState() => _ProxiesPageState();
}

class _ProxiesPageState extends State<ProxiesPage> {
  final Map<String, bool> _hideErrorMap = {};
  
  // 核心修复：为每个节点预先分配稳定的静态 GlobalKey，杜绝动态生成 key 导致的组件重建和绿条动画断档！
  final Map<String, GlobalKey> _nodeKeys = {};
  final Map<String, GlobalKey> _groupHeaderKeys = {};

  int _getNodeDelay(String nodeName, Map<String, dynamic> proxiesData) {
    final nodeData = proxiesData[nodeName] ?? {};
    final history = nodeData['history'] as List<dynamic>?;
    if (history != null && history.isNotEmpty) {
      return history.last['delay'] ?? 0;
    } else if (nodeData.containsKey('delay')) {
      return nodeData['delay'] ?? 0;
    }
    return 0; 
  }

  void _handleLocate(String groupName, String nowSelected) {
    if (widget.manager.getGroupCollapseState(groupName).value) {
      widget.manager.toggleGroupCollapse(groupName);
    }
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 通过稳定的字典直接获取已渲染的节点 key
      final nodeKey = _nodeKeys['$groupName-$nowSelected'];
      if (nodeKey != null && nodeKey.currentContext != null) {
        Scrollable.ensureVisible(
          nodeKey.currentContext!,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: 0.5,
        );
      } else {
        final headerKey = _groupHeaderKeys[groupName];
        if (headerKey != null && headerKey.currentContext != null) {
          Scrollable.ensureVisible(
            headerKey.currentContext!,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            alignment: 0.0,
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SubPageLayout(
      header: ValueListenableBuilder<Map<String, dynamic>>(
        valueListenable: widget.manager.config,
        builder: (context, config, _) {
          final currentMode = (config['mode'] ?? 'rule').toString().toLowerCase();
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly, 
            children: [
              _buildModeButton('全局', 'global', Icons.language, currentMode),
              _buildModeButton('规则', 'rule', Icons.call_split, currentMode),
              _buildModeButton('直连', 'direct', Icons.keyboard_double_arrow_right, currentMode),
              _buildModeButton('脚本', 'script', Icons.code, currentMode),
            ],
          );
        },
      ),
      content: ValueListenableBuilder<Map<String, dynamic>>(
        valueListenable: widget.manager.config,
        builder: (context, config, _) {
          final currentMode = (config['mode'] ?? 'rule').toString().toLowerCase();
          if (currentMode == 'direct') return const Center(child: Text('所有流量都会直连', style: TextStyle(color: Colors.white54, fontSize: 16)));
          if (currentMode == 'script') return const Center(child: Text('脚本模式 (暂未实现)', style: TextStyle(color: Colors.white54, fontSize: 16)));

          return ValueListenableBuilder<Map<String, dynamic>>(
            valueListenable: widget.manager.proxiesData,
            builder: (context, proxiesData, _) {
              return ValueListenableBuilder<int>(
                valueListenable: widget.manager.collapseTrigger,
                builder: (context, _, __) {
                  return ValueListenableBuilder<List<String>>(
                    valueListenable: widget.manager.groupNames,
                    builder: (context, groups, _) {
                      List<String> targetGroups = currentMode == 'global' ? ['GLOBAL'] : groups;
                      if (targetGroups.isEmpty) return const Center(child: Text('没有获取到代理组', style: TextStyle(color: Colors.white54)));
                      
                      return Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: CustomScrollView(
                          key: const PageStorageKey<String>('proxies_rule_list_scroll'),
                          slivers: [
                            for (final groupName in targetGroups)
                              _buildGroupSliver(groupName, proxiesData),
                            const SliverPadding(padding: EdgeInsets.only(bottom: 20)),
                          ],
                        ),
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
    final List<dynamic> rawNodes = groupData['all'] ?? [];
    final String nowSelected = groupData['now'] ?? '';
    final String type = groupData['type'] ?? '';
    
    final bool isCollapsed = widget.manager.getGroupCollapseState(groupName).value;
    final bool isHideError = _hideErrorMap[groupName] ?? false;

    List<String> displayNodes = [];
    for (var node in rawNodes) {
      String nodeName = node.toString();
      if (isHideError) {
        int delay = _getNodeDelay(nodeName, proxiesData);
        if (delay > 0 || nodeName == nowSelected) {
          displayNodes.add(nodeName);
        }
      } else {
        displayNodes.add(nodeName);
      }
    }

    if (rawNodes.isEmpty) return const SliverToBoxAdapter(child: SizedBox());

    _groupHeaderKeys[groupName] ??= GlobalKey();

    return SliverMainAxisGroup(
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _GroupHeaderDelegate(
            manager: widget.manager,
            groupName: groupName,
            nowSelected: nowSelected,
            type: type,
            isCollapsed: isCollapsed,
            isHideError: isHideError,
            headerKey: _groupHeaderKeys[groupName],
            onLocate: () => _handleLocate(groupName, nowSelected),
            onToggleHideError: () {
              setState(() {
                _hideErrorMap[groupName] = !isHideError;
              });
            },
          ),
        ),
        if (!isCollapsed)
          SliverPadding(
            padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20, top: 5),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final nodeIndex1 = index * 2;
                  final nodeIndex2 = nodeIndex1 + 1;
                  final node1 = displayNodes[nodeIndex1];
                  final node2 = nodeIndex2 < displayNodes.length ? displayNodes[nodeIndex2] : null;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 15),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch, 
                        children: [
                          Expanded(child: _buildNodeCard(groupName, node1, proxiesData, nowSelected)),
                          const SizedBox(width: 15),
                          if (node2 != null)
                            Expanded(child: _buildNodeCard(groupName, node2, proxiesData, nowSelected))
                          else
                            const Expanded(child: SizedBox()), 
                        ],
                      ),
                    ),
                  );
                },
                childCount: (displayNodes.length / 2).ceil(),
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

    // 核心修复：为节点分配一个稳定存活的 GlobalKey，确保动画状态不被销毁
    final cardKey = _nodeKeys.putIfAbsent('$groupName-$nodeName', () => GlobalKey());

    // 核心修复：仅依靠内核返回的明确 udp 属性判断，不再瞎推测协议
    bool hasUdp = nodeData['udp'] == true;

    int delay = _getNodeDelay(nodeName, proxiesData);
    bool isTested = (nodeData['history'] as List<dynamic>?)?.isNotEmpty == true || nodeData.containsKey('delay');

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

    return Row(
      key: cardKey, 
      crossAxisAlignment: CrossAxisAlignment.stretch, 
      children: [
        SizedBox(
          width: 4,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF454555), 
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              _CfwIndicator(isActive: isSelected, isSwitching: false), 
            ],
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: 66),
            decoration: BoxDecoration(
              color: const Color(0xFF373542),
              borderRadius: BorderRadius.circular(4),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => widget.manager.switchProxy(groupName, nodeName),
                  // 核心修复：用 Container 包住原本的 Padding，设置 alignment 以确保点击水波纹铺满全卡片
                  child: Container(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center, 
                      children: [
                        Text(
                          nodeName,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white,
                            fontWeight: FontWeight.normal,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Row(
                              children: [
                                Text(nodeType, style: const TextStyle(fontSize: 11, color: Colors.white54)),
                                if (hasUdp) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF2C2A38),
                                      borderRadius: BorderRadius.circular(2),
                                      border: Border.all(color: Colors.white12, width: 0.5),
                                    ),
                                    child: const Text('UDP', style: TextStyle(fontSize: 9, color: Colors.white54, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ],
                            ),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => widget.manager.testProxyDelay(nodeName),
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
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModeButton(String title, String modeKey, IconData icon, String currentMode) {
    final isSelected = currentMode == modeKey;
    return Material(
      color: isSelected ? const Color(0xFF3AA1CC) : const Color(0xFF42424E),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: () => widget.manager.updateConfig('mode', modeKey),
        borderRadius: BorderRadius.circular(6),
        hoverColor: Colors.white10,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title, 
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70, 
                  fontSize: 19, 
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal
                )
              ),
              const SizedBox(width: 6),
              Icon(icon, size: 20, color: isSelected ? Colors.white : Colors.white54), 
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
  final bool isHideError;
  final GlobalKey? headerKey;
  final VoidCallback onLocate;
  final VoidCallback onToggleHideError;

  _GroupHeaderDelegate({
    required this.manager,
    required this.groupName,
    required this.nowSelected,
    required this.type,
    required this.isCollapsed,
    required this.isHideError,
    required this.headerKey,
    required this.onLocate,
    required this.onToggleHideError,
  });

  Widget _buildHeaderBtn(IconData icon, String tooltip, VoidCallback onTap, {double size = 16, Color? color}) {
    return IconButton(
      icon: Icon(icon, size: size, color: color ?? Colors.white54),
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      splashRadius: 16,
      onPressed: onTap,
    );
  }

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      key: headerKey,
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
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFF373542), borderRadius: BorderRadius.circular(4)),
                  child: Text(type, style: const TextStyle(fontSize: 11, color: Colors.white)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    nowSelected,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: Colors.white),
                  ),
                ),
                
                _buildHeaderBtn(Icons.my_location, '定位到选中节点', onLocate),
                _buildHeaderBtn(
                  isHideError ? Icons.error : Icons.error_outline, 
                  isHideError ? '显示超时节点' : '隐藏超时节点', 
                  onToggleHideError, 
                  size: 18,
                  color: isHideError ? Colors.orangeAccent : Colors.white54,
                ),
                _buildHeaderBtn(Icons.wifi, '测速', () => manager.testGroupDelay(groupName)),
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
        oldDelegate.isCollapsed != isCollapsed ||
        oldDelegate.isHideError != isHideError;
  }
}

class _CfwIndicator extends StatefulWidget {
  final bool isActive;
  final bool isSwitching;

  const _CfwIndicator({required this.isActive, required this.isSwitching});

  @override
  State<_CfwIndicator> createState() => _CfwIndicatorState();
}

class _CfwIndicatorState extends State<_CfwIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _bounceController;
  late Animation<Alignment> _bounceAnim;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _bounceAnim = AlignmentTween(begin: const Alignment(0, -0.9), end: const Alignment(0, 0.9)).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeInOutSine),
    );

    if (widget.isSwitching) {
      _bounceController.repeat(reverse: true); 
    }
  }

  @override
  void didUpdateWidget(_CfwIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSwitching && !oldWidget.isSwitching) {
      _bounceController.repeat(reverse: true);
    } else if (!widget.isSwitching && oldWidget.isSwitching) {
      _bounceController.stop();
    }
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double targetFraction = widget.isActive ? 1.0 : (widget.isSwitching ? 0.6 : 0.0);

    return AnimatedBuilder(
      animation: _bounceController,
      builder: (context, child) {
        Alignment targetAlignment = widget.isActive ? Alignment.center : (widget.isSwitching ? _bounceAnim.value : Alignment.center);

        return AnimatedAlign(
          duration: const Duration(milliseconds: 400), 
          curve: Curves.easeOutCubic,
          alignment: targetAlignment,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: targetFraction),
            duration: const Duration(milliseconds: 500), 
            curve: Curves.easeOutBack, 
            builder: (context, fraction, child) {
              final safeFraction = fraction.clamp(0.0, 1.0);
              
              if (safeFraction == 0.0) return const SizedBox();
              return FractionallySizedBox(
                heightFactor: safeFraction,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF00AA00), 
                    borderRadius: BorderRadius.circular(4), 
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}