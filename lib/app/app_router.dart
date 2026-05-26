import 'package:go_router/go_router.dart';

import '../features/shell/app_shell.dart';

GoRouter buildAppRouter() {
  return GoRouter(
    initialLocation: '/reminders',
    routes: [
      GoRoute(
        path: '/reminders',
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: AppShell(selectedIndex: 0)),
      ),
      GoRoute(
        path: '/records',
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: AppShell(selectedIndex: 1)),
      ),
      GoRoute(
        path: '/me',
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: AppShell(selectedIndex: 2)),
      ),
    ],
  );
}
