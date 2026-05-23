# Review Fix TODO

本文记录 Flutter 技术底座代码审查中发现的问题及处理状态。

## 已在 Batch 0 处理：`LocalDate.parse` 未校验真实日历日期

- 位置：`lib/core/date/local_date.dart`
- 问题：当前 `parse` 只检查字符串能否回写成 `yyyy-MM-dd`，没有确认年月日是否是真实日历日期。
- 影响：例如 `2026-02-30` 会被接受，但 Dart `DateTime` 会把它归一化成其他日期，导致提醒进度、记录日期和导入数据口径偏移。
- 处理结果：
  - `LocalDate.parse` 已反查 `DateTime` 归一化后的年月日。
  - 已增加非法日期测试：`2026-02-30`、`2026-13-01`、`2026-00-01`。

## 已在 Batch 0 处理：保养记录可引用不存在或其他车辆的保养项目

- 位置：`lib/data/repositories/lunio_repository.dart`
- 问题：`saveMaintenanceRecord` 只对 `itemIds` 去重，然后直接写入 `maintenance_record_items`，未校验项目是否存在、是否属于当前车辆、是否未删除。
- 影响：
  - 可写出孤立记录项。
  - 可把 A 车记录关联到 B 车项目。
  - 后续按项目拆分、提醒计算、自定义项目删除历史检查会失真。
- 处理结果：
  - `saveMaintenanceRecord` 已在同一事务内查询所有项目。
  - 要求所有项目存在且 `carsId == record.carId`。
  - 禁用项目允许被历史记录继续引用；新增记录不展示禁用项目属于 UI/业务入口规则，不在 Repository 中硬拦截。
  - 已增加不存在项目、其他车辆项目测试。

## 已在 Batch 0 处理：备份格式缺少保养项目和应用偏好

- 位置：`lib/data/backup/backup_codec.dart`
- 问题：当前 `schemaVersion: 1` 只导出 `cars` 和 `records`，没有包含保养项目、记录项关系的完整语义、当前应用车辆、手动日期等偏好。
- 影响：
  - 恢复后记录里的 `itemIds` 无法映射到项目配置。
  - 当前应用车辆与手动日期会丢失。
  - 备份/恢复不能算真正自洽。
- 处理结果：
  - `BackupPayload` 已覆盖车辆、默认项目、保养项目、记录和偏好。
  - Repository 已增加导出/恢复事务入口。
  - 恢复前会校验车辆、项目、记录引用关系，失败时事务回滚。
  - 已增加备份 codec round-trip 和 Repository 恢复测试。

## 后续仍需覆盖

1. 备份恢复的 UI 入口和文件导入导出能力仍在 Batch 6。
2. 删除自定义项目前检查历史记录仍在 Batch 3。
3. 按项目拆单编辑/删除仍在 Batch 4。
