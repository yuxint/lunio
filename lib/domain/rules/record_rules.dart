// 保养记录校验与派生规则（纯静态工具类）。
//
// 由 Repository 的 4 个保存/更新入口在写库前调用（fail-fast）。
import '../../core/date/local_date.dart';
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

  /// 记录自校验：金额（分）非负、里程非负、至少包含一个项目、
  /// 项目费用（ADR 0010）金额非负且 itemId 必须在 itemIds 内。
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
    final itemIdSet = record.itemIds.toSet();
    for (final cost in record.itemCosts) {
      if (!itemIdSet.contains(cost.itemId)) {
        throw ArgumentError.value(
          cost.itemId,
          'itemCosts.itemId',
          'Item cost references item outside record',
        );
      }
      for (final cents in [
        cost.materialCents,
        cost.laborCents,
        cost.costCents,
      ]) {
        if (cents != null && cents < 0) {
          throw ArgumentError.value(
            cents,
            'itemCosts',
            'Item cost must be non-negative',
          );
        }
      }
    }
  }

  /// 已填项目费用合计（分）：只累加项目费用字段非空的条目（权威值，
  /// 不用材料+工时推导替换）。没有任何项目费用时为 0。
  static int sumItemCostCents(Iterable<RecordItemCost> itemCosts) {
    return itemCosts
        .map((cost) => cost.costCents)
        .whereType<int>()
        .fold(0, (sum, cents) => sum + cents);
  }

  /// 项目费用与"材料费+工时费"是否不一致（红字黄三角的判定，ADR 0010）。
  /// 仅当材料费、工时费都填了且都大于 0、项目费用也填了时才比——
  /// 0 与未填等价（只填一个组成部分时项目费用自由填写，不提示）。
  static bool itemCostMismatch(RecordItemCost cost) {
    final material = cost.materialCents;
    final labor = cost.laborCents;
    final total = cost.costCents;
    if (material == null || material <= 0 || labor == null || labor <= 0) {
      return false;
    }
    return total != null && total != material + labor;
  }

  /// 记录总费用与已填项目费用合计是否不一致（红字黄三角的判定）。
  /// 没有任何项目费用（合计为 0）时不比——简洁模式下总费用是纯手填。
  static bool totalCostMismatch({
    required int totalCostCents,
    required List<RecordItemCost> itemCosts,
  }) {
    final sum = sumItemCostCents(itemCosts);
    return sum > 0 && totalCostCents != sum;
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

  /// 某项目最近一次记录（提醒进度与"距上次"的基线，含当天）。
  /// 同车同项目同日的唯一约束（maintenance_record_items 的
  /// {carId, date, itemId}）保证该项目一天最多一条记录，按日期比较
  /// 即可唯一定位——不存在"同日多条取哪条"的并列问题；
  /// 没有任何含该项目的记录返回 null。
  static MaintenanceRecord? latestRecordForItem({
    required List<MaintenanceRecord> records,
    required int itemId,
  }) {
    MaintenanceRecord? latest;
    for (final record in _recordsForItem(records, itemId)) {
      if (latest == null || record.date.compareTo(latest.date) > 0) {
        latest = record;
      }
    }
    return latest;
  }

  /// 某项目在 [beforeDate] 之前（严格早于，不含当天）的最新一条记录，
  /// 即按项目记录详情里"距上次"的参照点（上一条 → 本条）。
  /// 同车同日唯一约束保证日期相同必为同一条，按日期可唯一定位；
  /// 没有更早的记录（该项目首条）返回 null。
  /// ⚠ [records] 必须传该车全部记录：按年份/项目筛选后的子集会把
  /// 上一条筛掉，导致弹窗误显示占位 —。
  static MaintenanceRecord? previousRecordForItem({
    required List<MaintenanceRecord> records,
    required int itemId,
    required LocalDate beforeDate,
  }) {
    MaintenanceRecord? previous;
    for (final record in _recordsForItem(records, itemId)) {
      if (record.date.compareTo(beforeDate) >= 0) {
        continue;
      }
      if (previous == null || record.date.compareTo(previous.date) > 0) {
        previous = record;
      }
    }
    return previous;
  }

  /// 含 [itemId] 的记录（latest / previous 两个查询共用的过滤）。
  static Iterable<MaintenanceRecord> _recordsForItem(
    List<MaintenanceRecord> records,
    int itemId,
  ) {
    return records.where((record) => record.itemIds.contains(itemId));
  }

  /// 距上次时间（天）：基线记录 → 参照日。CONTEXT.md「距上次（时间）」：
  /// 无基线（该项目首条）或差值为负（补录乱序，负值不参与提醒计算）
  /// 一律折叠成 null——"可算不可算"的判定只在这里做一次，
  /// 调用方与格式化层只需处理 null 与非负值。
  static int? daysSinceLast({
    required MaintenanceRecord? baselineRecord,
    required LocalDate untilDate,
  }) {
    if (baselineRecord == null) {
      return null;
    }
    final days = baselineRecord.date.daysUntil(untilDate);
    return days < 0 ? null : days;
  }

  /// 距上次里程（km）：参照里程 − 基线记录里程。
  /// 折叠规则（无基线 / 负值 → null）与 [daysSinceLast] 相同。
  static int? kmSinceLast({
    required MaintenanceRecord? baselineRecord,
    required int untilMileageKm,
  }) {
    if (baselineRecord == null) {
      return null;
    }
    final km = untilMileageKm - baselineRecord.mileageKm;
    return km < 0 ? null : km;
  }
}
