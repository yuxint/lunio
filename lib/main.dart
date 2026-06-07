import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/lunio_app.dart';
import 'core/notifications/lunio_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LunioNotificationService.instance.initialize();
  runApp(const ProviderScope(child: LunioApp()));
}
