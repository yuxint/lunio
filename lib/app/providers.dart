import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/date/app_date_context.dart';
import '../data/database/app_database.dart';
import '../data/repositories/lunio_repository.dart';

final appDateContextProvider = Provider<AppDateContext>(
  (ref) => AppDateContext.system(),
);

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

final lunioRepositoryProvider = Provider<LunioRepository>((ref) {
  return LunioRepository(ref.watch(appDatabaseProvider));
});
