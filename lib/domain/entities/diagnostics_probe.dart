// 检测点实体：页面上的一个数据条目 = 一条指令 + 一种解析方式 + 一个
// 展示位。用户可自定义，内置三条（油量/水温/电压）只读、可启停
// （GLOSSARY「车辆诊断」节，ADR 0021）。
//
// ≈ Java 的 POJO + 自校验构造器：构造即校验（不合法抛 ArgumentError），
// 与 FuelRecord 同先例。全局数据（不挂 carId，ADR 0021）：指令语义
// 与车无关，删车不级联、与车辆数据纪元无关。
import 'diagnostics_parse_type.dart';
import 'sync_metadata.dart';

class DiagnosticsProbe {
  /// 构造即自校验；因此本类不可 const 构造。
  DiagnosticsProbe({
    this.id,
    required this.name,
    required this.command,
    this.parseType = DiagnosticsParseType.rawHex,
    this.enabled = true,
    this.catalogKey,
    SyncMetadata? sync,
  }) : sync = sync ??
           SyncMetadata(status: SyncStatus.synced, updatedAt: DateTime.now()) {
    validate();
  }

  /// 行 id（雪花，Repository 生成；未入库为 null）。
  final int? id;

  /// 展示名（如"油量"）。内置行不可改、自定义行可改。
  final String name;

  /// 指令原文（如 `012F`、`ATRV`）。内置行不可改、自定义行可改。表单
  /// 保存前归一（probe_form_controller：大写 + 去全部空白，落库即发送
  /// 文本）；发送前会话再规整一次（幂等，票 06 之前存量未归一行兜底）。
  final String command;

  /// 解析类型（四种，见 [DiagnosticsParseType]）。
  final DiagnosticsParseType parseType;

  /// 启停。内置行也允许启停（唯一可变的内置字段）；轮询只发启用项。
  final bool enabled;

  /// 内置标识（稳定 catalogKey，供 bootstrap 幂等对账）：非 null =
  /// 内置行（只读 + 可启停）；null = 自定义行（可增改删）。内置不进
  /// 备份、自定义项进备份段时不带本字段（ADR 0021）。
  final String? catalogKey;

  /// 同步元数据（沿用全库约定：syncStatus/updatedAt/version）。
  final SyncMetadata sync;

  /// 是否内置检测点。
  bool get isBuiltIn => catalogKey != null;

  /// 写库/恢复备份前的统一校验：名称与指令原文去首尾空白后必须非空，
  /// 不合法抛 ArgumentError。
  void validate() {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'Probe name must not be blank');
    }
    if (command.trim().isEmpty) {
      throw ArgumentError.value(
        command,
        'command',
        'Probe command must not be blank',
      );
    }
  }

  /// 复制并替换部分字段（≈ copyWith）。catalogKey 用哨兵区分"没传"
  /// （保持原值）与"传了 null"（清成自定义）——与 FuelRecord.actualCents
  /// 同手法。sync 不传时保留原值。
  DiagnosticsProbe copyWith({
    int? id,
    String? name,
    String? command,
    DiagnosticsParseType? parseType,
    bool? enabled,
    Object? catalogKey = _sentinel,
    SyncMetadata? sync,
  }) {
    return DiagnosticsProbe(
      id: id ?? this.id,
      name: name ?? this.name,
      command: command ?? this.command,
      parseType: parseType ?? this.parseType,
      enabled: enabled ?? this.enabled,
      catalogKey: catalogKey == _sentinel
          ? this.catalogKey
          : catalogKey as String?,
      sync: sync ?? this.sync,
    );
  }

  static const _sentinel = Object();
}
