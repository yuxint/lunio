// 加油预测实体：一辆车的加油预测设置（剩余油量，容积在 Car 上）。
//
// 按车辆一条（fuel_predictions 表 {carId} 唯一），切换当前应用车辆后
// 加油页展示的车跟着换。剩余油量是"用户通过滚动档位列表选出的值"，
// 进 JSON 备份（备份契约见 backup_codec.dart）；油箱容积在
// Car 实体（车的属性）；油价缓存/手填价是临时数据，不进备份、
// 也不在本实体里。
import 'sync_metadata.dart';

class FuelPrediction {
  FuelPrediction({
    this.id,
    required this.carId,
    required this.fuelPercent,
    SyncMetadata? sync,
  }) : sync =
           sync ??
           SyncMetadata(status: SyncStatus.synced, updatedAt: DateTime.now()) {
    validate();
  }

  /// 行 id（雪花，Repository 生成；未入库为 null）。
  final int? id;

  /// 所属车辆 id（与 fuel_predictions 表 {carId} 唯一约束对应）。
  final int carId;

  /// 剩余油量百分比（0–100，2% 一档；即加满预估列表钉在第一行的基准档）。
  /// 没有行的车按默认 50% 展示（展示默认在 UI 层处理，本实体必填）。
  final int fuelPercent;

  /// 同步元数据（沿用全库约定：syncStatus/updatedAt/version）。
  final SyncMetadata sync;

  /// 写库/恢复备份前的统一校验，不合法抛 ArgumentError。
  void validate() {
    if (fuelPercent < 0 || fuelPercent > 100) {
      throw ArgumentError.value(
        fuelPercent,
        'fuelPercent',
        'must be between 0 and 100',
      );
    }
  }

  /// 复制并替换部分字段（≈ copyWith）。
  FuelPrediction copyWith({
    int? id,
    int? carId,
    int? fuelPercent,
    SyncMetadata? sync,
  }) {
    return FuelPrediction(
      id: id ?? this.id,
      carId: carId ?? this.carId,
      fuelPercent: fuelPercent ?? this.fuelPercent,
      sync: sync ?? this.sync,
    );
  }
}
