// 保养记录实体（≈ Java POJO）：某天对某辆车做过的一次保养。
//
// 一条记录可包含多个保养项目（itemIds 多对多，落库到
// maintenance_record_items 表）。金额用"分"存储（costCents）避免浮点误差，
// 与 Java 后端用 Long 存分的惯例一致。
//
// 注意：数据库层 maintenance_records 表有 {carId, date} 唯一约束——
// 一辆车一天只能有一条记录；Repository 另有"同日同项目不可重复"的
// 业务校验（_ensureRecordIsUnique），两层规则口径不同（详见审查报告）。
import '../../core/date/local_date.dart';
import 'sync_metadata.dart';

class MaintenanceRecord {
  const MaintenanceRecord({
    this.id,
    required this.carId,
    required this.date,
    required this.itemIds,
    required this.costCents,
    required this.mileageKm,
    required this.sync,
    this.note,
  });

  /// 数据库主键（Snowflake id）。未入库时为 null。
  final int? id;

  /// 所属车辆 id。
  final int carId;

  /// 保养日期（只到天）。
  final LocalDate date;

  /// 本次保养的项目 id 列表（保存前经 RecordRules.uniqueItemIds 去重）。
  final List<int> itemIds;

  /// 花费，单位"分"。0 表示未记录金额。
  final int costCents;

  /// 保养时的里程（公里）。写入后会触发车辆里程"只增"同步。
  final int mileageKm;

  /// 备注，可为空。
  final String? note;

  /// 云同步元数据。
  final SyncMetadata sync;
}
