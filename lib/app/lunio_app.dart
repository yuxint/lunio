import 'package:flutter/material.dart';

import 'app_router.dart';
import '../core/theme/lunio_theme.dart';

class LunioApp extends StatelessWidget {
  const LunioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Lunio',
      theme: buildLunioTheme(),
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
