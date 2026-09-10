// 提醒行组装层：当前应用车辆 → 提醒列表行（ReminderViewData）的视图模型
// 与组装规则 + 空态分类 + 英雄卡"到期概览"文案。
//
// 在 App 中的位置：从 reminder_notifications.dart 拆出 UI 半边——那边只留
// 系统通知内容组装与数据签名（通知域），本文件是提醒页的数据接缝。
// 消费方：提醒列表（reminder_list.dart）、英雄卡概览（reminder_page.dart）；
// 通知侧经 reminder_notifications.dart 复用同一个 buildReminderRows，
// 保证"界面看到的"和"通知里发的"来自同一次组装规则。
//
// reminderRowsProvider watch 当前应用车辆/项目/记录/有效今天四个上游，
// 英雄卡与列表都消费它——rows 每次数据变化只组装一遍（此前英雄卡与
// 列表各算一遍），空态优先级判断也只有一个出口。
// Java 类比：一个按上游数据自动重算的只读视图对象（Spring 的
// @Cacheable service 方法），widget 只是它的渲染皮。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/date/local_date.dart';
import '../../../core/widgets/lunio_components.dart';
import '../../../domain/entities/car.dart';
import '../../../domain/entities/maintenance_item.dart';
import '../../../domain/entities/maintenance_record.dart';
import '../../../domain/entities/reminder.dart';
import '../../../domain/rules/maintenance_rules.dart';
import '../../../domain/rules/record_rules.dart';
import '../shared/shell_shared.dart';

/// 单个保养项目的提醒展示模型（≈ 前端 ViewModel）：
/// 项目 + 进度 + 最近记录，附展示用 getter（百分比/徽章文案/语义色/详情行）。
class ReminderViewData {
  const ReminderViewData({
    required this.item,
    required this.progress,
    required this.latestRecord,
    this.daysSinceLatest,
    this.kmSinceLatest,
  });

  final MaintenanceItem item;
  final ReminderProgress progress;
  final MaintenanceRecord? latestRecord;

  /// 距上次时间：最近记录 → 今天的天数。无最近记录，或差值为负
  /// （补录乱序，已在 RecordRules 折叠成 null）时为 null，详情弹窗显示占位 —。
  final int? daysSinceLatest;

  /// 距上次里程：车辆当前里程 − 最近记录里程。折叠规则同 [daysSinceLatest]。
  final int? kmSinceLatest;

  String get title => item.name;

  int get displayPercent => MaintenanceRules.displayPercentForThresholds(
    percent: progress.percent,
    notOverdueUpperLimit: item.notOverdueUpperLimit,
    overdueUpperLimit: item.overdueUpperLimit,
  );

  String get percentText => formatPercent(displayPercent);

  LunioStatusTone get tone => progress.status.tone;

  String get badge {
    return switch (progress.status) {
      ReminderStatus.normal => '正常',
      ReminderStatus.warning => '到期',
      ReminderStatus.danger => '超期',
    };
  }

  List<String> get detailTexts {
    final details = <String>[];
    if (item.remindByMileage && progress.mileageRemainingKm != null) {
      details.add(_mileageReminderText(progress.mileageRemainingKm!));
    }
    if (item.remindByTime && progress.daysRemaining != null) {
      details.add(timeReminderText(progress.daysRemaining!));
    }
    if (details.isEmpty) {
      details.add('未设置提醒规则');
    }
    return details;
  }
}

/// 构建提醒列表行：只取启用且有 id 的项目 → 逐项算进度 → 排序。
/// 排序规则：状态越差越靠前（超期>到期>正常）→ 百分比降序 → sortOrder。
List<ReminderViewData> buildReminderRows({
  required Car car,
  required List<MaintenanceItem> items,
  required List<MaintenanceRecord> records,
  required LocalDate today,
}) {
  final rows = <ReminderViewData>[];
  for (final item in items.where((item) => item.enabled && item.id != null)) {
    final latestRecord = RecordRules.latestRecordForItem(
      records: records,
      itemId: item.id!,
    );
    final progress = MaintenanceRules.progressForItem(
      item: item,
      latestRecord: latestRecord,
      currentMileageKm: car.currentMileageKm,
      noHistoryBaselineDate: car.roadDate,
      today: today,
    );
    rows.add(
      ReminderViewData(
        item: item,
        progress: progress,
        latestRecord: latestRecord,
        // 距上次（提醒页参照点 = 今天 / 车辆当前里程），详情弹窗直接读；
        // 无基线或差值为负已在 domain 折叠成 null。
        daysSinceLatest: RecordRules.daysSinceLast(
          baselineRecord: latestRecord,
          untilDate: today,
        ),
        kmSinceLatest: RecordRules.kmSinceLast(
          baselineRecord: latestRecord,
          untilMileageKm: car.currentMileageKm,
        ),
      ),
    );
  }
  rows.sort((left, right) {
    final statusCompare = reminderStatusRank(
      right.progress.status,
    ).compareTo(reminderStatusRank(left.progress.status));
    if (statusCompare != 0) {
      return statusCompare;
    }
    final progressCompare = right.progress.percent.compareTo(
      left.progress.percent,
    );
    if (progressCompare != 0) {
      return progressCompare;
    }
    return left.item.sortOrder.compareTo(right.item.sortOrder);
  });
  return rows;
}

/// 状态排序权重（越大越紧急）。
int reminderStatusRank(ReminderStatus status) {
  return switch (status) {
    ReminderStatus.normal => 0,
    ReminderStatus.warning => 1,
    ReminderStatus.danger => 2,
  };
}

/// 提醒行组装结果：rows 之外附带"还没有任何保养记录"标志。
/// 这个标志不能从 rows 推出来——rows 按启用项目生成，一条记录都没有
/// 时也有行（进度走无历史基线），而"暂无保养记录"空态（与
/// maintenanceNotices 的"没记录不产生提醒"产品约定一致）必须先于
/// "无启用项目"判断。
class ReminderRows {
  const ReminderRows({required this.noRecordsYet, required this.rows});

  /// 当前应用车辆是否一条保养记录都没有。
  final bool noRecordsYet;

  /// 组装好的提醒行（已按 状态→百分比→sortOrder 排序）。
  final List<ReminderViewData> rows;
}

/// 提醒数据就绪后的三种形态（空态优先级单一出口）：
/// 无任何记录 → 无启用项目 → 正常。loading/error 不在其中——
/// 那两个态由调用方对 AsyncValue 做 when 处理。
sealed class ReminderRowsState {
  const ReminderRowsState();
}

/// 没有任何保养记录：不显示提醒行（新车主不轰炸）。
class ReminderRowsNoRecords extends ReminderRowsState {
  const ReminderRowsNoRecords();
}

/// 有记录但没有任何启用项目。
class ReminderRowsNoEnabledItems extends ReminderRowsState {
  const ReminderRowsNoEnabledItems();
}

/// 正常：有可展示的提醒行。
class ReminderRowsData extends ReminderRowsState {
  const ReminderRowsData(this.rows);

  final List<ReminderViewData> rows;
}

/// 空态分类：英雄卡与列表共用的优先级判断
/// （无记录 > 无启用项目 > 有数据），两处 UI 各自把结果映射成自己的文案。
ReminderRowsState classifyReminderRows(ReminderRows board) {
  if (board.noRecordsYet) {
    return const ReminderRowsNoRecords();
  }
  if (board.rows.isEmpty) {
    return const ReminderRowsNoEnabledItems();
  }
  return ReminderRowsData(board.rows);
}

/// 提醒行 provider：watch 当前应用车辆 + 项目 + 记录 + 有效今天四个上游，
/// 数据变化时自动重算。车辆为 null（还没建车）时给空结果——
/// 此时页面也不会渲染英雄卡与列表，这只是让 provider 永不抛错。
final reminderRowsProvider = FutureProvider<ReminderRows>((ref) async {
  final car = await ref.watch(appliedCarProvider.future);
  final items = await ref.watch(appliedCarMaintenanceItemsProvider.future);
  final records = await ref.watch(appliedCarRecordsProvider.future);
  final today = await ref.watch(effectiveTodayProvider.future);
  return ReminderRows(
    noRecordsYet: records.isEmpty,
    rows: car == null
        ? const []
        : buildReminderRows(
            car: car,
            items: items,
            records: records,
            today: today,
          ),
  );
});

/// 英雄卡"到期概览"文案：如"超期 1 / 到期 2"、"全部正常"、"暂无"。
/// 只收 [ReminderRows] 纯数据——loading/error 由页面对 AsyncValue 做
/// when 后才进来（此前本函数直接吃 AsyncValue，Riverpod 异步态泄漏进
/// view-data 接口）。
String dueOverviewText(ReminderRows board) {
  return switch (classifyReminderRows(board)) {
    ReminderRowsNoRecords() => '暂无',
    ReminderRowsNoEnabledItems() => '无项目',
    ReminderRowsData(:final rows) => _overviewForRows(rows),
  };
}

/// 有行时的概览文案：超期/到期计数，全正常给"全部正常"。
String _overviewForRows(List<ReminderViewData> rows) {
  final overdueCount = rows
      .where((row) => row.progress.status == ReminderStatus.danger)
      .length;
  final dueCount = rows
      .where((row) => row.progress.status == ReminderStatus.warning)
      .length;
  if (overdueCount > 0 && dueCount > 0) {
    return '超期 $overdueCount / 到期 $dueCount';
  }
  if (overdueCount > 0) {
    return '超期 $overdueCount';
  }
  if (dueCount > 0) {
    return '到期 $dueCount';
  }
  return '全部正常';
}

// ---- 文件内私有格式化（仅本文件消费的函数不留公共面）----

/// 里程维剩余文案（提醒详情用）。
String _mileageReminderText(int remainingKm) {
  if (remainingKm > 0) {
    return '里程：距离下次约 ${formatNumber(remainingKm)} 公里';
  }
  if (remainingKm == 0) {
    return '里程：已到期';
  }
  return '里程：已超 ${formatNumber(remainingKm.abs())} 公里';
}
