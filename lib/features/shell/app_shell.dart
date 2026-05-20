import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/lunio_tokens.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.selectedIndex});

  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final pages = const [
      _ShellPage(title: '保养提醒', body: '技术底座已接入，完整提醒 UI 后续实现。'),
      _ShellPage(title: '保养记录', body: '记录列表、筛选与新增流程将在业务 UI 阶段落地。'),
      _ShellPage(title: '我的', body: '车辆管理、备份恢复和手动日期入口后续接入。'),
    ];

    return Scaffold(
      backgroundColor: tokens.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
          child: pages[selectedIndex],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(tokens.radiusXl),
          child: NavigationBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: (index) {
              switch (index) {
                case 0:
                  context.go('/reminders');
                case 1:
                  context.go('/records');
                case 2:
                  context.go('/me');
              }
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_repair_service_outlined),
                selectedIcon: Icon(Icons.home_repair_service),
                label: '提醒',
              ),
              NavigationDestination(
                icon: Icon(Icons.format_list_bulleted_outlined),
                selectedIcon: Icon(Icons.format_list_bulleted),
                label: '记录',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: '我的',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShellPage extends StatelessWidget {
  const _ShellPage({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 8),
        Text(body, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Lunio 技术底座',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                Text(
                  'Flutter 单仓、Riverpod、go_router、Drift/SQLite、业务规则与 schemaVersion 1 备份格式已经进入工程。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: () {}, child: const Text('占位操作')),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: tokens.primarySoft,
            borderRadius: BorderRadius.circular(tokens.radiusMedium),
          ),
          child: Text(
            '当前阶段不承诺完整业务 UI；这里用于验证主题、路由和 iOS 启动链路。',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: tokens.primary),
          ),
        ),
      ],
    );
  }
}
