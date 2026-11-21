// 检测点表单的决策体控制器（票 06）：新增/编辑检测点 sheet 里全部业务
// 决策与字段状态的唯一实现。
//
// 职责：
//   1. 字段态：名称、指令原文两个输入框 + 解析类型选中项；
//   2. 编辑回填：三业务字段（名称 trim、指令原文、解析类型）回填编辑
//      目标；指令回填原文、提交时才归一（存量未归一行也原样回显）；
//   3. 校验阶梯：名称必填（trim 后非空）、指令必填（归一后非空）、
//      指令格式（归一后仅 ASCII 字母与数字——指令行只允许这两类字
//      符，这是格式校验不是指令白名单：spec 拍板不做白名单，副标题
//      注明"仅用于读取类指令"）；
//   4. 指令空白归一策略：提交载荷的指令 = normalizeObdCommand（大写
//      + 去全部空白，与解析模块同一份实现）——落库即发送文本，会话
//      发送侧再规整一次是幂等操作（票 06 之前存量的未归一行兜底）；
//   5. 提交载荷构造：三面守恒（id/enabled 不在表单字段里，编辑保持
//      原值）、catalogKey 恒 null（表单只产自定义项）、sync 状态位按
//      新增/编辑取 pendingCreate/pendingUpdate。
//
// 在 App 中的位置：只被 probe_form.dart 的 ProbeForm 使用。≈ Java
// Web 里表单页抽出来的 BackingBean（FuelRecordFormController 先例）：
// 持有输入控件状态与流转决策，widget 只做渲染并把事件转接进来；事件
// 方法只改状态不触发重建，widget 在事件返回后自行 setState。
//
// 与两道既有 seam 的边界（同加油表单控制器先例）：
//   - ADR 0016 表单运行时：本类不持有 FormSheetHandle、不碰 pop/toast/
//     saving；行内错误经注入的 reportError 写 handle（生命周期守卫留
//     在 widget 侧的注入闭包）；
//   - ADR 0007 动作层：本类只产出提交载荷，写库（saveDiagnosticsProbe）
//     的接线留在入口函数。
import 'package:flutter/material.dart';

import '../../../domain/entities/diagnostics_parse_type.dart';
import '../../../domain/entities/diagnostics_probe.dart';
import '../../../domain/entities/sync_metadata.dart';
import 'elm327_parser.dart' show normalizeObdCommand;

/// 检测点表单控制器（职责与边界见文件头）。
///
/// 接口约定：事件方法（setParseType / submitPayload）只改状态与经
/// reportError 报错，不触发重建——widget 在事件返回后自行 setState。
/// 渲染所需的派生状态经 isEditing / 两个 controller / parseType 暴露。
class ProbeFormController {
  ProbeFormController({
    required this.carId,
    DiagnosticsProbe? probe,
    required this.reportError,
    DateTime Function()? now,
  })  : probe = probe,
        _now = now ?? DateTime.now,
        // 编辑回填：名称 trim（存量行可能有未 trim 形态）、指令回填
        // 原文（未归一的存量形态原样回显，提交时才归一）、解析类型/
        // 刷新间隔回填原值。新增默认 60 秒（2026-11-21 拍板，与
        // DiagnosticsRepository.defaultRefreshIntervalSeconds 同值）。
        nameController = TextEditingController(text: probe?.name.trim() ?? ''),
        commandController =
            TextEditingController(text: probe?.command ?? ''),
        refreshIntervalController = TextEditingController(
          text: (probe?.refreshIntervalSeconds ?? 60).toString(),
        ),
        parseType = probe?.parseType ?? DiagnosticsParseType.rawHex;

  /// 归属车辆（每车一套，ADR 0021 修订节）。新增/编辑都带上；编辑时
  /// 与目标行 carId 不匹配会被仓库拒绝。
  final int carId;

  /// 编辑目标检测点（null = 新增）。内置行也可编辑（ADR 0021 修订节）；
  /// catalogKey/header 在提交载荷里按原值守恒。
  final DiagnosticsProbe? probe;

  /// 行内错误注入点：控制器把校验错误的文案写到 widget 侧的
  /// handle.setFormError（ADR 0016 错误统一在把手上显示）。
  final void Function(String? message) reportError;

  /// 当前时刻注入（默认 DateTime.now）：提交载荷的 sync.updatedAt 与
  /// now 解耦，单测可固定时刻断言。
  final DateTime Function() _now;

  /// 名称输入框。
  final TextEditingController nameController;

  /// 指令原文输入框。
  final TextEditingController commandController;

  /// 刷新间隔输入框（秒，ADR 0023）。默认 60（2026-11-21 起，与
  /// `DiagnosticsRepository.defaultRefreshIntervalSeconds` 同值），范围 5–3600。
  final TextEditingController refreshIntervalController;

  /// 解析类型选中项（新增默认 rawHex）。分段控件结构上必有选中项，
  /// "解析类型必选"由 UI 结构保证、无需用户面对报错。
  DiagnosticsParseType parseType;

  bool get isEditing => probe != null;

  /// 切换解析类型：纯赋值。
  void setParseType(DiagnosticsParseType value) {
    parseType = value;
  }

  /// 从推荐模板回填名称/指令/解析类型（刷新间隔保持用户当前值）。
  void applyTemplate({
    required String name,
    required String command,
    required DiagnosticsParseType parseType,
  }) {
    nameController.text = name;
    commandController.text = command;
    this.parseType = parseType;
  }

  /// 「保存」的提交载荷：校验阶梯失败时报行内错误（中文文案）并返回
  /// null；成功时构造 [DiagnosticsProbe]——指令经 normalizeObdCommand
  /// 归一（大写 + 去全部空白，落库即发送文本）、名称 trim、启停保持
  /// 原值（编辑不碰启停，启停走行开关）、sync 状态位按新增/编辑取
  /// pendingCreate/pendingUpdate、updatedAt 经注入的 now。写库由 widget
  /// 经 handle.submit → 动作层完成，本类不碰。
  DiagnosticsProbe? submitPayload() {
    final name = nameController.text.trim();
    final command = normalizeObdCommand(commandController.text);
    final refreshInterval = int.tryParse(
      refreshIntervalController.text.trim(),
    );
    if (name.isEmpty) {
      reportError('检测点名称不能为空');
      return null;
    }
    if (command.isEmpty) {
      reportError('指令不能为空');
      return null;
    }
    if (!_commandFormat.hasMatch(command)) {
      reportError('指令只能由字母与数字组成');
      return null;
    }
    if (refreshInterval == null ||
        refreshInterval < 5 ||
        refreshInterval > 3600) {
      reportError('刷新间隔必须是 5–3600 秒');
      return null;
    }
    return DiagnosticsProbe(
      id: probe?.id,
      carId: carId,
      name: name,
      command: command,
      parseType: parseType,
      enabled: probe?.enabled ?? true,
      catalogKey: probe?.catalogKey,
      refreshIntervalSeconds: refreshInterval,
      header: probe?.header,
      sync: SyncMetadata(
        status: isEditing ? SyncStatus.pendingUpdate : SyncStatus.pendingCreate,
        updatedAt: _now(),
      ),
    );
  }

  /// 释放全部输入控件（widget dispose 时调用）。
  void dispose() {
    nameController.dispose();
    commandController.dispose();
    refreshIntervalController.dispose();
  }

  /// 指令格式正则（归一后仅 ASCII 字母与数字）。
  static final RegExp _commandFormat = RegExp(r'^[0-9A-Z]+$');
}
