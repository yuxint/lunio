// 车辆实体（≈ Java 的 POJO/DTO）。
//
// 纯数据类：只描述一辆车有哪些字段，不依赖 Flutter、不依赖数据库。
// 所有字段 final（不可变），需要"改"时用 copyWith 生成新对象——
// Java 对照：类似 Lombok 的 @Value + @With。
//
// 注意 brand+model+roadDate 在数据库层有唯一约束（见 app_database.dart），
// 即同一品牌/型号/上路日期的车只能建一辆。
import '../../core/date/local_date.dart';
import 'sync_metadata.dart';

class Car {
  const Car({
    this.id,
    required this.brand,
    required this.model,
    required this.currentMileageKm,
    required this.roadDate,
    required this.sync,
  });

  /// 数据库主键（Snowflake 雪花 id，见 core/id/）。新建尚未入库时为 null。
  final int? id;

  /// 品牌，如"丰田"。
  final String brand;

  /// 车型，如"卡罗拉 1.2T"。
  final String model;

  /// 当前里程（公里）。业务规则：只增不减——
  /// 新增/编辑保养记录时会用 max(当前值, 记录里程) 回写（见 RecordRules）。
  final int currentMileageKm;

  /// 上路日期（无保养记录时的时间进度基线）。只用年月日，不带时分秒。
  final LocalDate roadDate;

  /// 云同步元数据（为未来同步预留，当前全部为 synced）。
  final SyncMetadata sync;

  /// 复制并替换部分字段（Dart 惯用的"不可变对象更新"方式）。
  /// 只开放里程和 sync 的替换——品牌/型号/上路日期是身份字段，
  /// 编辑车辆表单也不允许修改它们。
  Car copyWith({int? currentMileageKm, SyncMetadata? sync}) {
    return Car(
      id: id,
      brand: brand,
      model: model,
      currentMileageKm: currentMileageKm ?? this.currentMileageKm,
      roadDate: roadDate,
      sync: sync ?? this.sync,
    );
  }
}
