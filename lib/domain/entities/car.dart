// 车辆实体（≈ Java 的 POJO/DTO）。
//
// 纯数据类：只描述一辆车有哪些字段，不依赖 Flutter、不依赖数据库。
// 所有字段 final（不可变），需要"改"时用 copyWith 生成新对象——
// Java 对照：类似 Lombok 的 @Value + @With。
//
// 注意 brand+model+roadDate 在数据库层有唯一约束（见 app_database.dart），
// 即同一品牌/型号/上路日期的车只能建一辆。
import '../../core/date/local_date.dart';
import 'powertrain_type.dart';
import 'sync_metadata.dart';

class Car {
  const Car({
    this.id,
    required this.brand,
    required this.model,
    this.powertrainType = PowertrainType.fuel,
    required this.currentMileageKm,
    required this.roadDate,
    this.tankCapacityLiters,
    required this.sync,
  });

  /// 数据库主键（Snowflake 雪花 id，见 core/id/）。新建尚未入库时为 null。
  final int? id;

  /// 品牌，如"丰田"。
  final String brand;

  /// 车型，如"卡罗拉 1.2T"。
  final String model;

  /// 动力类型（燃油/混动/插混/增程/纯电）。添加车辆时由用户选择，
  /// 决定默认保养模板；添加后不可修改（身份字段，同 brand/model），
  /// 因此 copyWith 不开放替换。默认燃油（ADR 0003）；
  /// 生产代码在添加/编辑表单里总是显式传入。
  final PowertrainType powertrainType;

  /// 当前里程（公里）。业务规则：只增不减——
  /// 新增/编辑保养记录时会用 max(当前值, 记录里程) 回写（见 RecordRules）。
  final int currentMileageKm;

  /// 上路日期（无保养记录时的时间进度基线）。只用年月日，不带时分秒。
  final LocalDate roadDate;

  /// 油箱容积（升），车的物理属性。非必填，未填为 null（加油预估的
  /// 加满金额需要它，空态时加油页引导去填）。校验规则见
  /// FuelRules.validateTankCapacity：1–999，最多四位小数；
  /// 写库/恢复备份前由 Repository 统一校验（Car 保持可 const 构造，
  /// 校验不放构造函数里）。
  final double? tankCapacityLiters;

  /// 云同步元数据（为未来同步预留，当前全部为 synced）。
  final SyncMetadata sync;

  /// 复制并替换部分字段（Dart 惯用的"不可变对象更新"方式）。
  /// 只开放里程/容积/sync 的替换——品牌/型号/上路日期是身份字段，
  /// 编辑车辆表单也不允许修改它们。
  Car copyWith({
    int? currentMileageKm,
    double? tankCapacityLiters,
    bool keepCapacity = true,
    SyncMetadata? sync,
  }) {
    return Car(
      id: id,
      brand: brand,
      model: model,
      powertrainType: powertrainType,
      currentMileageKm: currentMileageKm ?? this.currentMileageKm,
      roadDate: roadDate,
      tankCapacityLiters: keepCapacity
          ? (tankCapacityLiters ?? this.tankCapacityLiters)
          : tankCapacityLiters,
      sync: sync ?? this.sync,
    );
  }
}
