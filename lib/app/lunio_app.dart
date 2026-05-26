import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_router.dart';
import 'providers.dart';
import '../core/theme/lunio_theme.dart';

class LunioApp extends ConsumerWidget {
  const LunioApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref
        .watch(themeModePreferenceProvider)
        .maybeWhen(data: (value) => value, orElse: () => ThemeMode.system);
    return MaterialApp.router(
      title: 'Lunio',
      theme: buildLunioTheme(),
      darkTheme: buildLunioTheme(brightness: Brightness.dark),
      themeMode: themeMode,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
