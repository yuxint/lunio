// 加油记录实体（≈ Java 的流水 POJO）：某天给某辆车加的一次油。
//
// 五项输入字段（ADR 0015，2026-09-22 重定义）：日期、油品、单价、
// 应付金额、实付金额；容积（应付 ÷ 单价）由本类构造时算好落库，
// 属**预留字段**——页面暂不展示，与车辆档案的油箱容积
// （Car.tankCapacityLiters）不是同一个概念。
//
// 与保养记录（MaintenanceRecord）的两个关键差异（沿 ADR 0014）：
//  - 一天可以有多条（长途一天两箱合法），数据库层没有 {carId, date}
//    唯一约束，也没有"同日查重"业务规则；
//  - 不联动车辆当前里程——保养记录是车辆里程的唯一写源。
//
// 金额全部用"分"存储（int）避免浮点误差，与保养记录 costCents 一致；
// 单价同为分（每升）；容积用 double（两位小数），与油箱容积同精度先例。
import '../../core/date/local_date.dart';
import 'fuel_price.dart';
import 'sync_metadata.dart';

class FuelRecord {
  /// 构造即自校验（不合法抛 ArgumentError），与 FuelPrediction 同先例；
  /// 因此本类不可 const 构造。容积在构造时由应付金额 ÷ 单价算出
  /// （四舍五入到两位小数，与油机跳枪数精度一致），不接受外部传入，
  /// 保证这一派生值全库只有一处算法、永不与输入字段矛盾。
  FuelRecord({
    this.id,
    required this.carId,
    required this.date,
    required this.grade,
    required this.unitPriceCents,
    required this.payableCents,
    this.actualCents,
    SyncMetadata? sync,
  }) : sync =
           sync ??
           SyncMetadata(status: SyncStatus.synced, updatedAt: DateTime.now()),
       volumeLiters = _computeVolumeLiters(
         payableCents: payableCents,
         unitPriceCents: unitPriceCents,
       ) {
    validate();
  }

  /// 行 id（雪花，Repository 生成；未入库为 null）。
  final int? id;

  /// 所属车辆 id。
  final int carId;

  /// 加油日期（只到天）。
  final LocalDate date;

  /// 油品（92/95/98/0#）。
  final FuelGrade grade;

  /// 每升单价，单位"分"（8.15 元/升 = 815，> 0）。用户输入的权威值。
  final int unitPriceCents;

  /// 应付金额（加油机口径），单位"分"（> 0）。
  final int payableCents;

  /// 实付金额（优惠后实际支付），单位"分"。null = 未填（无优惠，
  /// 统计与展示取应付金额）；有值时 ≥ 0，可以大于应付（不拦截，
  /// 用户自己的账）。
  final int? actualCents;

  /// 加油容积（升，两位小数）＝应付金额 ÷ 单价。预留字段：落库但
  /// 页面暂不展示，供将来油耗等功能使用。
  final double volumeLiters;

  /// 同步元数据（沿用全库约定：syncStatus/updatedAt/version）。
  final SyncMetadata sync;

  /// 参与费用统计的金额（分）＝实付金额；没填（null）取应付金额。
  /// 统计页加油费用卡与记录页头部"今年加油"共用的唯一口径实现点。
  int get effectiveCostCents => actualCents ?? payableCents;

  /// 容积唯一算法：应付 ÷ 单价，四舍五入到两位小数。
  static double _computeVolumeLiters({
    required int payableCents,
    required int unitPriceCents,
  }) {
    final liters = payableCents / unitPriceCents;
    return (liters * 100).roundToDouble() / 100;
  }

  /// 写库/恢复备份前的统一校验，不合法抛 ArgumentError：
  /// 单价 > 0、应付金额 > 0（0 元加油没有物理意义）、实付金额
  /// 可空但填了必须非负。
  void validate() {
    if (unitPriceCents <= 0) {
      throw ArgumentError.value(
        unitPriceCents,
        'unitPriceCents',
        'Unit price must be positive',
      );
    }
    if (payableCents <= 0) {
      throw ArgumentError.value(
        payableCents,
        'payableCents',
        'Payable cost must be positive',
      );
    }
    final actual = actualCents;
    if (actual != null && actual < 0) {
      throw ArgumentError.value(
        actual,
        'actualCents',
        'Actual cost must be non-negative',
      );
    }
  }

  /// 复制并替换部分字段（≈ copyWith）。carId 开放替换是给备份恢复的
  /// carId 重映射用的（与 FuelPrediction 同先例）。容积随
  /// 应付/单价的替换重新计算。
  FuelRecord copyWith({
    int? id,
    int? carId,
    LocalDate? date,
    FuelGrade? grade,
    int? unitPriceCents,
    int? payableCents,
    Object? actualCents = _sentinel,
    SyncMetadata? sync,
  }) {
    return FuelRecord(
      id: id ?? this.id,
      carId: carId ?? this.carId,
      date: date ?? this.date,
      grade: grade ?? this.grade,
      unitPriceCents: unitPriceCents ?? this.unitPriceCents,
      payableCents: payableCents ?? this.payableCents,
      // null 是合法值（= 未填实付），用哨兵区分"没传"与"传了 null"。
      actualCents: actualCents == _sentinel
          ? this.actualCents
          : actualCents as int?,
      sync: sync ?? this.sync,
    );
  }

  static const _sentinel = Object();
}
