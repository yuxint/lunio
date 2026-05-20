import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lunio/app/lunio_app.dart';

void main() {
  testWidgets('app shell exposes three main entries', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: LunioApp()));

    expect(find.text('保养提醒'), findsOneWidget);
    expect(find.text('提醒'), findsOneWidget);
    expect(find.text('记录'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
  });
}
