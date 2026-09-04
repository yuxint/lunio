// parking 域 widget 测试（自原 widget_test.dart 按页面域拆分，
// 共享夹具见 test/helpers/widget_app.dart）。
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lunio/core/date/app_date_context.dart';

import 'package:lunio/data/database/app_database.dart';
import 'package:lunio/domain/entities/parking_countdown.dart';
import '../helpers/widget_app.dart';

void main() {
  testWidgets('reminders can start and end parking countdown', (tester) async {
    final database = await pumpApp(
      tester,
      dateContext: AppDateContext(
        readSystemNow: () => DateTime(2026, 6, 10, 10, 20),
      ),
    );
    await createDefaultCar(tester);

    await tester.tap(find.text('提醒'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '停车倒计时'));
    await tester.pumpAndSettle();

    expect(find.text('停车计时'), findsOneWidget);
    expect(find.text('入场时间'), findsOneWidget);
    expect(find.text('10:20:00'), findsOneWidget);
    expect(find.text('免费时长'), findsOneWidget);
    expect(find.text('0.5 小时'), findsOneWidget);
    await tester.tap(find.text('开始计时'));
    await tester.pumpAndSettle();

    expect(find.text('剩余充足'), findsNothing);
    expect(find.text('10:50:00 前离场'), findsOneWidget);
    expect(find.textContaining('还剩'), findsNothing);
    expect(await testRepository(database).getParkingCountdown(), isNotNull);

    await tester.tap(find.widgetWithText(TextButton, '结束'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, '停车倒计时'), findsOneWidget);
    expect(await testRepository(database).getParkingCountdown(), isNull);
  });


  testWidgets('parking countdown sheet keeps actions above keyboard', (
    tester,
  ) async {
    await pumpApp(
      tester,
      dateContext: AppDateContext(
        readSystemNow: () => DateTime(2026, 6, 10, 10, 20),
      ),
    );
    await createDefaultCar(tester);
    await tester.tap(find.text('提醒'));
    await tester.pumpAndSettle();

    const keyboardHeight = 360.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboardHeight);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, '停车倒计时'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextField, '免费时长'));
    await tester.pumpAndSettle();

    final keyboardTop =
        tester.view.physicalSize.height / tester.view.devicePixelRatio -
        keyboardHeight;
    final startButtonBottom = tester
        .getBottomLeft(find.widgetWithText(FilledButton, '开始计时'))
        .dy;
    expect(startButtonBottom, lessThanOrEqualTo(keyboardTop));
  });


  testWidgets('parking countdown starts Android notification timer', (
    tester,
  ) async {
    final notificationCalls = <MethodCall>[];
    final cleanupNotifications = mockAndroidNotifications(notificationCalls);
    try {
      await pumpApp(
        tester,
        dateContext: AppDateContext(readSystemNow: () => DateTime.now()),
        systemNotificationsEnabled: true,
      );
      await createDefaultCar(tester);
      notificationCalls.clear();

      await tester.tap(find.text('提醒'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '停车倒计时'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始计时'));
      await tester.pumpAndSettle();

      expect(
        notificationCalls.map((call) => call.method),
        containsAll(<String>[
          'requestNotificationsPermission',
          'show',
          'zonedSchedule',
        ]),
      );
      final showCall = notificationCalls.singleWhere(
        (call) => call.method == 'show',
      );
      final showArguments = showCall.arguments as Map<Object?, Object?>;
      final showSpecifics =
          showArguments['platformSpecifics'] as Map<Object?, Object?>;
      expect(showSpecifics['channelId'], 'lunio_parking_ongoing');
      expect(showSpecifics['ongoing'], isTrue);
      expect(showSpecifics['chronometerCountDown'], isTrue);
    } finally {
      cleanupNotifications();
    }
  });


  testWidgets('parking countdown accepts custom minutes', (tester) async {
    final database = await pumpApp(
      tester,
      dateContext: AppDateContext(
        readSystemNow: () => DateTime(2026, 6, 10, 10, 20),
      ),
    );
    await createDefaultCar(tester);

    await tester.tap(find.text('提醒'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '停车倒计时'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '免费时长'), '45');
    await tester.tap(find.text('开始计时'));
    await tester.pumpAndSettle();

    expect(find.text('11:05:00 前离场'), findsOneWidget);
    expect(find.textContaining('还剩'), findsNothing);
    final countdown = await testRepository(database).getParkingCountdown();
    expect(countdown?.durationSeconds, 2700);
  });


  testWidgets('parking countdown entry time uses scroll wheels', (
    tester,
  ) async {
    await pumpApp(
      tester,
      dateContext: AppDateContext(
        readSystemNow: () => DateTime(2026, 6, 10, 10, 20, 15),
      ),
    );
    await createDefaultCar(tester);

    await tester.tap(find.text('提醒'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '停车倒计时'));
    await tester.pumpAndSettle();

    final durationField = tester.widget<TextField>(
      find.widgetWithText(TextField, '免费时长'),
    );
    // 数字输入统一数字键盘（整数，不带小数点）。
    expect(durationField.keyboardType, const TextInputType.numberWithOptions());
    expect(durationField.textInputAction, TextInputAction.done);
    expect(durationField.inputFormatters, hasLength(1));
    expect(
      durationField.inputFormatters!.single,
      isA<FilteringTextInputFormatter>(),
    );

    // 入场时间默认取点按钮此刻的系统时间，秒/毫秒截 0（10:20:15 → 10:20:00）。
    await tester.tap(find.text('10:20:00'));
    await tester.pumpAndSettle();

    expect(find.text('选择入场时间'), findsOneWidget);
    expect(find.byType(CupertinoPicker), findsNWidgets(3));
    expect(find.text('时'), findsOneWidget);
    expect(find.text('分'), findsOneWidget);
    expect(find.text('秒'), findsOneWidget);
  });


  testWidgets('reminders show expired parking countdown', (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    await testRepository(database).saveParkingCountdown(
      ParkingCountdown(
        startedAt: DateTime(2026, 6, 10, 10, 20, 15),
        durationSeconds: 1800,
      ),
    );

    await pumpApp(
      tester,
      database: database,
      dateContext: AppDateContext(
        readSystemNow: () => DateTime(2026, 6, 10, 11, 2, 15),
      ),
    );

    expect(find.text('已超时'), findsNothing);
    expect(find.text('停车时长'), findsOneWidget);
    expect(find.text('42:00'), findsOneWidget);
    expect(find.text('+12:00'), findsNothing);
    expect(find.textContaining('已超 '), findsNothing);
    expect(find.text('10:50:15 已到点'), findsOneWidget);
  });


  testWidgets('parking countdown button is disabled while countdown runs', (
    tester,
  ) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    await testRepository(database).saveParkingCountdown(
      ParkingCountdown(
        startedAt: DateTime(2026, 6, 10, 10, 20),
        durationSeconds: 1800,
      ),
    );
    await pumpApp(
      tester,
      database: database,
      dateContext: AppDateContext(
        readSystemNow: () => DateTime(2026, 6, 10, 10, 20),
      ),
    );
    await createDefaultCar(tester);

    await tester.tap(find.text('提醒'));
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '停车倒计时'),
    );
    expect(button.onPressed, isNull);

    await tester.tap(find.widgetWithText(FilledButton, '停车倒计时'));
    await tester.pumpAndSettle();
    expect(find.text('停车计时'), findsNothing);
  });


  testWidgets(
    'clearing data cancels parking and reminder notifications and keeps catalog',
    (tester) async {
      final notificationCalls = <MethodCall>[];
      final cleanupNotifications = mockAndroidNotifications(notificationCalls);
      try {
        final database = await pumpApp(
          tester,
          dateContext: AppDateContext(readSystemNow: () => DateTime.now()),
          systemNotificationsEnabled: true,
        );
        await createDefaultCar(tester);

        // 先启动停车倒计时，制造 9001/9002 系统通知。
        await tester.tap(find.text('提醒'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, '停车倒计时'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('开始计时'));
        await tester.pumpAndSettle();
        expect(
          notificationCalls.map((call) => call.method),
          containsAll(<String>['show', 'zonedSchedule']),
        );
        notificationCalls.clear();

        await tester.tap(find.text('我的'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, '清空'));
        await tester.pumpAndSettle();
        // 清空确认文案明示目录表保留。
        expect(find.textContaining('默认车辆模型与默认保养项目目录会保留'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, '清空'));
        await tester.pumpAndSettle();

        final cancelledIds = notificationCalls
            .where((call) => call.method == 'cancel')
            .map((call) => (call.arguments as Map<Object?, Object?>)['id'])
            .whereType<int>()
            .toSet();
        expect(cancelledIds, containsAll([9001, 9002]));
        // R10 收紧：取消只发 16 个在用 id，不再整段扫 8000~8999。
        expect(
          cancelledIds.where((id) => id >= 8000 && id < 9000),
          <int>{
            for (var index = 0; index < 8; index++) 8000 + index,
            for (var index = 0; index < 8; index++) 8900 + index,
          },
        );
        expect(find.text('已清空数据'), findsOneWidget);
        expect(await database.select(database.cars).get(), isEmpty);
        expect(
          await database.select(database.maintenanceItems).get(),
          isEmpty,
        );
        // 注意：appPreferences 不恒为空——清空后同步引擎按首启语义
        // 重新初始化通知权限，会立刻写回 systemNotificationPermission*
        // 两个 key。这里只断言业务偏好确实被清掉。
        expect(
          await testRepository(database).getParkingCountdown(),
          isNull,
        );
        expect(
          await testRepository(database).getPreferenceValue('themeMode'),
          isNull,
        );
        // 默认目录表保留（清空语义）。
        expect(
          await database.select(database.vehicleDefaultMaintenanceItems).get(),
          isNotEmpty,
        );
        expect(await database.select(database.vehicleModels).get(), isNotEmpty);
      } finally {
        cleanupNotifications();
      }
    },
  );
}
