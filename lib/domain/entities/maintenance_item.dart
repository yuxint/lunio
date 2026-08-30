// 保养项目实体（≈ Java POJO）：一辆车上的一个保养项，如"机油""刹车油"。
//
// 提醒规则由两类开关 + 两个间隔共同决定：
//  - remindByMileage + mileageIntervalKm：按里程提醒（如每 5000km 一次）
//  - remindByTime + timeIntervalMonths：按时间提醒（如每 6 个月一次）
// 两维同时开启时，进度计算取较大者（见 rules/maintenance_rules.dart）。
//
// 数据库唯一约束：carsId + name（一辆车同名项目只能有一个）。
import 'sync_metadata.dart';

class MaintenanceItem {
  const MaintenanceItem({
    this.id,
    required this.carsId,
    required this.name,
    required this.enabled,
    required this.remindByMileage,
    required this.remindByTime,
    this.notOverdueUpperLimit = 100,
    this.overdueUpperLimit = 125,
    required this.sortOrder,
    required this.sync,
    this.mileageIntervalKm,
    this.timeIntervalMonths,
  });

  /// 数据库主键（Snowflake id）。未入库时为 null。
  final int? id;

  /// 所属车辆 id（逻辑外键，数据库层未声明 FOREIGN KEY）。
  final int carsId;

  /// 项目名称。trim 后不能为空（见 [validate]）。
  final String name;

  /// 是否参与提醒计算与列表展示。停用的项目不出现在提醒列表。
  /// 业务保证"每辆车至少保留一个启用项"（Repository 校验）。
  final bool enabled;

  /// 是否按里程提醒。
  final bool remindByMileage;

  /// 是否按时间（月）提醒。两个提醒开关至少要开一个。
  final bool remindByTime;

  /// 里程提醒间隔（公里）。remindByMileage 为 true 时必须为正数。
  final int? mileageIntervalKm;

  /// 时间提醒间隔（月）。remindByTime 为 true 时必须为正数。
  final int? timeIntervalMonths;

  /// 进入"到期"（warning 黄色）的进度阈值百分比，默认 100。
  final double notOverdueUpperLimit;

  /// 进入"超期"（danger 红色）的进度阈值百分比，默认 125。
  final double overdueUpperLimit;

  /// 列表排序权重，越小越靠前（继承自内置默认项目的顺序）。
  final int sortOrder;

  /// 云同步元数据。
  final SyncMetadata sync;

  /// 复制并替换部分字段（不可变对象更新惯例）。
  MaintenanceItem copyWith({
    int? id,
    int? carsId,
    String? name,
    bool? enabled,
    bool? remindByMileage,
    bool? remindByTime,
    int? mileageIntervalKm,
    int? timeIntervalMonths,
    double? notOverdueUpperLimit,
    double? overdueUpperLimit,
    int? sortOrder,
    SyncMetadata? sync,
  }) {
    return MaintenanceItem(
      id: id ?? this.id,
      carsId: carsId ?? this.carsId,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      remindByMileage: remindByMileage ?? this.remindByMileage,
      remindByTime: remindByTime ?? this.remindByTime,
      mileageIntervalKm: mileageIntervalKm ?? this.mileageIntervalKm,
      timeIntervalMonths: timeIntervalMonths ?? this.timeIntervalMonths,
      notOverdueUpperLimit: notOverdueUpperLimit ?? this.notOverdueUpperLimit,
      overdueUpperLimit: overdueUpperLimit ?? this.overdueUpperLimit,
      sortOrder: sortOrder ?? this.sortOrder,
      sync: sync ?? this.sync,
    );
  }

  /// 实体自校验：名称非空、至少一种提醒方式、开启的提醒方式对应间隔为正。
  /// 由 Repository 在写库前调用；失败抛 ArgumentError
  /// （≈ Java 的 IllegalArgumentException），UI 层经 friendlyError 翻译成中文。
  void validate() {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'Maintenance item name is empty');
    }
    if (!remindByMileage && !remindByTime) {
      throw ArgumentError('At least one reminder type must be enabled');
    }
    if (remindByMileage &&
        (mileageIntervalKm == null || mileageIntervalKm! <= 0)) {
      throw ArgumentError('Mileage reminder interval must be positive');
    }
    if (remindByTime &&
        (timeIntervalMonths == null || timeIntervalMonths! <= 0)) {
      throw ArgumentError('Time reminder interval must be positive');
    }
  }
}
