// diagnostics 域 widget 测试（票 05 三区状态机 + 票 06 表单增改删，共享
// 夹具 test/helpers/widget_app.dart 与 diagnostics_fixture.dart）。
// 2026-11-17 ADR 0029 卡化重构适配版：
//  - 检测点行列表撤销，全员信息卡：内置四张（油量 | 水温 / 电压 |
//    燃油修正），启用的自定义探针追加通用卡——值渲染断言按卡计数
//    （38% 等每值一处、时间戳 = 有读数的卡数）。
//  - 显示回退语义：实时有值优先；实时无数据不遮蔽持久化最后值（显旧
//    值+旧时间戳）；两者皆无 = 「—」灰态 + 「未更新」时间戳（页面不再
//    出现「无数据」文案与行级「超时」reason）。
//  - 油量升数估算（estimateFuel）删除：油量卡只有百分比大字，无升数行。
//  - 启停与管理入口迁出诊断页：唯一入口 = 我的页车辆卡「检测点」按钮
//    （openProbeManagementSheet）；启停下一轮生效用例改走 sheet。
//  - 连接序列含 ECU 握手 0100；默认刷新间隔 30→10 秒（advanceRound
//    11 拍）。
// 2026-11-18 ADR 0029 修订节适配版：
//  - 燃油修正卡撤下（LTFT/STFT 探针保留、不再上卡），位置换 CVT 油温
//    卡（222301 私有 DID 多行帧，标准帧解析 69℃ 落黄档）——内置四张
//    固定卡 = 油量 | 水温 / 电压 | CVT 油温。
//  - 内置探针五条→七条（CVT 油温/里程表升内置）⇒ 默认满一轮 7 条；
//    里程表内置但不上卡（页面无里程卡，读数仅供 ECU 里程同步）。
//  - ECU 里程同步收拢为 App 级静默一档（ADR 0026 修订节）：回调常驻
//    obd_runtime 装配，开关开才写、守卫「只增不减」在动作层；确认式
//    「更新里程」入口随页面接缝取消（相关两用例删除）。
//
// 其余语义保持：三区状态机全状态可达（未连接→连接中→已连接→已断开+
// 错误+重连）、单条超时不连坐、离开页面只摘作用域不断开 App 级连接
// （ADR 0027，无 pending timer 残留）；表单增改删（添加进新增/自定义
// 进编辑/内置守卫/删确认/行内校验）；BLE 连接流程；最后读数持久化；
// ECU 里程静默同步（ADR 0026）。
//
// 时序全走门闩（夹具文件头的配方）：advanceUntil 逐拍放行字节至值出
// 现；advanceRound 一拍时钟进下一轮。零真实定时器——用例收尾只泵帧
// （pop 起始帧/移除帧），无 pending timer 排空负担。
//
// 导航一律走真实入口（诊断页 = 我的页开发者区块「进入诊断页」行，
// context.push 真入栈；管理 sheet = 我的页车辆卡「检测点」按钮）。
//
// 播种必须在 pumpApp 之前：装配后直写库不会触发 provider 失效（例外：
// 最后读数持久化用例在装配后直写并手动逐出 family，见该用例注释）。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lunio/data/database/app_database.dart';
import 'package:lunio/data/preferences/app_preferences.dart';
import 'package:lunio/domain/entities/diagnostics_probe.dart';
import 'package:lunio/features/shell/diagnostics/ble_obd_errors.dart';
import 'package:lunio/features/shell/diagnostics/ble_scan_entries.dart';
import 'package:lunio/features/shell/diagnostics/elm327_session.dart';
import 'package:lunio/features/shell/diagnostics/mock_obd_transport.dart';
import 'package:lunio/features/shell/diagnostics/obd_runtime.dart';
import 'package:lunio/features/shell/diagnostics/obd_verification_commands.dart';
import 'package:lunio/features/shell/shared/shell_shared.dart';
import 'package:lunio/app/providers.dart';
import 'package:lunio/core/theme/lunio_tokens.dart';
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
/// 完成帧→路由移除帧（页面离树，State.dispose 只摘接缝与作用域，
/// App 级连接保持，ADR 0027）；会话定时全是门闩 Completer（非定时
/// 器），无需冲刷。
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
  // 页面已在栈顶（下层我的页 offstage，finder 默认跳过）。2026-11-16
  // 起我的页不再有「车辆诊断」开关行（迁设置页），标题只有页面一处。
  expect(find.text('车辆诊断'), findsOneWidget);
}

/// 打开检测点管理 sheet（2026-11-17 ADR 0029 起的真实入口）：我的页
/// 车辆卡「检测点」按钮，锚定当前车进 sheet。诊断页已无入口行。
Future<void> openProbeManagementSheet(WidgetTester tester) async {
  await gotoTab(tester, '我的');
  await tester.ensureVisible(find.text('检测点'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('检测点'));
  await tester.pumpAndSettle();
  expect(find.text('检测点管理'), findsOneWidget);
}

/// 管理 sheet 内的 finder 作用域：下层「我的」页车辆卡同样有「编辑/
/// 删除」按钮，sheet 内定位一律收进 PrototypeSheetFrame 子树，避免
/// 跨层串扰（ADR 0029 检测点入口迁车辆卡后新增的约束）。
Finder inProbeSheet(Finder finder) => find.descendant(
      of: find.byType(PrototypeSheetFrame),
      matching: finder,
    );

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

      // 逐拍放行字节：连接完成 + 第一轮轮询，四张内置卡值 + 时间戳
      // （012F/0167/ATRV/0106/0107/222301/01A6 串行，收满一轮共 7 条
      // 应答；01A6 读数不上卡——里程表内置探针无卡，仅供 ECU 里程同步）。
      await rig.advanceUntil(tester, find.text('38%'));
      for (var i = 0; i < 6; i++) {
        await rig.deliverChunks(tester);
      }
      // 行列表撤销（ADR 0029）：每个值只在信息卡一处。
      expect(find.text('38%'), findsOneWidget);
      expect(find.text('95℃'), findsOneWidget);
      expect(find.text('11.2V'), findsOneWidget);
      // CVT 油温卡（燃油修正卡已撤下）：222301 多行帧 → 69℃（黄档）。
      expect(find.text('CVT 油温'), findsOneWidget);
      expect(find.text('69℃'), findsOneWidget);
      // 燃油修正两探针仍在轮询清单里，但不再有卡可上。
      expect(find.text('+0.0%'), findsNothing);
      expect(find.text('短期 -1.6%'), findsNothing);
      // 里程表读数（66,068 km）不上卡：内置探针不在四张固定卡清单。
      expect(find.text('66,068 km'), findsNothing);
      expect(find.text('已连接'), findsOneWidget);
      expect(find.text('未更新'), findsNothing);
      // 四张内置卡各一枚时间戳（时间只挂卡上）。
      expect(find.textContaining('14:30:00'), findsNWidgets(4));

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

      // 重连：新会话 AT 序列重发（sentCommands 第二组 ATZ），回到已连
      // 接；controller 读数表不随会话重建清空（最后读数合并），油量卡
      // 旧值保留显示。
      await tester.tap(find.text('重连'));
      await tester.pump();
      await rig.advanceUntil(tester, find.text('已连接'));
      expect(
        rig.mock.sentCommands.where((command) => command == 'ATZ'),
        hasLength(2),
      );
      await rig.advanceUntil(tester, find.text('38%'));
      expect(find.text('38%'), findsOneWidget);

      await leavePageAndFlush(tester);
    });

    testWidgets('油量卡只显百分比大字，无升数估算行（ADR 0029 删 estimateFuel）', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      await seedAppliedCar(database, tankCapacity: 55, totalTankCapacity: 60);
      final rig = DiagnosticsRig();
      await seedDeveloperDiagnostics(database);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await openDiagnosticsPage(tester);
      await rig.advanceUntil(tester, find.text('38%'));

      // 油量卡只有百分比大字：有容积也不算升数（可用/估算总油量行已
      // 随 estimateFuel 删除），页面任何位置不出现「升」字。
      expect(find.text('38%'), findsOneWidget);
      expect(find.textContaining('升'), findsNothing);

      await leavePageAndFlush(tester);
    });

    testWidgets('冷车水温染红档（<50 冷启动窗口，2026-11-18 五段拍板守卫）', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      // 0167 回冷车帧：41 67 03 3C 00 → (0x3C−40)=20℃ <50 → danger。
      final rig = DiagnosticsRig(
        responses: rigStandardResponses()
          ..['0167'] = rigResp('41 67 03 3C 00 \r\r>'),
      );
      await seedDeveloperDiagnostics(database);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await openDiagnosticsPage(tester);
      await rig.advanceUntil(tester, find.text('20℃'));

      // 大字颜色 = tokens.danger（红档：冷启动磨损窗口），不是 ink。
      final context = tester.element(find.text('20℃'));
      final tokens = Theme.of(context).extension<LunioTokens>()!;
      final color = tester.widget<Text>(find.text('20℃')).style?.color;
      expect(color, tokens.danger);
      expect(color, isNot(tokens.ink));

      await leavePageAndFlush(tester);
    });

    testWidgets('卡级无数据灰态：单条超时不连坐，其他卡照常更新', (tester) async {
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
      await rig.advanceUntil(tester, find.text('38%'));

      // 放行 0167 的 300ms 响应超时 → 无数据；串行轮询继续到电压。
      await rig.completeProbeTimeout(tester);
      await rig.deliverChunks(tester);

      // 水温卡灰态「—」+「未更新」（此探针从未有过有效值；实时无数据
      // 不遮蔽持久化值——本用例无持久化值，落到灰态；ADR 0029 卡化后
      // 不再有行级「超时」reason 文案，「无数据」文案也不再出现在卡上）。
      final coolantCard = find.ancestor(
        of: find.text('水温'),
        matching: find.byType(LunioCard),
      );
      expect(
        find.descendant(of: coolantCard, matching: find.text('—')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: coolantCard, matching: find.text('未更新')),
        findsOneWidget,
      );
      expect(find.text('超时'), findsNothing);
      expect(find.text('无数据'), findsNothing);
      // 其他卡不连坐：油量/电压值仍在，状态条仍是已连接。
      expect(find.text('38%'), findsOneWidget);
      expect(find.text('11.2V'), findsOneWidget);
      expect(find.text('已连接'), findsOneWidget);

      await leavePageAndFlush(tester);
    });

    testWidgets('离开页面不断开连接（App 级连接保持，ADR 0027）', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final rig = DiagnosticsRig();
      await seedDeveloperDiagnostics(database);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await openDiagnosticsPage(tester);
      await rig.advanceUntil(tester, find.text('38%'));
      expect(rig.mock.disconnectCalls, 0);

      // 离开页面：只摘 UI 接缝与诊断作用域（轮询清单换回提醒页核心两
      // 条），App 级连接保持——重连成本高，跨页共享是 ADR 0027 的目的。
      await leavePageAndFlush(tester);
      expect(rig.mock.disconnectCalls, 0);
      // 页面已退栈（诊断页标题不在树上；下层我的页的「检测点」按钮
      // 与页面无关，不再拿它当退栈标记——ADR 0029 后它是常驻入口）。
      expect(find.text('车辆诊断'), findsNothing);
    });
    testWidgets('调试终端：暂停轮询后原始命令可发，验证脚本含私有 DID', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final rig = DiagnosticsRig();
      await seedDeveloperDiagnostics(database);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await openDiagnosticsPage(tester);
      await rig.advanceUntil(tester, find.text('38%'));
      // 收完第一轮余下六条（水温/电压/短期/长期/CVT 油温/里程表），循环
      // 回到轮间睡眠拍——无在途请求时暂停才有确定边界（有在途请求时
      // pausePolling 会等它收尾，而静默脚本的在途请求只能靠 300ms 超时
      // 闩，门闩不放行就挂住 pumpAndSettle）。
      for (var i = 0; i < 6; i++) {
        await rig.deliverChunks(tester);
      }

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
      // 原始命令真的发出去了：第一轮轮询的 ATRV 之外，又多一次手动发送
      // （卡上 11.2V 是第一轮的值，不能证明手发成功，发送计数才算数）。
      expect(
        rig.mock.sentCommands.where((command) => command == 'ATRV'),
        hasLength(greaterThanOrEqualTo(2)),
      );
      expect(find.textContaining('11.2V'), findsWidgets);

      final vendorCommands = obdVendorCommandGroups
          .expand((group) => group.commands)
          .toList();
      // 2026-11-18 三组候选段（调研报告第六节 + 机油温度备选两条拍板）。
      expect(vendorCommands, [
        '227029',
        '22702A',
        '227060',
        '227028',
        '227022',
        '222301',
        '222666',
        '22261A',
        '22262A',
      ]);
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
      await rig.advanceUntil(tester, find.text('38%'));
      // 收完第一轮余下六条，循环回到轮间睡眠拍（暂停边界理由见上一条）。
      for (var i = 0; i < 6; i++) {
        await rig.deliverChunks(tester);
      }

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

      // 点检测：run module 同步吐出日志头与首条命令（`> ATI` 行在 send
      // 前落日志），随后挂在 ATI 请求上（静默脚本无字节）——这正是接
      // 线冒烟要锁的边。
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
    testWidgets('增：合法提交落库，管理卡即时可见（写点直失效传导）', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final rig = DiagnosticsRig();
      await seedDeveloperDiagnostics(database);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);

      // 入口已迁出诊断页（ADR 0029）：我的页车辆卡「检测点」按钮。
      await openProbeManagementSheet(tester);
      await tester.tap(inProbeSheet(find.text('新增')));
      await tester.pumpAndSettle();
      expect(find.text('新增检测点'), findsOneWidget);
      expect(find.text('仅用于读取类指令（如标准 PID 查询）'), findsOneWidget);

      // 填名称与指令，保存（刷新间隔保持默认 10，2026-11-17 拍板 30→10）。
      await tester.enterText(find.byType(TextField).at(0), '节气门');
      await tester.enterText(find.byType(TextField).at(1), '01 2f');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      // 管理卡即时可见 + 库里第 8 行（内置七条 + 自定义一条）。
      expect(inProbeSheet(find.text('节气门')), findsOneWidget);
      final probes = await testRepository(database)
          .diagnosticsRepository
          .listProbes(await appliedCarId(database));
      expect(probes, hasLength(8));
      expect(
        probes.last.command,
        '012F',
        reason: '保存前归一（大写 + 去空白），落库即发送文本',
      );
      expect(probes.last.refreshIntervalSeconds, 10);
      expect(find.text('检测点已保存'), findsOneWidget);

      await drainToastTimer(tester);
      // 关管理 sheet（barrierDismissible 默认 true，点遮罩可关）。
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
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

      // 管理 sheet → 自定义卡片（最后一张）编辑 → 表单回填。
      await openProbeManagementSheet(tester);
      await tester.ensureVisible(inProbeSheet(find.text('编辑')).last);
      await tester.pumpAndSettle();
      await tester.tap(inProbeSheet(find.text('编辑')).last);
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
      // 管理卡更新，旧名消失。
      expect(inProbeSheet(find.text('进气压力')), findsOneWidget);
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
      expect(inProbeSheet(find.textContaining('每 60 秒刷新')), findsOneWidget);
      expect(find.text('检测点已保存'), findsOneWidget);
      await drainToastTimer(tester);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
    });

    testWidgets('内置卡片可编辑、无删除按钮（管理 sheet，内置七条）', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final rig = DiagnosticsRig();
      await seedDeveloperDiagnostics(database);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);

      await openProbeManagementSheet(tester);
      // 内置七条（油量/水温/电压/短期/长期/CVT 油温/里程表，ADR 0029
      // 转正 + 2026-11-18 修订节升内置）。
      expect(inProbeSheet(find.text('内置')), findsNWidgets(7));
      expect(inProbeSheet(find.text('删除')), findsNothing, reason: '内置不可删');

      // 第三张内置卡片（电压）可进编辑表单。
      await tester.ensureVisible(inProbeSheet(find.text('编辑')).at(2));
      await tester.pumpAndSettle();
      await tester.tap(inProbeSheet(find.text('编辑')).at(2));
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
    });

    testWidgets('删：确认后删除，管理卡与库同步移除', (tester) async {
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

      // 管理 sheet → 自定义卡片删除 → 确认框。删除按钮收在 sheet 作用
      // 域里点（下层我的页车辆卡也有「删除」，裸 finder 会点错层）。
      await openProbeManagementSheet(tester);
      await tester.ensureVisible(inProbeSheet(find.text('删除')));
      await tester.pumpAndSettle();
      await tester.tap(inProbeSheet(find.text('删除')));
      await tester.pumpAndSettle();
      expect(find.text('删除检测点'), findsOneWidget);
      expect(find.text('确定删除 节气门？'), findsOneWidget);

      // 确认删除：确认框的「删除」在顶层路由（finder 顺序最后），卡片
      // 消失、库行消失（剩内置七条）。
      await tester.tap(find.text('删除').last);
      await tester.pumpAndSettle();
      expect(find.text('节气门'), findsNothing);
      final probes = await repo.listProbes(carId);
      expect(probes, hasLength(7));
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
    });

    testWidgets('校验失败行内错误文案，不弹窗', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final rig = DiagnosticsRig();
      await seedDeveloperDiagnostics(database);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);

      await openProbeManagementSheet(tester);
      await tester.tap(inProbeSheet(find.text('新增')));
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
    });

    testWidgets('sheet 内启停下一轮生效：禁用电压后不再发 ATRV，重开恢复', (
      tester,
    ) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final rig = DiagnosticsRig();
      await seedDeveloperDiagnostics(database);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await openDiagnosticsPage(tester);
      await rig.advanceUntil(tester, find.text('38%'));
      // 收完第一轮余下六条，回到轮间睡眠拍（advanceRound 的前提）。
      for (var i = 0; i < 6; i++) {
        await rig.deliverChunks(tester);
      }

      // 第一轮已发全部七条（内置序：油量/水温/电压/短期/长期/CVT 油温/
      // 里程表）。
      expect(rig.mock.sentCommands.where((c) => c == 'ATRV'), hasLength(1));

      // 页面已无启停开关（ADR 0029），唯一入口在管理 sheet：离页（作
      // 用域换防、连接保持）→ 我的页车辆卡「检测点」开 sheet。
      await leavePageAndFlush(tester);
      await openProbeManagementSheet(tester);

      // 关电压卡启停按钮（内置序第 3 张，「已启用」）：动作层写库 →
      // 逐出 provider → 卡片按钮即时转「已禁用」；下一轮快照读
      // provider 当前值，不再发 ATRV。
      final voltageToggle = inProbeSheet(find.text('已启用')).at(2);
      await tester.ensureVisible(voltageToggle);
      await tester.pumpAndSettle();
      await tester.tap(voltageToggle);
      await tester.pumpAndSettle();
      expect(find.text('已禁用'), findsOneWidget);
      expect(
        (await testRepository(database)
                .diagnosticsRepository
                .listProbes(await appliedCarId(database)))
            .firstWhere((probe) => probe.command == 'ATRV')
            .enabled,
        isFalse,
      );
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      // 重进诊断页：App 级连接复用（connected 守卫不重连），advanceRound
      // 放行轮询拍进下一轮——快照里没有电压，ATRV 不再发（余下六条：
      // 油量/水温/短期/长期/CVT 油温/里程表）。
      await openDiagnosticsPage(tester);
      await rig.advanceRound(tester);
      for (var i = 0; i < 6; i++) {
        await rig.deliverChunks(tester);
      }
      expect(
        rig.mock.sentCommands.where((c) => c == 'ATRV'),
        hasLength(1),
      );
      expect(
        rig.mock.sentCommands.where((c) => c == '012F'),
        hasLength(greaterThanOrEqualTo(2)),
      );

      // 重新打开 sheet 启停回来：下一轮 ATRV 恢复发送。
      await leavePageAndFlush(tester);
      await openProbeManagementSheet(tester);
      await tester.ensureVisible(find.text('已禁用'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('已禁用'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      await openDiagnosticsPage(tester);
      await rig.advanceRound(tester);
      for (var i = 0; i < 7; i++) {
        await rig.deliverChunks(tester);
      }
      expect(
        rig.mock.sentCommands.where((c) => c == 'ATRV'),
        hasLength(greaterThanOrEqualTo(2)),
      );

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
      // 停在传输层断开门闩上；期间重开 sheet 并连接 B，旧 teardown 恢复时
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
    testWidgets('重进页面显最后读数：跨天带日期，无实时值的卡灰态「未更新」', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final rig = DiagnosticsRig();
      // 门禁失败阻断实时链路：页面停在已断开、无实时读数，持久化读数
      // 成卡显示的唯一来源（隔离被测行为）。
      rig.scanner.gateError = const BleObdTransportException(
        BleObdLinkErrorKind.permissionDenied,
      );
      await seedAppliedCar(database, tankCapacity: 50);
      await seedDeveloperDiagnostics(database, obdDeviceId: null);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await gotoTab(tester, '我的');
      await tester.pumpAndSettle();

      // 开页前预写最后读数（昨天 08:00:00）：油量 38% / 水温 95℃。
      final diagnostics = testRepository(database).diagnosticsRepository;
      final fuelId = (await diagnostics.listProbes(await appliedCarId(database)))
          .firstWhere((p) => p.name == '油量')
          .id!;
      final coolantId = (await diagnostics.listProbes(await appliedCarId(database)))
          .firstWhere((p) => p.name == '水温')
          .id!;
      await diagnostics.saveProbeReading(
        fuelId,
        value: '38%',
        percent: 37.6,
        at: DateTime(2026, 11, 14, 8, 0, 0),
      );
      await diagnostics.saveProbeReading(
        coolantId,
        value: '95℃',
        at: DateTime(2026, 11, 14, 8, 0, 0),
      );
      // 直写仓库绕过了写点直失效（轮询落库写点已收在 App 级连接装配，
      // obd_runtime.dart）：这里镜像动作层纪律手动逐出，进页才能读到
      // 带最后读数的检测点清单。
      ProviderScope.containerOf(
        tester.element(find.byType(LunioPage).first),
      ).invalidate(diagnosticsProbesProvider);

      await openDiagnosticsPage(tester);

      // 卡：跨天时间带日期（M/d HH:mm:ss），两张有值的卡各一枚。
      expect(find.text('38%'), findsOneWidget);
      expect(find.textContaining('08:00:00'), findsNWidgets(2));
      expect(find.text('95℃'), findsOneWidget);
      // 电压/CVT 油温从未有过有效值：灰态「—」+「未更新」（升数估算
      // 已删，油量卡不再有「≈ x 升」行可断言）。
      expect(find.text('—'), findsNWidgets(2));
      expect(find.text('未更新'), findsNWidgets(2));
      await leavePageAndFlush(tester);
    });

    testWidgets('轮询读数落库：有效值写、无数据不写不覆盖', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final rig = DiagnosticsRig(
        responses: {
          ...rigStandardResponses(),
          // 油量本轮 NO DATA：卡显灰字，持久化层不写不覆盖。
          '012F': rigResp('NO DATA\r\r>'),
        },
      );
      await seedDeveloperDiagnostics(database);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await openDiagnosticsPage(tester);

      // 连接成功进轮询：油量 NO DATA（卡从未有过值 → 灰态），水温显
      // 有效值；收满一轮让其余卡也落定（余五条：电压/短期/长期/CVT
      // 油温/里程表）。
      await rig.advanceUntil(tester, find.text('95℃'));
      for (var i = 0; i < 5; i++) {
        await rig.deliverChunks(tester);
      }

      // 卡侧：油量卡「—」+「未更新」，其余卡有值（NO DATA 不上卡，
      // 「无数据」文案在 ADR 0029 卡化后不再出现）。
      final fuelCard = find.ancestor(
        of: find.text('油量'),
        matching: find.byType(LunioCard),
      );
      expect(
        find.descendant(of: fuelCard, matching: find.text('—')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: fuelCard, matching: find.text('未更新')),
        findsOneWidget,
      );
      expect(find.text('无数据'), findsNothing);

      // 库内口径：油量不写库（保持 null）、水温有效值已写。
      final diagnostics = testRepository(database).diagnosticsRepository;
      final probes = await diagnostics.listProbes(await appliedCarId(database));
      final fuel = probes.firstWhere((p) => p.name == '油量');
      final coolant = probes.firstWhere((p) => p.name == '水温');
      expect(fuel.lastValue, isNull);
      expect(coolant.lastValue, '95℃');
      await leavePageAndFlush(tester);
    });

    testWidgets('实时无数据不遮蔽持久化最后值：显旧值+旧时间戳（2026-11-17 拍板）', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      // 012F 不在应答表 = Mock 静默脚本 → 本轮油量超时无数据。
      final rig = DiagnosticsRig(
        responses: rigStandardResponses()..remove('012F'),
      );
      await seedAppliedCar(database);
      await seedDeveloperDiagnostics(database);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await gotoTab(tester, '我的');
      await tester.pumpAndSettle();

      // 开页前预写油量最后读数（昨天 08:00:00）：30%。
      final diagnostics = testRepository(database).diagnosticsRepository;
      final fuelId = (await diagnostics.listProbes(await appliedCarId(database)))
          .firstWhere((p) => p.name == '油量')
          .id!;
      await diagnostics.saveProbeReading(
        fuelId,
        value: '30%',
        percent: 30,
        at: DateTime(2026, 11, 17, 8, 0, 0),
      );
      ProviderScope.containerOf(
        tester.element(find.byType(LunioPage).first),
      ).invalidate(diagnosticsProbesProvider);

      await openDiagnosticsPage(tester);
      await rig.advanceUntil(tester, find.text('已连接'));

      // 放行 012F 的 300ms 超时 → 实时无数据：油量卡回退持久化最后值
      // （旧值 + 旧时间戳，不切灰态）；水温照常更新，其他卡不连坐。
      await rig.completeProbeTimeout(tester);
      await rig.deliverChunks(tester);
      final fuelCard = find.ancestor(
        of: find.text('油量'),
        matching: find.byType(LunioCard),
      );
      expect(
        find.descendant(of: fuelCard, matching: find.text('30%')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: fuelCard, matching: find.textContaining('11/17 08:00:00')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: fuelCard, matching: find.text('—')),
        findsNothing,
      );
      expect(
        find.descendant(of: fuelCard, matching: find.text('未更新')),
        findsNothing,
      );
      expect(find.text('无数据'), findsNothing);
      expect(find.text('95℃'), findsOneWidget);
      expect(find.text('已连接'), findsOneWidget);

      await leavePageAndFlush(tester);
    });
  });

  group('ECU 里程同步（ADR 0026，2026-11-18 起仅静默一档）', () {
    /// 逐拍泵帧直至里程表读数落库（runtime 写点 UPDATE last 三列）：
    /// 20 拍封顶。返回即读数事件已处理——同一事件点同步触发的 ECU 里程
    /// 回调（obd_runtime 静默同步链）已在跑，后续守卫/落库断言以此为
    /// 定界（里程表内置探针不上卡，页面无值可等，只能锚库值）。
    Future<void> pumpUntilOdometerReadingSaved(
      WidgetTester tester,
      AppDatabase database,
    ) async {
      final diagnostics = testRepository(database).diagnosticsRepository;
      for (var i = 0; i < 20; i++) {
        final probes =
            await diagnostics.listProbes(await appliedCarId(database));
        if (probes.firstWhere((p) => p.name == '里程表').lastValue != null) {
          return;
        }
        await tester.pump();
      }
      fail('20 拍内里程表读数未落库——轮询门闩或读数写点有问题');
    }

    /// 逐拍泵帧直至车辆里程写为 [expectedKm]（静默自动写链：读开关 →
    /// 读当前应用车 → 守卫写库），20 拍封顶。
    Future<void> pumpUntilCarMileage(
      WidgetTester tester,
      AppDatabase database,
      int expectedKm,
    ) async {
      for (var i = 0; i < 20; i++) {
        final cars = await database.select(database.cars).get();
        if (cars.single.currentMileageKm == expectedKm) {
          return;
        }
        await tester.pump();
      }
      fail('20 拍内车辆里程未写到 $expectedKm——静默同步链有问题');
    }

    /// 已连接后收满一轮（内置七条含里程表 01A6 → 66,068 km 读数）。
    Future<void> connectAndFinishFirstRound(
      WidgetTester tester,
      DiagnosticsRig rig,
    ) async {
      await rig.advanceUntil(tester, find.text('已连接'));
      for (var i = 0; i < 7; i++) {
        await rig.deliverChunks(tester);
      }
    }

    testWidgets('守卫：静默档 ECU 里程不大于车辆里程不写库（只增不减）', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final rig = DiagnosticsRig();
      await seedAppliedCar(database, mileageKm: 70000);
      await seedDeveloperDiagnostics(database);
      await testRepository(database).setPreferenceValue(
        LunioPreferences.obdOdometerAutoSyncKey,
        'true',
      );
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await openDiagnosticsPage(tester);
      await connectAndFinishFirstRound(tester, rig);
      await pumpUntilOdometerReadingSaved(tester, database);
      // 静默同步链（读开关/读车/守卫）再泵几拍走完。
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }

      // 动作层「只增不减」守卫拒绝分支（ADR 0026 静默自动写的唯一安全
      // 栏）：删掉守卫 → 这里变 66068，用例红灯。controller 收里程读数
      // 即调 handler 的接缝语义在 controller 层锁定
      //（diagnostics_connection_controller_test「ECU 里程读数经接缝回调」）。
      final cars = await database.select(database.cars).get();
      expect(cars.single.currentMileageKm, 70000);
      // 静默档无确认入口、无弹窗（确认式入口随 App 级化取消，2026-11-18）。
      expect(find.text('更新里程'), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      await leavePageAndFlush(tester);
    });

    testWidgets('静默自动写：开关开时读到更大里程直接落库、不弹窗', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final rig = DiagnosticsRig();
      await seedAppliedCar(database, mileageKm: 10000);
      await seedDeveloperDiagnostics(database);
      await testRepository(database).setPreferenceValue(
        LunioPreferences.obdOdometerAutoSyncKey,
        'true',
      );
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);
      await openDiagnosticsPage(tester);
      await connectAndFinishFirstRound(tester, rig);

      // 静默档：无确认入口、不弹窗；等静默写链跑完后车辆里程已落库。
      await pumpUntilCarMileage(tester, database, 66068);
      expect(find.text('更新里程'), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      await leavePageAndFlush(tester);
    });

    testWidgets('管理 sheet 开关行：默认关，打开后写偏好并重算', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final rig = DiagnosticsRig();
      await seedDeveloperDiagnostics(database);
      await pumpApp(tester, database: database, extraOverrides: rig.overrides);

      // 入口已不在诊断页（ADR 0029）：我的页车辆卡「检测点」按钮直接
      // 开 sheet，无需进诊断页。
      await openProbeManagementSheet(tester);
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
    });
  });
}
