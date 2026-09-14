// 记录表单第二步「间隔确认」的收编模块：把间隔输入草稿变成
// "待更新的保养项目实体清单"。
//
// 职责：
//   1. RecordIntervalDraft——第二步单个项目的间隔输入草稿（项目 + 两个
//      controller，预填当前间隔，缺省 5000km / 1 个月）；
//   2. buildItemUpdates——提交清单生成：解析 → 正整数校验（规则在
//      MaintenanceRules.validateIntervals，与保养项目表单共用一份）→
//      间隔没变的项目跳过（不生成 update）→ 有变化的项目按原字段重建
//      为 pendingUpdate 实体。
//
// 在 App 中的位置：只被 records_page.dart 的两步表单第二步使用，
// 页面保留草稿列表持有权、渲染与调用时机，本模块只管输入→实体的
// 转换。≈ Java Web 里表单提交时的 DTO 组装器：控件值进、待写库实体出。
// 「间隔没变不产生 update」的口径在这里；正整数校验的口径在
// MaintenanceRules（单测 test/features/record_interval_updates_test.dart
// 与 test/domain/maintenance_rules_test.dart）。
import 'package:flutter/material.dart';

import '../../../domain/entities/maintenance_item.dart';
import '../../../domain/entities/sync_metadata.dart';
import '../../../domain/rules/maintenance_rules.dart';

/// 第二步单个项目的间隔输入草稿（项目 + 两个 controller，
/// 缺省值 5000km / 1 个月）。dispose 释放 controller。
class RecordIntervalDraft {
  RecordIntervalDraft({required this.item})
    : mileageController = TextEditingController(
        text: item.remindByMileage
            ? (item.mileageIntervalKm ?? 5000).toString()
            : '',
      ),
      monthsController = TextEditingController(
        text: item.remindByTime
            ? (item.timeIntervalMonths ?? 1).toString()
            : '',
      );

  final MaintenanceItem item;
  final TextEditingController mileageController;
  final TextEditingController monthsController;

  void dispose() {
    mileageController.dispose();
    monthsController.dispose();
  }
}

/// [buildItemUpdates] 的结果：校验失败时 [errorText] 非空（此时
/// [updates] 为空）；成功时 [errorText] 为 null，[updates] 是待更新的
/// 项目实体（可能为空——所有项目间隔都没改）。
class RecordIntervalUpdates {
  const RecordIntervalUpdates.error(this.errorText) : updates = const [];
  const RecordIntervalUpdates.of(this.updates) : errorText = null;

  final String? errorText;
  final List<MaintenanceItem> updates;
}

/// 把第二步的间隔输入整理成"待更新的项目实体"列表：
/// 间隔没变的项目跳过（不生成 update）；非法值返回错误文案（带项目名
/// 前缀，文案由 MaintenanceRules.intervalProblemText 生成）。
/// [now] 注入当前时间，供重建实体的 SyncMetadata 使用（测试可固定）。
RecordIntervalUpdates buildItemUpdates({
  required List<RecordIntervalDraft> drafts,
  required DateTime now,
}) {
  final updates = <MaintenanceItem>[];
  for (final draft in drafts) {
    final item = draft.item;
    // 未开启的轴不解析，直接沿用存量值（等于放弃该轴的变更可能）。
    final mileageInterval = item.remindByMileage
        ? int.tryParse(draft.mileageController.text)
        : item.mileageIntervalKm;
    final timeInterval = item.remindByTime
        ? int.tryParse(draft.monthsController.text)
        : item.timeIntervalMonths;

    final problem = MaintenanceRules.validateIntervals(
      remindByMileage: item.remindByMileage,
      mileageIntervalKm: mileageInterval,
      remindByTime: item.remindByTime,
      timeIntervalMonths: timeInterval,
    );
    if (problem != null) {
      return RecordIntervalUpdates.error(
        MaintenanceRules.intervalProblemText(problem, itemName: item.name),
      );
    }
    if (mileageInterval == item.mileageIntervalKm &&
        timeInterval == item.timeIntervalMonths) {
      continue;
    }
    updates.add(
      MaintenanceItem(
        id: item.id,
        carsId: item.carsId,
        name: item.name,
        enabled: item.enabled,
        remindByMileage: item.remindByMileage,
        remindByTime: item.remindByTime,
        mileageIntervalKm: item.remindByMileage ? mileageInterval : null,
        timeIntervalMonths: item.remindByTime ? timeInterval : null,
        notOverdueUpperLimit: item.notOverdueUpperLimit,
        overdueUpperLimit: item.overdueUpperLimit,
        sortOrder: item.sortOrder,
        sync: SyncMetadata(
          status: SyncStatus.pendingUpdate,
          updatedAt: now,
        ),
      ),
    );
  }
  return RecordIntervalUpdates.of(updates);
}
