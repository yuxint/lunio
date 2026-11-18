// 检测点表单控制器（ProbeFormController）的单元测试。
//
// 直接打控制器收编出来的全部决策（fuel_record_form_controller_test
// 先例，spec「Testing Decisions」预先拍板的接缝）：
//  - 新增默认：解析类型默认原始 hex（story 24 兜底）、文本字段空；
//  - 编辑回填：三业务字段（名称 trim、指令原文、解析类型）回填编辑
//    目标；指令回填原文、提交时才归一（存量未归一行也原样回显）；
//  - 校验阶梯：名称必填、指令必填、指令格式（归一后仅字母与数字），
//    失败报中文行内错误、不产出载荷；
//  - 指令空白归一策略：保存前归一（大写 + 去全部空白），落库即发送
//    文本；会话发送侧再规整一次（幂等，票 06 之前的存量未归一行兜底）；
//  - 新增/编辑提交载荷：id/enabled/catalogKey 三面守恒、sync 状态位
//    pendingCreate/pendingUpdate、updatedAt 用注入时钟。
//
// 指令合法性本体在 DiagnosticsProbe.validate（实体构造自校验），这里
// 只锁控制器的输入态编排与中文文案；表单增改删的页面交互回归在
// test/widget/diagnostics_test.dart。
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/domain/entities/diagnostics_parse_type.dart';
import 'package:lunio/domain/entities/diagnostics_probe.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';
import 'package:lunio/features/shell/diagnostics/probe_form_controller.dart';
import 'package:lunio/features/shell/diagnostics/probe_templates.dart';

/// 测试夹具：装配控制器 + 行内错误捕获 + 注入时钟。
class ProbeFormHarness {
  ProbeFormHarness({DiagnosticsProbe? probe}) {
    controller = ProbeFormController(
      carId: 1,
      probe: probe,
      reportError: (message) => reportedError = message,
      now: () => fixedNow,
    );
  }

  late final ProbeFormController controller;

  /// 行内错误捕获（控制器校验失败时写非空文案、成功路径不写）。
  String? reportedError;

  /// 注入的固定时钟：sync.updatedAt 的断言值。
  final DateTime fixedNow = DateTime(2026, 6, 1, 8, 30);
}

/// 编辑态夹具目标（自定义检测点，已入库形态：带 id、启停 false）。
DiagnosticsProbe editTarget() => DiagnosticsProbe(
      id: 512,
      carId: 1,
      name: '节气门',
      command: '0111',
      parseType: DiagnosticsParseType.rawHex,
      enabled: false,
      refreshIntervalSeconds: 60,
    );

void main() {
  test('new form defaults: parse type rawHex, fields empty, not editing', () {
    final harness = ProbeFormHarness();
    expect(harness.controller.isEditing, isFalse);
    expect(harness.controller.nameController.text, isEmpty);
    expect(harness.controller.commandController.text, isEmpty);
    expect(harness.controller.parseType, DiagnosticsParseType.rawHex);
    expect(harness.controller.refreshIntervalController.text, '10');
  });

  test('edit form backfills name, raw command and parse type', () {
    final harness = ProbeFormHarness(
      probe: DiagnosticsProbe(
        id: 512,
        carId: 1,
        name: '节气门',
        command: '01 11',
        parseType: DiagnosticsParseType.coolantTemp,
        refreshIntervalSeconds: 45,
      ),
    );

    expect(harness.controller.isEditing, isTrue);
    expect(harness.controller.nameController.text, '节气门');
    // 指令回填原文（未归一的存量形态也原样回显，提交时才归一）。
    expect(harness.controller.commandController.text, '01 11');
    expect(harness.controller.parseType, DiagnosticsParseType.coolantTemp);
    expect(harness.controller.refreshIntervalController.text, '45');
  });

  test('validation ladder rejects blank name', () {
    final harness = ProbeFormHarness();
    harness.controller.commandController.text = '0111';

    // 全空白 = 空（trim 后空）。
    harness.controller.nameController.text = '   ';
    expect(harness.controller.submitPayload(), isNull);
    expect(harness.reportedError, '检测点名称不能为空');
  });

  test('validation ladder rejects blank command', () {
    final harness = ProbeFormHarness();
    harness.controller.nameController.text = '节气门';

    harness.controller.commandController.text = '   ';
    expect(harness.controller.submitPayload(), isNull);
    expect(harness.reportedError, '指令不能为空');

    harness.controller.commandController.text = '';
    expect(harness.controller.submitPayload(), isNull);
    expect(harness.reportedError, '指令不能为空');
  });

  test('validation ladder rejects non-alphanumeric command', () {
    final harness = ProbeFormHarness();
    harness.controller.nameController.text = '节气门';
    harness.controller.commandController.text = '01-2F';
    expect(harness.controller.submitPayload(), isNull);
    expect(harness.reportedError, '指令只能由字母与数字组成');
    // 分号同判非法（标点不是字母数字）；小写合法（归一升大写）。
    harness.controller.commandController.text = '0111;';
    expect(harness.controller.submitPayload(), isNull);
    expect(harness.reportedError, '指令只能由字母与数字组成');

    // 小写合法：归一升大写，不是格式错误。
    harness.controller.commandController.text = '01 2f';
    final payload = harness.controller.submitPayload();
    expect(payload, isNotNull);
    expect(payload!.command, '012F');
  });

  test('command normalization: whitespace stripped and uppercased into payload', () {
    final harness = ProbeFormHarness();
    harness.controller.nameController.text = '节气门';
    harness.controller.commandController.text = '01 2f';
    final payload = harness.controller.submitPayload();
    expect(payload, isNotNull);
    expect(payload!.command, '012F');
  });

  test('new payload: pendingCreate with injected clock, id null', () {
    final harness = ProbeFormHarness();
    harness.controller.nameController.text = '节气门';
    harness.controller.commandController.text = '0111';
    final payload = harness.controller.submitPayload();
    expect(payload, isNotNull);
    expect(payload!.id, isNull);
    expect(payload.carId, 1);
    expect(payload.catalogKey, isNull);
    expect(payload.parseType, DiagnosticsParseType.rawHex);
    expect(payload.refreshIntervalSeconds, 10);
    expect(payload.enabled, isTrue);
    expect(payload.sync.status, SyncStatus.pendingCreate);
    expect(payload.sync.updatedAt, harness.fixedNow);
  });

  test('edit payload: id and enabled preserved, pendingUpdate', () {
    final harness = ProbeFormHarness(probe: editTarget());
    harness.controller.nameController.text = '进气压力';
    final payload = harness.controller.submitPayload();
    expect(payload, isNotNull);
    expect(payload!.id, 512);
    expect(payload.carId, 1);
    expect(payload.enabled, isFalse, reason: '编辑不碰启停');
    expect(payload.parseType, DiagnosticsParseType.rawHex);
    expect(payload.refreshIntervalSeconds, 60);
    expect(payload.sync.status, SyncStatus.pendingUpdate);
    expect(payload.sync.updatedAt, harness.fixedNow);
  });

  test('setParseType switches selection carried into payload', () {
    final harness = ProbeFormHarness();
    harness.controller.setParseType(DiagnosticsParseType.coolantTemp);
    harness.controller.nameController.text = '水温对比';
    harness.controller.commandController.text = '0105';
    final payload = harness.controller.submitPayload();
    expect(payload!.parseType, DiagnosticsParseType.coolantTemp);
  });

  test('applyTemplate fills name/command/parseType', () {
    final harness = ProbeFormHarness();
    final template = diagnosticsProbeTemplates.first;
    harness.controller.applyTemplate(
      name: template.name,
      command: template.command,
      parseType: template.parseType,
    );
    final payload = harness.controller.submitPayload();
    expect(payload, isNotNull);
    expect(payload!.name, template.name);
    expect(payload.command, template.command);
    expect(payload.parseType, template.parseType);
    expect(payload.refreshIntervalSeconds, 10, reason: '模板不动间隔');
  });

  test('refresh interval rejects outside 5–3600 seconds', () {
    final harness = ProbeFormHarness();
    harness.controller.nameController.text = '节气门';
    harness.controller.commandController.text = '0111';
    for (final value in ['4', '3601', '', 'abc']) {
      harness.controller.refreshIntervalController.text = value;
      expect(harness.controller.submitPayload(), isNull);
      expect(harness.reportedError, '刷新间隔必须是 5–3600 秒');
    }
  });
}
