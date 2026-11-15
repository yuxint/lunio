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
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lunio/data/database/app_database.dart';
import 'package:lunio/domain/entities/diagnostics_probe.dart';
import 'package:lunio/features/shell/diagnostics/elm327_session.dart';
import 'package:lunio/core/widgets/lunio_components.dart';

import '../helpers/builders.dart';
import '../helpers/diagnostics_fixture.dart';
import '../helpers/widget_app.dart';

/// 播种应用车辆（可选油箱容积）并设为当前车：必须在 pumpApp 之前。
Future<void> seedAppliedCar(AppDatabase database, {double? tankCapacity}) async {
  final bundle = testRepository(database);
  final carId = await bundle.insertCarForTest(
    defaultCar(tankCapacityLiters: tankCapacity),
  );
  await bundle.setAppliedCarId(carId);
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

/// 种子开发者模式与诊断开关（必须在 pumpApp 之前）。
Future<void> seedDeveloperDiagnostics(AppDatabase database) async {
  final bundle = testRepository(database);
  await bundle.setPreferenceValue('developerModeEnabled', 'true');
  await bundle.setPreferenceValue('diagnosticsEnabled', 'true');
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
      expect(find.text('90℃'), findsNWidgets(2));
      expect(find.text('11.2V'), findsOneWidget);
      expect(find.text('已连接'), findsOneWidget);
      expect(find.text('未更新'), findsNothing);
      expect(find.text('14:30:00'), findsNWidgets(3));

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
      // 0105 不在应答表 = Mock 默认静默脚本（不应答）→ 单条超时无数据。
      final rig = DiagnosticsRig(
        responses: rigStandardResponses()..remove('0105'),
      );
      await seedDeveloperDiagnostics(database);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await openDiagnosticsPage(tester);

      // 油量先到，水温在途（不应答）。
      await rig.advanceUntil(tester, find.text('37.6%'));

      // 一拍时钟：0105 超时闩放行 → 行级无数据；串行轮询继续到电压。
      await rig.advanceRound(tester);
      await rig.deliverChunks(tester);

      // 水温行与水温卡都转无数据灰态（story 15）。
      expect(find.text('无数据'), findsNWidgets(2));
      // 其他行不连坐：油量/电压值仍在，状态条仍是已连接。
      expect(find.text('37.6%'), findsNWidgets(2));
      expect(find.text('11.2V'), findsOneWidget);
      expect(find.text('已连接'), findsOneWidget);
      // 无数据也是一次更新：行尾时间戳照常打点（story 14）。
      expect(find.text('14:30:00'), findsNWidgets(3));

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
                .listProbes())
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
  });

  group('表单增改删（票 06）', () {
    testWidgets('增：合法提交落库，列表即时可见（写点直失效传导）', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final rig = DiagnosticsRig();
      await seedDeveloperDiagnostics(database);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await openDiagnosticsPage(tester);

      // 列表尾添加行 → 新增表单（运行时统一出口：标题 + 副标题可见）。
      await tester.tap(find.text('添加检测点'));
      await tester.pumpAndSettle();
      expect(find.text('新增检测点'), findsOneWidget);
      expect(find.text('仅用于读取类指令（如标准 PID 查询）'), findsOneWidget);

      // 填名称与指令，保存。
      await tester.enterText(find.byType(TextField).at(0), '节气门');
      await tester.enterText(find.byType(TextField).at(1), '01 2f');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      // 列表即时可见 + 库里第 4 行（3 内置 + 1 自定义）。
      expect(find.text('节气门'), findsOneWidget);
      final probes = await testRepository(database)
          .diagnosticsRepository
          .listProbes();
      expect(probes, hasLength(4));
      expect(
        probes.last.command,
        '012F',
        reason: '保存前归一（大写 + 去空白），落库即发送文本',
      );
      expect(find.text('检测点已保存'), findsOneWidget);

      await drainToastTimer(tester);
      await leavePageAndFlush(tester);
    });

    testWidgets('改：点自定义行进编辑表单，保存后列表与库同步更新', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final repo = testRepository(database).diagnosticsRepository;
      final rig = DiagnosticsRig();
      await repo.saveProbe(
        DiagnosticsProbe(name: '节气门', command: '0111'),
      );
      final seededId = (await repo.listProbes())
          .firstWhere((p) => p.name == '节气门')
          .id!;
      await seedDeveloperDiagnostics(database);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await openDiagnosticsPage(tester);

      // 点自定义行 → 编辑表单（标题 + 三字段回填）。
      await tester.tap(find.text('节气门'));
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
      await tester.tap(find.text('保存修改'));
      await tester.pumpAndSettle();
      expect(find.text('进气压力'), findsOneWidget);
      expect(find.text('节气门'), findsNothing);
      final updated = await repo.listProbes();
      expect(updated.where((p) => p.name == '进气压力'), hasLength(1));
      expect(
        updated.firstWhere((p) => p.name == '进气压力').id,
        seededId,
        reason: '编辑保持原行 id',
      );
      expect(find.text('检测点已保存'), findsOneWidget);
      await drainToastTimer(tester);
      await leavePageAndFlush(tester);
    });

    testWidgets('内置行点按无编辑入口（story 23 只读守卫的 UI 呈现）', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final rig = DiagnosticsRig();
      await seedDeveloperDiagnostics(database);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await openDiagnosticsPage(tester);

      // 点内置"电压"行（文本唯一，油量行文本与核心值卡重名）→ 不出表单。
      await tester.tap(find.text('电压'));
      await tester.pumpAndSettle();
      expect(find.text('编辑检测点'), findsNothing);
      expect(find.text('新增检测点'), findsNothing);

      await leavePageAndFlush(tester);
    });

    testWidgets('删：确认后删除，列表与库同步移除', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final repo = testRepository(database).diagnosticsRepository;
      final rig = DiagnosticsRig();
      await repo.saveProbe(
        DiagnosticsProbe(name: '节气门', command: '0111'),
      );
      await seedDeveloperDiagnostics(database);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await openDiagnosticsPage(tester);

      // 编辑表单 → 删除 → 确认框。
      await tester.tap(find.text('节气门'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.text('删除检测点'), findsOneWidget);
      expect(find.text('确定删除 节气门？'), findsOneWidget);

      // 确认删除：行消失、库行消失、成功 toast。
      await tester.tap(find.text('删除').last);
      await tester.pumpAndSettle();
      expect(find.text('节气门'), findsNothing);
      final probes = await repo.listProbes();
      expect(probes, hasLength(3));
      expect(find.text('检测点已删除'), findsOneWidget);
      await drainToastTimer(tester);
      await leavePageAndFlush(tester);
    });

    testWidgets('校验失败行内错误文案，不弹窗', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final rig = DiagnosticsRig();
      await seedDeveloperDiagnostics(database);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await openDiagnosticsPage(tester);

      await tester.tap(find.text('添加检测点'));
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
      await leavePageAndFlush(tester);
    });
  });
}
