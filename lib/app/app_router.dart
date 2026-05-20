import 'package:go_router/go_router.dart';

import '../features/shell/app_shell.dart';

final appRouter = GoRouter(
  initialLocation: '/reminders',
  routes: [
    GoRoute(
      path: '/reminders',
      builder: (context, state) => const AppShell(selectedIndex: 0),
    ),
    GoRoute(
      path: '/records',
      builder: (context, state) => const AppShell(selectedIndex: 1),
    ),
    GoRoute(
      path: '/me',
      builder: (context, state) => const AppShell(selectedIndex: 2),
    ),
  ],
);
