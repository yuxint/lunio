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

/// 单个保养项目在一条记录里的费用（ADR 0010）。
/// ≈ 订单明细行上的价格：一条记录勾了一个项目就有一份，同一个项目
/// 每次价格可以不同。三个金额都可空（null = 未填），且允许合法的
/// 不一致（如优惠改价后项目费用 ≠ 材料+工时），展示方原样展示。
class RecordItemCost {
  const RecordItemCost({
    required this.itemId,
    this.materialCents,
    this.laborCents,
    this.costCents,
  });

  /// 保养项目 id。
  final int itemId;

  /// 材料费（分），null = 未填。
  final int? materialCents;

  /// 工时费（分），null = 未填。
  final int? laborCents;

  /// 项目费用（分），null = 未填。权威值：求和与展示都取它。
  final int? costCents;

  /// 三个金额是否全部未填（全空 = 这条项目费用没有实际内容）。
  bool get isEmpty =>
      materialCents == null && laborCents == null && costCents == null;
}

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
    this.itemCosts = const [],
  });

  /// 数据库主键（Snowflake id）。未入库时为 null。
  final int? id;

  /// 所属车辆 id。
  final int carId;

  /// 保养日期（只到天）。
  final LocalDate date;

  /// 本次保养的项目 id 列表（保存前经 RecordRules.uniqueItemIds 去重）。
  final List<int> itemIds;

  /// 有费用内容的项目费用列表（ADR 0010）。只包含至少填了一个金额的
  /// 项目；不在列表里的项目 = 费用全空。itemId 必须都在 itemIds 内。
  final List<RecordItemCost> itemCosts;

  /// 花费，单位"分"。0 表示未记录金额。
  final int costCents;

  /// 保养时的里程（公里）。写入后会触发车辆里程"只增"同步。
  final int mileageKm;

  /// 备注，可为空。
  final String? note;

  /// 云同步元数据。
  final SyncMetadata sync;
}
