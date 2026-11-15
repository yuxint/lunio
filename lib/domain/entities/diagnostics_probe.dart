// 检测点实体：页面上的一个数据条目 = 一条指令 + 一种解析方式 + 一个
// 展示位。每车一套（ADR 0021 修订节）：内置三条（油量/水温/电压）
// 可编辑、不可删除；自定义检测点可增改删。
//
// ≈ Java 的 POJO + 自校验构造器：构造即校验（不合法抛 ArgumentError），
// 与 FuelRecord 同先例。检测点挂 carId：切车随车变化，删车在事务里
// 级联删除；与车辆数据纪元无关（写点仍走 provider 点失效）。
import 'diagnostics_parse_type.dart';
import 'sync_metadata.dart';

class DiagnosticsProbe {
  /// 构造即自校验；因此本类不可 const 构造。
  DiagnosticsProbe({
    this.id,
    required this.carId,
    required this.name,
    required this.command,
    this.parseType = DiagnosticsParseType.rawHex,
    this.enabled = true,
    this.catalogKey,
    this.refreshIntervalSeconds = 30,
    this.header,
    this.lastValue,
    this.lastPercent,
    this.lastReadingAt,
    SyncMetadata? sync,
  }) : sync = sync ??
           SyncMetadata(status: SyncStatus.synced, updatedAt: DateTime.now()) {
    validate();
  }

  /// 行 id（雪花，Repository 生成；未入库为 null）。
  final int? id;

  /// 所属车辆 id（每车一套，ADR 0021 修订节）。存储列可空只为迁移期
  /// 存量回填；代码层必填——种子、表单、恢复备份都必须带车。
  final int carId;

  /// 展示名（如"油量"）。内置行也允许编辑。
  final String name;

  /// 指令原文（如 `012F`、`ATRV`）。内置行也允许编辑。表单保存前归一
  /// （probe_form_controller：大写 + 去全部空白，落库即发送文本）；发送
  /// 前会话再规整一次（幂等）。
  final String command;

  /// 解析类型（见 [DiagnosticsParseType]）。
  final DiagnosticsParseType parseType;

  /// 启停。轮询只发启用项。
  final bool enabled;

  /// 内置标识（稳定 catalogKey，供 bootstrap 幂等对账）：非 null =
  /// 内置行（可编辑、可启停、不可删）；null = 自定义行（可增改删）。
  /// 内置不进备份、自定义项进备份段时不带本字段（ADR 0021 修订节）。
  final String? catalogKey;

  /// 自动轮询间隔（秒，ADR 0023）：默认 30，范围 5–3600；手动刷新不受
  /// 它限制。调度器按各条到期时间轮询。
  final int refreshIntervalSeconds;

  /// 29-bit 物理头（如 `DA 60 F1`，私有 DID 预留，ADR 0023）。null =
  /// 默认功能寻址。本轮无 UI；验证通过后由私有解析使用。
  final String? header;

  /// 最后读数：展示值（reading.display）与时刻（ADR 0021 修订节）。
  /// 只存有效值（无数据不写不覆盖），设备派生临时数据：不进备份、写库
  /// 不盖同步章。行读取时由仓库从行映射，表单/恢复备份等构造路径保持
  /// null。
  final String? lastValue;

  /// 最后读数的油量百分比（仅 fuelLevel 类有效值有值）：油量卡升数估算
  /// 重进不缺数据。
  final double? lastPercent;

  /// 最后读数的时刻。
  final DateTime? lastReadingAt;

  /// 同步元数据（沿用全库约定：syncStatus/updatedAt/version）。
  final SyncMetadata sync;

  /// 是否内置检测点。
  bool get isBuiltIn => catalogKey != null;

  /// 写库/恢复备份前的统一校验：名称与指令原文去首尾空白后必须非空；
  /// 刷新间隔 5–3600 秒；header 有值时不得为空白。不合法抛
  /// ArgumentError。
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
    if (refreshIntervalSeconds < 5 || refreshIntervalSeconds > 3600) {
      throw ArgumentError.value(
        refreshIntervalSeconds,
        'refreshIntervalSeconds',
        'must be between 5 and 3600',
      );
    }
    if (header != null && header!.trim().isEmpty) {
      throw ArgumentError.value(
        header,
        'header',
        'must not be blank when present',
      );
    }
  }

  /// 复制并替换部分字段（≈ copyWith）。catalogKey / header / 最后读数用
  /// 哨兵区分"没传"（保持原值）与"传了 null"（清空）——与
  /// FuelRecord.actualCents 同手法。sync 不传时保留原值。
  DiagnosticsProbe copyWith({
    int? id,
    int? carId,
    String? name,
    String? command,
    DiagnosticsParseType? parseType,
    bool? enabled,
    Object? catalogKey = _sentinel,
    int? refreshIntervalSeconds,
    Object? header = _sentinel,
    Object? lastValue = _sentinel,
    Object? lastPercent = _sentinel,
    Object? lastReadingAt = _sentinel,
    SyncMetadata? sync,
  }) {
    return DiagnosticsProbe(
      id: id ?? this.id,
      carId: carId ?? this.carId,
      name: name ?? this.name,
      command: command ?? this.command,
      parseType: parseType ?? this.parseType,
      enabled: enabled ?? this.enabled,
      catalogKey: catalogKey == _sentinel
          ? this.catalogKey
          : catalogKey as String?,
      refreshIntervalSeconds:
          refreshIntervalSeconds ?? this.refreshIntervalSeconds,
      header: header == _sentinel ? this.header : header as String?,
      lastValue: lastValue == _sentinel ? this.lastValue : lastValue as String?,
      lastPercent: lastPercent == _sentinel
          ? this.lastPercent
          : lastPercent as double?,
      lastReadingAt: lastReadingAt == _sentinel
          ? this.lastReadingAt
          : lastReadingAt as DateTime?,
      sync: sync ?? this.sync,
    );
  }

  static const _sentinel = Object();
}