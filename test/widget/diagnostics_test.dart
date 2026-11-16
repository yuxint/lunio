// diagnostics 域 widget 测试（票 05 三区状态机 + 票 06 表单增改删，共享
// 夹具 test/helpers/widget_app.dart 与 diagnostics_fixture.dart）：三区
// 状态机全状态可达（未连接→连接中→已连接→已断开+错误+重连）、油量卡
// 升数按容积估算/未填只显百分比、行级无数据灰态不连坐、启停下一轮生
// 效且不打断当前轮、离开页面断开会话（无 pending timer 残留）；表单
// 增改删（添加行进新增/自定义行进编辑/内置行守卫/删确认/行内校验）。
//
// 时序全走门闩（夹具文件头的配方）：advanceUntil 逐拍放行字节至值出
// 现；advanceRound 一拍时钟进下一轮。零真实定时器——用例收尾只泵帧
// （pop 起始帧/移除帧），无 pending timer 排空负担。
//
// 导航一律走真实入口（我的页开发者区块"进入诊断页"行，context.push
// 真入栈）——深链通道 pushRoute 是 go 语义无栈可弹，返回键用例测不了
// （cost_stats 测试先例注释）。
//
// 播种必须在 pumpApp 之前：装配后直写库不会触发 provider 失效。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lunio/data/database/app_database.dart';
import 'package:lunio/data/preferences/app_preferences.dart';
import 'package:lunio/domain/entities/diagnostics_probe.dart';
import 'package:lunio/domain/entities/diagnostics_parse_type.dart';
import 'package:lunio/features/shell/diagnostics/ble_obd_errors.dart';
import 'package:lunio/features/shell/diagnostics/ble_scan_entries.dart';
import 'package:lunio/features/shell/diagnostics/elm327_session.dart';
import 'package:lunio/features/shell/diagnostics/mock_obd_transport.dart';
import 'package:lunio/features/shell/diagnostics/obd_runtime.dart';
import 'package:lunio/features/shell/diagnostics/obd_verification_commands.dart';
import 'package:lunio/core/widgets/lunio_components.dart';

import '../helpers/builders.dart';
import '../helpers/diagnostics_fixture.dart';
import '../helpers/widget_app.dart';

/// 会话 A 的传输层：disconnect 挂在门闩上，模拟旧 teardown 在新会话
/// 建立之后才恢复（取消订阅竞态回归用例）。
class _SlowDisconnectMock extends MockObdTransport {
  _SlowDisconnectMock({
    required super.responses,
    required super.delay,
    required this.disconnectGate,
  });

  final Completer<void> disconnectGate;

  @override
  Future<void> disconnect() async {
    await disconnectGate.future;
    await super.disconnect();
  }
}

/// 播种应用车辆（可选油箱容积与当前里程）并设为当前车：必须在 pumpApp
/// 之前。[mileageKm] 不传走 builder 默认 10,000。
Future<int> seedAppliedCar(
  AppDatabase database, {
  double? tankCapacity,
  double? totalTankCapacity,
  int? mileageKm,
}) async {
  final bundle = testRepository(database);
  final carId = await bundle.insertCarForTest(
    defaultCar(
      currentMileageKm: mileageKm ?? 10000,
      tankCapacityLiters: tankCapacity,
      totalTankCapacityLiters: totalTankCapacity,
    ),
  );
  await bundle.setAppliedCarId(carId);
  return carId;
}

/// 读当前应用车辆 id（未设置回退第一辆；诊断页每车一套的测试锚点）。
Future<int> appliedCarId(AppDatabase database) async {
  final bundle = testRepository(database);
  final applied = await bundle.preferences.getAppliedCarId();
  if (applied != null) {
    return applied;
  }
  final cars = await database.select(database.cars).get();
  return cars.first.id;
}

/// 离开页面（点返回键）：每用例固定收尾。三次泵帧=pop 起始帧→转场
/// 完成帧→路由移除帧（页面离树，State.dispose 启动会话释放链）；会话
/// 定时全是门闩 Completer（非定时器），无需冲刷。
Future<void> leavePageAndFlush(WidgetTester tester) async {
  await tester.tap(find.byTooltip('返回'));
  // 三拍时长泵：tap 回调在事件冲刷里触发 pop；转场动画进度随假时钟流
  // 逝推进（零时长泵不动它），300ms 转场走完并结算路由移除帧；末拍收
  // dispose 链与重建帧。会话定时全是门闩 Completer（非定时器），无需
  // 冲刷。
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

/// 种子开发者模式与诊断开关（必须在 pumpApp 之前）。obdDeviceId 默认
/// 'dev-1'（票 07 直连记忆路径的种子）；传 null 模拟无记忆首用。
Future<void> seedDeveloperDiagnostics(
  AppDatabase database, {
  String? obdDeviceId = 'dev-1',
}) async {
  final bundle = testRepository(database);
  await bundle.setPreferenceValue('developerModeEnabled', 'true');
  await bundle.setPreferenceValue('diagnosticsEnabled', 'true');
  if (obdDeviceId != null) {
    await bundle.setPreferenceValue('lastObdDeviceId', obdDeviceId);
  }
  // 诊断页每车一套检测点（ADR 0021 修订节）：没播种应用车辆的用例补
  // 一辆默认车，页面才有宿主；显式 seedAppliedCar 的用例之后再加一辆
  // 并覆盖应用车辆，仍是最后设置的那辆生效。
  final cars = await database.select(database.cars).get();
  if (cars.isEmpty) {
    final carId = await bundle.insertCarForTest(defaultCar());
    await bundle.setAppliedCarId(carId);
  }
}

/// 打开诊断页（真实入口）：我的页 → 滚到入口行 → 点行尾"进入"按钮
/// （ProfileSettingRow 只有行尾 TextButton 可点，settings_test 同款）。
Future<void> openDiagnosticsPage(WidgetTester tester) async {
  await gotoTab(tester, '我的');
  await tester.ensureVisible(find.text('进入'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('进入'));
  // pump 1：入口回调在事件冲刷里触发 push（本帧仍是我的页）；pump 2：
  // 一拍时长泵走完 300ms 转场（动画进度随假时钟流逝推进，零时长泵
  // 不动它——不补这拍页面停在半滑入位，页内 tap 全部落空）。
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  // 页面已在栈顶（下层我的页 offstage，finder 默认跳过）。
  expect(find.text('车辆诊断'), findsNWidgets(2));
}

void main() {
  group('三区状态机', () {
    testWidgets('未连接→连接中→已连接→读取值渲染→断开+重连', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final rig = DiagnosticsRig();
      await seedDeveloperDiagnostics(database);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await openDiagnosticsPage(tester);

      // pump 1：入口行回调在事件冲刷里触发 push（本帧仍是我的页）；
      // pump 2 起可观察序列开始。"未连接"是连接前的初始相位（连接动
      // 作在首个可观察帧前已置连接中——mock 流程下它是零帧瞬态；真机
      // BLE 扫描/建链窗口内同理由连接中覆盖），测试断言可观察序列。
      await tester.pump();
      await tester.pump();
      expect(find.text('连接中'), findsOneWidget);

      // 逐拍放行字节：连接完成 + 第一轮轮询，三行值 + 卡值 + 时间戳。
      await rig.advanceUntil(tester, find.text('37.6%'));
      await rig.deliverChunks(tester);
      await rig.deliverChunks(tester);
      expect(find.text('37.6%'), findsNWidgets(2));
      expect(find.text('95℃'), findsNWidgets(2));
      expect(find.text('11.2V'), findsOneWidget);
      expect(find.text('已连接'), findsOneWidget);
      expect(find.text('未更新'), findsNothing);
      expect(find.textContaining('14:30:00'), findsNWidgets(3));

      // 断连：字节流注入 error → 状态条已断开 + 错误文案 + 重连按钮；
      // 连接级失败只上状态条、不弹窗（story 16）。
      rig.mock.injectError(const Elm327SessionException('蓝牙链路中断'));
      await tester.pump();
      await tester.pump();
      expect(find.text('已断开'), findsOneWidget);
      expect(find.text('重连'), findsOneWidget);
      expect(find.text('蓝牙链路中断'), findsOneWidget);
      // 连接级失败只上状态条、不弹窗（story 16 显式断言）。
      expect(find.byType(Dialog), findsNothing);

      // 重连：新会话 AT 序列重发（sentCommands 第二组 ATZ），回到已连接。
      await tester.tap(find.text('重连'));
      await tester.pump();
      await rig.advanceUntil(tester, find.text('已连接'));
      expect(
        rig.mock.sentCommands.where((command) => command == 'ATZ'),
        hasLength(2),
      );
      expect(find.text('37.6%'), findsNWidgets(2));

      await leavePageAndFlush(tester);
    });

    testWidgets('油量卡：升数按容积估算（55L）', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      await seedAppliedCar(database, tankCapacity: 55);
      final rig = DiagnosticsRig();
      await seedDeveloperDiagnostics(database);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await openDiagnosticsPage(tester);
      await rig.advanceUntil(tester, find.text('37.6%'));

      // 容积 55L × 37.6% ≈ 20.7 升（story 10）。
      expect(find.text('≈ 20.7 升'), findsOneWidget);

      await leavePageAndFlush(tester);
    });

    testWidgets('油量卡：双油量（可用 + 估算总油量，ADR 0022）', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      await seedAppliedCar(
        database,
        tankCapacity: 55,
        totalTankCapacity: 60,
      );
      final rig = DiagnosticsRig();
      await seedDeveloperDiagnostics(database);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await openDiagnosticsPage(tester);
      await rig.advanceUntil(tester, find.text('37.6%'));

      // 可用 55 × 37.6% ≈ 20.7；储备 60−55=5；估算总 25.7。
      expect(
        find.text('可用 20.7 升 · 估算总油量 25.7 升'),
        findsOneWidget,
      );

      await leavePageAndFlush(tester);
    });

    testWidgets('油量卡：容积未填只显百分比、不显示升数（story 11）', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final rig = DiagnosticsRig();
      await seedDeveloperDiagnostics(database);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await openDiagnosticsPage(tester);
      await rig.advanceUntil(tester, find.text('37.6%'));

      // 没有升数行（不提示去填）。
      expect(find.textContaining('升'), findsNothing);

      await leavePageAndFlush(tester);
    });

    testWidgets('行级无数据灰态：单条超时不连坐，其他行照常更新', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      // 0167 不在应答表 = Mock 默认静默脚本（不应答）→ 单条超时无数据。
      final rig = DiagnosticsRig(
        responses: rigStandardResponses()..remove('0167'),
      );
      await seedDeveloperDiagnostics(database);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await openDiagnosticsPage(tester);

      // 油量先到，水温在途（不应答）。
      await rig.advanceUntil(tester, find.text('37.6%'));

      // 放行 0167 的 300ms 响应超时 → 行级无数据；串行轮询继续到电压。
      await rig.completeProbeTimeout(tester);
      await rig.deliverChunks(tester);

      // 水温行与水温卡都转无数据灰态（story 15）；行尾附原因（ADR 0023）。
      expect(find.text('无数据'), findsNWidgets(2));
      expect(find.text('超时'), findsOneWidget);
      // 其他行不连坐：油量/电压值仍在，状态条仍是已连接。
      expect(find.text('37.6%'), findsNWidgets(2));
      expect(find.text('11.2V'), findsOneWidget);
      expect(find.text('已连接'), findsOneWidget);
      // 无数据也是一次更新：行尾时间戳照常打点（story 14）。
      expect(find.textContaining('14:30:00'), findsNWidgets(3));

      await leavePageAndFlush(tester);
    });

    testWidgets('启停下一轮生效且不打断当前轮（开关+库+轮询三面对账）', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final rig = DiagnosticsRig();
      await seedDeveloperDiagnostics(database);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await openDiagnosticsPage(tester);
      await rig.advanceUntil(tester, find.text('37.6%'));
      await rig.deliverChunks(tester);
      await rig.deliverChunks(tester);

      // 第一轮已发全部三条（内置序：油量/水温/电压）。
      expect(rig.mock.sentCommands.where((c) => c == 'ATRV'), hasLength(1));

      // 关电压行开关（第三行）：动作层写库 → 逐出 provider → 行开关
      // 即时回落；下一轮快照读 provider 当前值，不再发 ATRV。
      // 电压行的开关（按行定位）：裸 Switch finder 会把下层"我的"页
      // 仍在树里的两个开发者开关一起数进来，at(2) 点到的是油量行。
      final voltageSwitch = find.descendant(
        of: find
            .ancestor(of: find.text('电压'), matching: find.byType(LunioCard))
            .first,
        matching: find.byType(Switch),
      );
      await tester.tap(voltageSwitch);
      // 写库（微任务）→ 逐出 → 重算（微任务）→ 数据分支重建：三拍覆盖。
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(tester.widget<Switch>(voltageSwitch).value, isFalse);
      await rig.advanceRound(tester);
      await rig.deliverChunks(tester);
      await rig.deliverChunks(tester);

      expect(
        rig.mock.sentCommands.where((c) => c == 'ATRV'),
        hasLength(1),
      );
      expect(
        rig.mock.sentCommands.where((c) => c == '012F'),
        hasLength(greaterThanOrEqualTo(2)),
      );
      expect(
        (await testRepository(database)
                .diagnosticsRepository
                .listProbes(await appliedCarId(database)))
            .firstWhere((probe) => probe.command == 'ATRV')
            .enabled,
        isFalse,
      );

      // 重新打开：再进一轮，ATRV 恢复发送。
      await tester.tap(voltageSwitch);
      await tester.pump();
      await rig.advanceRound(tester);
      await rig.deliverChunks(tester);
      await rig.deliverChunks(tester);
      await rig.deliverChunks(tester);
      expect(
        rig.mock.sentCommands.where((c) => c == 'ATRV'),
        hasLength(greaterThanOrEqualTo(2)),
      );

      await leavePageAndFlush(tester);
    });

    testWidgets('离开页面断开会话（dispose 链路到传输层，无泄漏）', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final rig = DiagnosticsRig();
      await seedDeveloperDiagnostics(database);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await openDiagnosticsPage(tester);
      await rig.advanceUntil(tester, find.text('37.6%'));
      expect(rig.mock.disconnectCalls, 0);

      // 离开页面：dispose → 会话 dispose → transport.disconnect。
      await leavePageAndFlush(tester);
      expect(rig.mock.disconnectCalls, 1);
      // 页面已退栈。
      expect(find.text('检测点'), findsNothing);
    });

    testWidgets('调试终端：暂停轮询后原始命令可发，验证脚本含私有 DID', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final rig = DiagnosticsRig();
      await seedDeveloperDiagnostics(database);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await openDiagnosticsPage(tester);
      await rig.advanceUntil(tester, find.text('37.6%'));
      // 收完第一轮余下两条，循环回到调度拍，暂停才有确定边界。
      await rig.deliverChunks(tester);
      await rig.deliverChunks(tester);

      await tester.ensureVisible(find.text('调试'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('展开'));
      await tester.pumpAndSettle();
      expect(find.text('调试模式（暂停自动轮询）'), findsOneWidget);

      final debugSwitch = find.descendant(
        of: find
            .ancestor(
              of: find.text('调试模式（暂停自动轮询）'),
              matching: find.byType(Row),
            )
            .first,
        matching: find.byType(Switch),
      );
      await tester.tap(debugSwitch);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, '原始命令'),
        'ATRV',
      );
      await tester.tap(find.text('发送'));
      await rig.deliverChunks(tester);
      await tester.pump();
      expect(find.textContaining('11.2V'), findsWidgets);

      final vendorCommands = obdVendorCommandGroups
          .expand((group) => group.commands)
          .toList();
      expect(vendorCommands, ['227029']);
      expect(obdVendorCommandGroups.first.header, 'DA60F1');

      await leavePageAndFlush(tester);
    });

    testWidgets('一键采集接线：点按钮走 run module，日志出真实头块与首条命令', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final rig = DiagnosticsRig();
      await seedDeveloperDiagnostics(database);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await openDiagnosticsPage(tester);
      await rig.advanceUntil(tester, find.text('37.6%'));
      // 收完第一轮余下两条，循环回到调度拍，暂停才有确定边界。
      await rig.deliverChunks(tester);
      await rig.deliverChunks(tester);

      await tester.ensureVisible(find.text('调试'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('展开'));
      await tester.pumpAndSettle();

      final debugSwitch = find.descendant(
        of: find
            .ancestor(
              of: find.text('调试模式（暂停自动轮询）'),
              matching: find.byType(Row),
            )
            .first,
        matching: find.byType(Switch),
      );
      await tester.tap(debugSwitch);
      await tester.pumpAndSettle();

      // 点检测：run module 同步吐出日志头与首条命令，随后挂在 ATI 请求
      // 上（静默脚本无字节）——这正是接线冒烟要锁的边。
      await tester.tap(find.text('一键检测'));
      await tester.pump();

      final log = tester.widget<SelectableText>(find.byType(SelectableText)).data;
      expect(log, contains('Lunio OBD 一键检测日志'));
      expect(log, contains('> ATI'));
      expect(rig.mock.sentCommands, contains('ATI'));

      await leavePageAndFlush(tester);
    });
  });

  group('表单增改删（票 06）', () {
    testWidgets('增：合法提交落库，列表即时可见（写点直失效传导）', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final rig = DiagnosticsRig();
      await seedDeveloperDiagnostics(database);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await openDiagnosticsPage(tester);

      // 列表尾"管理检测点" → 项目式管理 sheet → 新增表单。
      await tester.ensureVisible(find.text('管理检测点'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('管理检测点'));
      await tester.pumpAndSettle();
      expect(find.text('检测点管理'), findsOneWidget);
      await tester.tap(find.text('新增'));
      await tester.pumpAndSettle();
      expect(find.text('新增检测点'), findsOneWidget);
      expect(find.text('仅用于读取类指令（如标准 PID 查询）'), findsOneWidget);

      // 填名称与指令，保存（刷新间隔保持默认 30）。
      await tester.enterText(find.byType(TextField).at(0), '节气门');
      await tester.enterText(find.byType(TextField).at(1), '01 2f');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      // 管理卡片与页面读数行即时可见 + 库里第 4 行。
      expect(find.text('节气门'), findsWidgets);
      final probes = await testRepository(database)
          .diagnosticsRepository
          .listProbes(await appliedCarId(database));
      expect(probes, hasLength(4));
      expect(
        probes.last.command,
        '012F',
        reason: '保存前归一（大写 + 去空白），落库即发送文本',
      );
      expect(probes.last.refreshIntervalSeconds, 30);
      expect(find.text('检测点已保存'), findsOneWidget);

      await drainToastTimer(tester);
      // 关管理 sheet 再离开页面。
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      await leavePageAndFlush(tester);
    });

    testWidgets('改：点自定义行进编辑表单，保存后列表与库同步更新', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final rig = DiagnosticsRig();
      final carId = await seedAppliedCar(database);
      final repo = testRepository(database).diagnosticsRepository;
      await repo.saveProbe(
        DiagnosticsProbe(
          carId: carId,
          name: '节气门',
          command: '0111',
        ),
      );
      final seededId = (await repo.listProbes(carId))
          .firstWhere((p) => p.name == '节气门')
          .id!;
      await seedDeveloperDiagnostics(database);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await openDiagnosticsPage(tester);

      // 管理 sheet → 自定义卡片（最后一张）编辑 → 表单回填。
      await tester.ensureVisible(find.text('管理检测点'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('管理检测点'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑').last);
      await tester.pumpAndSettle();
      expect(find.text('编辑检测点'), findsOneWidget);
      expect(find.text('仅用于读取类指令（如标准 PID 查询）'), findsOneWidget);
      expect(
        tester.widget<TextField>(
          find.widgetWithText(TextField, '检测点名称'),
        ).controller!.text,
        '节气门',
      );
      expect(
        tester.widget<TextField>(
          find.widgetWithText(TextField, '指令原文'),
        ).controller!.text,
        '0111',
      );

      // 改名保存：列表与库同步更新。
      await tester.enterText(find.widgetWithText(TextField, '检测点名称'), '进气压力');
      await tester.enterText(
        find.widgetWithText(TextField, '刷新间隔'),
        '60',
      );
      await tester.tap(find.text('保存修改'));
      await tester.pumpAndSettle();
      // 管理卡片 + 页面读数行都更新。
      expect(find.text('进气压力'), findsWidgets);
      expect(find.text('节气门'), findsNothing);
      final updated = await repo.listProbes(carId);
      expect(updated.where((p) => p.name == '进气压力'), hasLength(1));
      expect(
        updated.firstWhere((p) => p.name == '进气压力').id,
        seededId,
        reason: '编辑保持原行 id',
      );
      expect(
        updated.firstWhere((p) => p.name == '进气压力').refreshIntervalSeconds,
        60,
      );
      expect(find.textContaining('每 60 秒刷新'), findsOneWidget);
      expect(find.text('检测点已保存'), findsOneWidget);
      await drainToastTimer(tester);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      await leavePageAndFlush(tester);
    });

    testWidgets('内置卡片可编辑、无删除按钮（管理 sheet）', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final rig = DiagnosticsRig();
      await seedDeveloperDiagnostics(database);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await openDiagnosticsPage(tester);

      await tester.ensureVisible(find.text('管理检测点'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('管理检测点'));
      await tester.pumpAndSettle();
      expect(find.text('检测点管理'), findsOneWidget);
      expect(find.text('内置'), findsNWidgets(3));
      expect(find.text('删除'), findsNothing, reason: '内置不可删');

      // 第三张内置卡片（电压）可进编辑表单。
      await tester.tap(find.text('编辑').at(2));
      await tester.pumpAndSettle();
      expect(find.text('编辑检测点'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, '检测点名称'),
            )
            .controller!
            .text,
        '电压',
      );
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      await leavePageAndFlush(tester);
    });

    testWidgets('删：确认后删除，列表与库同步移除', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final rig = DiagnosticsRig();
      final carId = await seedAppliedCar(database);
      final repo = testRepository(database).diagnosticsRepository;
      await repo.saveProbe(
        DiagnosticsProbe(
          carId: carId,
          name: '节气门',
          command: '0111',
        ),
      );
      await seedDeveloperDiagnostics(database);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await openDiagnosticsPage(tester);

      // 管理 sheet → 自定义卡片删除 → 确认框。
      await tester.ensureVisible(find.text('管理检测点'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('管理检测点'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.text('删除检测点'), findsOneWidget);
      expect(find.text('确定删除 节气门？'), findsOneWidget);

      // 确认删除：卡片/读数行消失、库行消失。
      await tester.tap(find.text('删除').last);
      await tester.pumpAndSettle();
      expect(find.text('节气门'), findsNothing);
      final probes = await repo.listProbes(carId);
      expect(probes, hasLength(3));
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      await leavePageAndFlush(tester);
    });

    testWidgets('校验失败行内错误文案，不弹窗', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final rig = DiagnosticsRig();
      await seedDeveloperDiagnostics(database);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await openDiagnosticsPage(tester);

      await tester.ensureVisible(find.text('管理检测点'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('管理检测点'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新增'));
      await tester.pumpAndSettle();
      // 名称与指令全空：保存 → 行内错误、sheet 留场、无弹窗。
      await tester.tap(find.text('保存'));
      await tester.pump();
      await tester.pump();
      expect(find.text('检测点名称不能为空'), findsOneWidget);
      expect(find.text('新增检测点'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);

      // 补上名称只缺指令：行内错误换文案、仍不弹窗。
      await tester.enterText(find.byType(TextField).at(0), '节气门');
      await tester.tap(find.text('保存'));
      await tester.pump();
      await tester.pump();
      expect(find.text('指令不能为空'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      await leavePageAndFlush(tester);
    });
  });

  /// 构造扫描列表条目（点选/行态断言用）。
  BleObdScanEntry scanEntry(String id, String name, int rssi) =>
      BleObdScanEntry(id: id, name: name, rssi: rssi);

  group('BLE 连接流程（票 07）', () {
    testWidgets('无记忆首用：自动开扫描 sheet，点选后连接成功并记忆', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final rig = DiagnosticsRig();
      await seedDeveloperDiagnostics(database, obdDeviceId: null);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await openDiagnosticsPage(tester);
      // 无记忆 → 自动开扫描 sheet：相位徽标"扫描中" + sheet 标题（状态
      // 条提示与 sheet 顶部提示同文案，共两处）。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('扫描中'), findsOneWidget);
      expect(find.text('选择适配器'), findsOneWidget);
      expect(
        find.text('正在扫描附近的蓝牙设备…'),
        findsNWidgets(2),
      );
      // 推入扫描结果：空名设备被扫描器过滤，列表只有有名字的设备
      //（2026-11-15 反转 story 5；过滤在扫描器数据源，sheet 只渲染）。
      rig.scanner.emit([
        scanEntry('dev-A', 'IOS-Vlink', -58),
        scanEntry('dev-B', '', -72),
        scanEntry('dev-C', '', -40),
      ]);
      await tester.pump();
      expect(find.text('IOS-Vlink'), findsOneWidget);
      expect(find.text('未命名设备'), findsNothing);
      // 点选 → 行态"连接中…"（story 6）。
      await tester.tap(find.text('IOS-Vlink'));
      await tester.pump();
      expect(find.text('连接中…'), findsOneWidget);
      // 建链成功：已连接 + 记忆写入 + sheet 关闭（story 4/5）；sheet 退
      // 出动画随 400ms 泵走完再断言关净。
      await rig.advanceUntil(tester, find.text('已连接'));
      // 记忆写入（真库异步）→ close 起在最后一拍泵的微任务尾巴，退出动
      // 画还要额外帧才收——pumpAndSettle 冲净（会话轮询走门闩无真实定时
      // 器，不拖 settle，票 06 sheet 断言同手法）。
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('选择适配器'), findsNothing);
      final bundle = testRepository(database);
      expect(await bundle.getPreferenceValue('lastObdDeviceId'), 'dev-A');
      expect(rig.lastDeviceId, 'dev-A');
      await leavePageAndFlush(tester);
    });

    testWidgets('扫描 sheet 无留白回归守卫：提示行→首卡/空态占位间距紧贴', (
      tester,
    ) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final rig = DiagnosticsRig();
      await seedDeveloperDiagnostics(database, obdDeviceId: null);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await openDiagnosticsPage(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // 空态：占位文案紧跟提示行（8dp 间隔 + 24dp 占位上边距）。
      final hintBottom =
          tester.getBottomLeft(find.text('正在扫描附近的蓝牙设备…').last).dy;
      final emptyTop =
          tester.getTopLeft(find.text('附近暂无蓝牙设备，请确认适配器已插车')).dy;
      expect(emptyTop - hintBottom, lessThanOrEqualTo(40));

      // 有结果：首卡紧跟提示行（8dp 间隔；守卫 ListView 默认安全区
      // padding 回归——修复前此处凭空多 ~74px）。
      rig.scanner.emit([scanEntry('dev-A', 'IOS-Vlink', -58)]);
      await tester.pump();
      final hintBottom2 =
          tester.getBottomLeft(find.text('正在扫描附近的蓝牙设备…').last).dy;
      final cardTop = tester
          .getTopLeft(
            find.ancestor(
              of: find.text('IOS-Vlink'),
              matching: find.byType(LunioCard),
            ),
          )
          .dy;
      expect(cardTop - hintBottom2, lessThanOrEqualTo(20));

      // 收尾：关 sheet、离页。
      await tester.tap(find.text('关闭'));
      await tester.pump(const Duration(milliseconds: 400));
      await leavePageAndFlush(tester);
    });

    testWidgets('扫描顺序稳定：信号抖动不换位，新设备插入有序（2026-11-15）', (
      tester,
    ) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final rig = DiagnosticsRig();
      await seedDeveloperDiagnostics(database, obdDeviceId: null);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await openDiagnosticsPage(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // 首拍按信号降序：B(-45) 在 A(-58) 上面。
      rig.scanner.emit([
        scanEntry('dev-A', 'IOS-Vlink', -58),
        scanEntry('dev-B', 'Android-Vlink', -45),
      ]);
      await tester.pump();
      final bY1 = tester.getTopLeft(find.text('Android-Vlink')).dy;
      final aY1 = tester.getTopLeft(find.text('IOS-Vlink')).dy;
      expect(bY1, lessThan(aY1));

      // 信号抖动：行序冻结不换位，数字照常刷新。
      rig.scanner.emit([
        scanEntry('dev-A', 'IOS-Vlink', -35),
        scanEntry('dev-B', 'Android-Vlink', -80),
      ]);
      await tester.pump();
      expect(tester.getTopLeft(find.text('Android-Vlink')).dy, bY1);
      expect(tester.getTopLeft(find.text('IOS-Vlink')).dy, aY1);
      expect(find.text('信号强度 -35'), findsOneWidget);
      expect(find.text('信号强度 -80'), findsOneWidget);

      // 新设备插入：最弱的追加末尾、最强的插到最前。
      rig.scanner.emit([
        scanEntry('dev-A', 'IOS-Vlink', -35),
        scanEntry('dev-B', 'Android-Vlink', -80),
        scanEntry('dev-C', 'OBD Adapter', -90),
      ]);
      await tester.pump();
      rig.scanner.emit([
        scanEntry('dev-A', 'IOS-Vlink', -35),
        scanEntry('dev-B', 'Android-Vlink', -80),
        scanEntry('dev-C', 'OBD Adapter', -90),
        scanEntry('dev-D', 'Fast Adapter', -20),
      ]);
      await tester.pump();
      final dY = tester.getTopLeft(find.text('Fast Adapter')).dy;
      final bY2 = tester.getTopLeft(find.text('Android-Vlink')).dy;
      final aY2 = tester.getTopLeft(find.text('IOS-Vlink')).dy;
      final cY = tester.getTopLeft(find.text('OBD Adapter')).dy;
      expect(dY, lessThan(bY2), reason: '最强的新设备插到最前');
      expect(cY, greaterThan(aY2), reason: '最弱的新设备追加末尾');

      await tester.tap(find.text('关闭'));
      await tester.pump(const Duration(milliseconds: 400));
      await leavePageAndFlush(tester);
    });

    testWidgets('已连接点「断开」：释放会话落未连接，记忆保留（2026-11-15）', (
      tester,
    ) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final rig = DiagnosticsRig();
      await seedDeveloperDiagnostics(database);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await openDiagnosticsPage(tester);
      await rig.advanceUntil(tester, find.text('已连接'));

      // 点「断开」：会话释放（mock disconnect 恰一次）+ 落「未连接」
      //（手动断开非异常，不落红色「已断开」）+「选择设备」再入口。
      await tester.tap(find.text('断开'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('已连接'), findsNothing);
      expect(find.text('未连接'), findsOneWidget);
      expect(find.text('选择设备'), findsOneWidget);
      expect(rig.mock.disconnectCalls, 1);

      // 设备记忆保留：重连语义不变（重进页面仍自动直连）。
      final bundle = testRepository(database);
      expect(await bundle.getPreferenceValue('lastObdDeviceId'), 'dev-1');

      await leavePageAndFlush(tester);
      // 离页收尾不再产生第二次 disconnect（会话已释放，teardown 幂等）。
      expect(rig.mock.disconnectCalls, 1);
    });

    testWidgets('取消后重选：旧 teardown 不取消新会话订阅', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final rig = DiagnosticsRig();
      // 会话 A 的断开挂门闩：关闭 sheet 取消 A 后，A 的 teardown 会
      // 停在传输层断开上；期间重开 sheet 并连接 B，旧 teardown 恢复时
      // 只准取消 A 的订阅。
      final aDisconnectGate = Completer<void>();
      var sessionCount = 0;
      MockObdTransport? bMock;
      Elm327Session factory(String deviceId) {
        sessionCount++;
        final MockObdTransport mock;
        if (sessionCount == 1) {
          mock = _SlowDisconnectMock(
            responses: rigStandardResponses(),
            delay: (d) => rig.chunkGate.gate(d),
            disconnectGate: aDisconnectGate,
          );
        } else {
          mock = MockObdTransport(
            responses: rigStandardResponses(),
            delay: (d) => rig.chunkGate.gate(d),
          );
        }
        if (sessionCount == 2) {
          bMock = mock;
        }
        return Elm327Session(
          transport: mock,
          now: () => rig.fixedNow,
          delay: (d) => rig.timeGate.gate(d),
          responseTimeout: const Duration(milliseconds: 300),
                  );
      }

      await seedDeveloperDiagnostics(database, obdDeviceId: null);
      await pumpApp(
        tester,
        database: database,
        extraOverrides: [
          obdSessionFactoryProvider.overrideWithValue(factory),
          obdScannerProvider.overrideWithValue(rig.scanner),
        ],
      );
      await openDiagnosticsPage(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // 连接 A 后取消（旧 teardown 卡在断开门闩）。
      rig.scanner.emit([scanEntry('dev-A', 'A 适配器', -50)]);
      await tester.pump();
      await tester.tap(find.text('A 适配器'));
      await tester.pump();
      expect(find.text('连接中'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('未连接'), findsOneWidget);
      // 重开扫描并连接 B。
      await tester.tap(find.text('选择设备'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      rig.scanner.emit([scanEntry('dev-B', 'B 适配器', -50)]);
      await tester.pump();
      await tester.tap(find.text('B 适配器'));
      await tester.pump();
      await rig.advanceUntil(tester, find.text('已连接'));
      expect(sessionCount, 2);
      // 放行 A 的断开：旧 teardown 恢复，B 的页面订阅必须仍然有效。
      aDisconnectGate.complete();
      await tester.pump();
      await tester.pump();
      bMock!.injectError(StateError('B 链路断开'));
      await tester.pump();
      await tester.pump();
      expect(find.text('已断开'), findsOneWidget);
      await leavePageAndFlush(tester);
    });

  });

  group('最后读数持久化（2026-11-15，ADR 0021 修订节）', () {
    testWidgets('重进页面显最后读数：跨天带日期，油量卡升数恢复', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final rig = DiagnosticsRig();
      // 门禁失败阻断实时链路：页面停在已断开、无实时读数，持久化读数
      // 成行/卡显示的唯一来源（隔离被测行为）。
      rig.scanner.gateError = const BleObdTransportException(
        BleObdLinkErrorKind.permissionDenied,
      );
      await seedAppliedCar(database, tankCapacity: 50);
      await seedDeveloperDiagnostics(database, obdDeviceId: null);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await gotoTab(tester, '我的');
      await tester.pumpAndSettle();

      // 开页前预写最后读数（昨天 08:00:00）：油量 37.6% / 水温 95℃。
      final diagnostics = testRepository(database).diagnosticsRepository;
      final fuelId = (await diagnostics.listProbes(await appliedCarId(database)))
          .firstWhere((p) => p.name == '油量')
          .id!;
      final coolantId = (await diagnostics.listProbes(await appliedCarId(database)))
          .firstWhere((p) => p.name == '水温')
          .id!;
      await diagnostics.saveProbeReading(
        fuelId,
        value: '37.6%',
        percent: 37.6,
        at: DateTime(2026, 11, 14, 8, 0, 0),
      );
      await diagnostics.saveProbeReading(
        coolantId,
        value: '95℃',
        at: DateTime(2026, 11, 14, 8, 0, 0),
      );

      await openDiagnosticsPage(tester);

      // 行：跨天时间带日期（M/d HH:mm:ss），两行同刻 → 两处。
      expect(find.text('37.6%'), findsNWidgets(2)); // 行 + 油量卡
      expect(find.textContaining('08:00:00'), findsNWidgets(2));
      // 油量卡升数：37.6% × 50L = 18.8 升。
      expect(find.text('≈ 18.8 升'), findsOneWidget);
      expect(find.text('95℃'), findsNWidgets(2)); // 行 + 水温卡
      await leavePageAndFlush(tester);
    });

    testWidgets('轮询读数落库：有效值写、无数据不写不覆盖', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final rig = DiagnosticsRig(
        responses: {
          ...rigStandardResponses(),
          // 油量本轮 NO DATA：行显灰字无数据，持久化层不写不覆盖。
          '012F': rigResp('NO DATA\r\r>'),
        },
      );
      await seedDeveloperDiagnostics(database);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await openDiagnosticsPage(tester);

      // 连接成功进轮询：油量行显「无数据」（实时显示不受持久化口径影
      // 响），水温行显有效值。
      await rig.advanceUntil(tester, find.text('无数据'));
      await rig.advanceUntil(tester, find.text('95℃'));

      // 库内口径：油量不写库（保持 null）、水温有效值已写。
      final diagnostics = testRepository(database).diagnosticsRepository;
      final probes = await diagnostics.listProbes(await appliedCarId(database));
      final fuel = probes.firstWhere((p) => p.name == '油量');
      final coolant = probes.firstWhere((p) => p.name == '水温');
      expect(fuel.lastValue, isNull);
      expect(coolant.lastValue, '95℃');
      await leavePageAndFlush(tester);
    });
  });

  group('ECU 里程同步（ADR 0026）', () {
    /// 播种自定义里程表探针（默认夹具只种内置三条）。
    Future<void> seedOdometerProbe(AppDatabase database) async {
      await testRepository(database)
          .diagnosticsRepository
          .saveProbe(
            DiagnosticsProbe(
              carId: await appliedCarId(database),
              name: '里程表',
              command: '01A6',
              parseType: DiagnosticsParseType.odometer,
            ),
          );
    }

    testWidgets('确认式：ECU 里程 > 车辆里程显行内入口，确认后写库', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final rig = DiagnosticsRig();
      await seedAppliedCar(database, mileageKm: 10000);
      await seedDeveloperDiagnostics(database);
      await seedOdometerProbe(database);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await openDiagnosticsPage(tester);
      await rig.advanceUntil(tester, find.text('66,068 km'));

      // 确认式入口显形（10,000 < 66,068；开关默认关 = 确认档）。
      expect(find.text('更新里程'), findsOneWidget);

      // 确认框两值对照 → 确认 → 写库 + 入口消失。
      await tester.tap(find.text('更新里程'));
      await tester.pump();
      expect(find.text('更新车辆里程'), findsOneWidget);
      expect(find.textContaining('大于当前车辆里程'), findsOneWidget);
      await tester.tap(find.text('更新').last);
      await tester.pump();
      await tester.pump();

      final cars = await database.select(database.cars).get();
      expect(cars.single.currentMileageKm, 66068);
      expect(find.text('更新里程'), findsNothing);
      await leavePageAndFlush(tester);
    });

    testWidgets('守卫：ECU 里程不大于车辆里程不显入口', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final rig = DiagnosticsRig();
      await seedAppliedCar(database, mileageKm: 70000);
      await seedDeveloperDiagnostics(database);
      await seedOdometerProbe(database);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await openDiagnosticsPage(tester);
      await rig.advanceUntil(tester, find.text('66,068 km'));

      expect(find.text('更新里程'), findsNothing);
      await leavePageAndFlush(tester);
    });

    testWidgets('静默自动写：开关开时读到更大里程直接落库、不弹窗', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final rig = DiagnosticsRig();
      await seedAppliedCar(database, mileageKm: 10000);
      await seedDeveloperDiagnostics(database);
      await seedOdometerProbe(database);
      await testRepository(database).setPreferenceValue(
        LunioPreferences.obdOdometerAutoSyncKey,
        'true',
      );
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await openDiagnosticsPage(tester);
      await rig.advanceUntil(tester, find.text('66,068 km'));

      // 静默档：不显确认入口；静默写完成后车辆里程已落库。
      await tester.pump();
      await tester.pump();
      expect(find.text('更新里程'), findsNothing);
      final cars = await database.select(database.cars).get();
      expect(cars.single.currentMileageKm, 66068);
      await leavePageAndFlush(tester);
    });

    testWidgets('管理 sheet 开关行：默认关，打开后写偏好并重算', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final rig = DiagnosticsRig();
      await seedDeveloperDiagnostics(database);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await openDiagnosticsPage(tester);
      await tester.ensureVisible(find.text('管理检测点'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('管理检测点'));
      await tester.pumpAndSettle();
      expect(find.text('ECU 里程自动同步'), findsOneWidget);
      expect(
        await testRepository(database).getPreferenceValue(
          LunioPreferences.obdOdometerAutoSyncKey,
        ),
        isNull,
      );

      // 打开开关 → 偏好写入（纪元 bump 后 provider 重算）。
      final syncSwitch = find.descendant(
        of: find
            .ancestor(
              of: find.text('ECU 里程自动同步'),
              matching: find.byType(Row),
            )
            .first,
        matching: find.byType(Switch),
      );
      await tester.tap(syncSwitch);
      await tester.pumpAndSettle();
      expect(
        await testRepository(database).getPreferenceValue(
          LunioPreferences.obdOdometerAutoSyncKey,
        ),
        'true',
      );

      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      await leavePageAndFlush(tester);
    });
  });
}
