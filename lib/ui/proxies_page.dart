import 'package:flutter/material.dart';
import '../core/mihomo_manager.dart';

class ProxiesPage extends StatelessWidget {
  final MihomoManager manager;
  const ProxiesPage({Key? key, required this.manager}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: manager.isLoadingProxies,
      builder: (context, loading, _) {
        if (loading) return const Center(child: CircularProgressIndicator());
        return ValueListenableBuilder<List<String>>(
          valueListenable: manager.groupNames,
          builder: (context, groups, _) {
            if (groups.isEmpty) return const Center(child: Text('没有获取到代理组'));
            return DefaultTabController(
              length: groups.length,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: TabBar(
                            isScrollable: true,
                            indicatorColor: Colors.green,
                            labelColor: Colors.green,
                            unselectedLabelColor: Colors.white60,
                            tabs: groups.map((g) => Tab(text: g)).toList(),
                          ),
                        ),
                        IconButton(icon: const Icon(Icons.wifi_protected_setup), tooltip: '测速', onPressed: () {}),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ValueListenableBuilder<Map<String, dynamic>>(
                      valueListenable: manager.proxiesData,
                      builder: (context, proxiesData, _) {
                        return TabBarView(
                          children: groups.map((groupName) {
                            var groupData = proxiesData[groupName] ?? {};
                            List<dynamic> allNodes = groupData['all'] ?? [];
                            String nowSelected = groupData['now'] ?? '';

                            return GridView.builder(
                              padding: const EdgeInsets.all(20),
                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 200,
                                mainAxisExtent: 65,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                              ),
                              itemCount: allNodes.length,
                              itemBuilder: (context, index) {
                                String nodeName = allNodes[index];
                                var nodeData = proxiesData[nodeName];
                                String type = nodeData != null ? nodeData['type'] : 'Unknown';
                                bool isSelected = (nowSelected == nodeName);

                                return InkWell(
                                  onTap: () => manager.switchProxy(groupName, nodeName),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF383842),
                                      borderRadius: BorderRadius.circular(6),
                                      border: isSelected ? Border.all(color: Colors.green, width: 2) : null,
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(nodeName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Colors.white)),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(type, style: const TextStyle(fontSize: 10, color: Colors.white54)),
                                            const Text('ms', style: TextStyle(fontSize: 10, color: Colors.green)),
                                          ],
                                        )
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
