// 加油记录实体（≈ Java 的流水 POJO）：某天给某辆车加的一次油。
//
// 与保养记录（MaintenanceRecord）的两个关键差异（ADR 0014）：
//  - 一天可以有多条（长途一天两箱合法），数据库层没有 {carId, date}
//    唯一约束，也没有"同日查重"业务规则；
//  - 保存不联动车辆当前里程——保养记录是车辆里程的唯一写源，避免
//    两个来源打架。
//
// 金额用"分"存储（totalCostCents）避免浮点误差，与保养记录 costCents
// 一致；升数用 double，与油箱容积 tankCapacityLiters 同精度先例。
import '../../core/date/local_date.dart';
import 'sync_metadata.dart';

class FuelRecord {
  /// 构造即自校验（不合法抛 ArgumentError），与 FuelPrediction 同先例；
  /// 因此本类不可 const 构造。
  FuelRecord({
    this.id,
    required this.carId,
    required this.date,
    required this.mileageKm,
    required this.volumeLiters,
    required this.totalCostCents,
    required this.fullTank,
    SyncMetadata? sync,
  }) : sync =
           sync ??
           SyncMetadata(status: SyncStatus.synced, updatedAt: DateTime.now()) {
    validate();
  }

  /// 行 id（雪花，Repository 生成；未入库为 null）。
  final int? id;

  /// 所属车辆 id。
  final int carId;

  /// 加油日期（只到天）。
  final LocalDate date;

  /// 加油时的里程（公里）。仅作流水记录，不回写车辆当前里程。
  final int mileageKm;

  /// 加油升数（> 0）。
  final double volumeLiters;

  /// 加油总金额，单位"分"（≥ 0）。单价 = 金额 ÷ 升数，展示层现算。
  final int totalCostCents;

  /// 是否加满。满箱段油耗口径（full-to-full）用它判定区间闭合。
  final bool fullTank;

  /// 同步元数据（沿用全库约定：syncStatus/updatedAt/version）。
  final SyncMetadata sync;

  /// 写库/恢复备份前的统一校验，不合法抛 ArgumentError：
  /// 里程/金额非负、升数必须大于 0（0 升的"加油"没有物理意义）。
  void validate() {
    if (mileageKm < 0) {
      throw ArgumentError.value(
        mileageKm,
        'mileageKm',
        'Mileage must be non-negative',
      );
    }
    if (totalCostCents < 0) {
      throw ArgumentError.value(
        totalCostCents,
        'totalCostCents',
        'Cost must be non-negative',
      );
    }
    if (volumeLiters <= 0) {
      throw ArgumentError.value(
        volumeLiters,
        'volumeLiters',
        'Volume must be positive',
      );
    }
  }

  /// 复制并替换部分字段（≈ copyWith）。carId 开放替换是给备份恢复的
  /// carId 重映射用的（与 FuelPrediction 同先例）。
  FuelRecord copyWith({
    int? id,
    int? carId,
    LocalDate? date,
    int? mileageKm,
    double? volumeLiters,
    int? totalCostCents,
    bool? fullTank,
    SyncMetadata? sync,
  }) {
    return FuelRecord(
      id: id ?? this.id,
      carId: carId ?? this.carId,
      date: date ?? this.date,
      mileageKm: mileageKm ?? this.mileageKm,
      volumeLiters: volumeLiters ?? this.volumeLiters,
      totalCostCents: totalCostCents ?? this.totalCostCents,
      fullTank: fullTank ?? this.fullTank,
      sync: sync ?? this.sync,
    );
  }
}
