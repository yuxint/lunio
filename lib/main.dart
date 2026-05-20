import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/lunio_app.dart';

void main() {
  runApp(const ProviderScope(child: LunioApp()));
}
