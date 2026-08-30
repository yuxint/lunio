// 保养记录校验与派生规则（纯静态工具类）。
//
// 由 Repository 的 4 个保存/更新入口在写库前调用（fail-fast）。
import '../entities/maintenance_record.dart';

class RecordRules {
  const RecordRules._();

  /// 项目 id 列表保序去重（Set.add 返回 false 表示已存在，天然去重器）。
  /// 保存/更新记录、备份恢复都会调用。
  static List<int> uniqueItemIds(List<int> itemIds) {
    final result = <int>[];
    final seen = <int>{};
    for (final id in itemIds) {
      if (seen.add(id)) {
        result.add(id);
      }
    }
    return result;
  }

  /// 记录自校验：金额（分）非负、里程非负、至少包含一个项目。
  /// 失败抛 ArgumentError（≈ IllegalArgumentException），UI 翻译成中文提示。
  static void validateRecord(MaintenanceRecord record) {
    if (record.costCents < 0) {
      throw ArgumentError.value(
        record.costCents,
        'costCents',
        'Cost must be non-negative',
      );
    }
    if (record.mileageKm < 0) {
      throw ArgumentError.value(
        record.mileageKm,
        'mileageKm',
        'Mileage must be non-negative',
      );
    }
    if (uniqueItemIds(record.itemIds).isEmpty) {
      throw ArgumentError.value(
        record.itemIds,
        'itemIds',
        'Record must contain items',
      );
    }
  }

  /// 车辆里程"只增不减"规则：新/编辑记录触发车辆里程同步时，
  /// 取 max(当前里程, 记录里程)。防止编辑旧记录把车里程改小。
  static int mileageAfterRecord({
    required int currentMileageKm,
    required int recordMileageKm,
  }) {
    return recordMileageKm > currentMileageKm
        ? recordMileageKm
        : currentMileageKm;
  }
}
