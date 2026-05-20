# Review Fix TODO

本文记录当前 Flutter 技术底座代码审查中发现、暂不立即修复的问题。后续统一按优先级拆批处理。

## P1：`LocalDate.parse` 未校验真实日历日期

- 位置：`lib/core/date/local_date.dart`
- 问题：当前 `parse` 只检查字符串能否回写成 `yyyy-MM-dd`，没有确认年月日是否是真实日历日期。
- 影响：例如 `2026-02-30` 会被接受，但 Dart `DateTime` 会把它归一化成其他日期，导致提醒进度、记录日期和导入数据口径偏移。
- 建议修复：
  - `LocalDate.parse` 中构造 `DateTime(year, month, day)` 后，反查 `year/month/day` 是否完全一致。
  - 增加非法日期测试：`2026-02-30`、`2026-13-01`、`2026-00-01`。

## P1：保养记录可引用不存在或其他车辆的保养项目

- 位置：`lib/data/repositories/lunio_repository.dart`
- 问题：`saveMaintenanceRecord` 只对 `itemIds` 去重，然后直接写入 `maintenance_record_items`，未校验项目是否存在、是否属于当前车辆、是否未删除。
- 影响：
  - 可写出孤立记录项。
  - 可把 A 车记录关联到 B 车项目。
  - 后续按项目拆分、提醒计算、自定义项目删除历史检查会失真。
- 建议修复：
  - 在同一个事务里查询所有 `itemIds` 对应的 `maintenance_items`。
  - 要求所有项目存在、`ownerCarId == record.carId`、`deletedAt == null`。
  - 是否要求 `enabled == true` 需要产品确认：历史记录是否允许引用后来禁用的项目。
  - 增加测试：不存在项目、其他车辆项目、重复项目、已删除项目。

## P2：备份格式缺少保养项目和应用偏好

- 位置：`lib/data/backup/backup_codec.dart`
- 问题：当前 `schemaVersion: 1` 只导出 `cars` 和 `records`，没有包含保养项目、记录项关系的完整语义、当前应用车辆、手动日期等偏好。
- 影响：
  - 恢复后记录里的 `itemIds` 无法映射到项目配置。
  - 当前应用车辆与手动日期会丢失。
  - 备份/恢复不能算真正自洽。
- 建议修复：
  - `BackupPayload` 增加 `maintenanceItems`、`preferences`。
  - 记录保留 `itemIds`，但导入时必须校验这些 ID 在备份项目集合内存在且属于同一车辆。
  - 增加完整 round-trip 测试：车辆 + 项目 + 记录 + 当前车辆 + 手动日期。

## 处理顺序建议

1. 先修 `LocalDate.parse`，避免后续测试和导入逻辑建立在错误日期上。
2. 再修 `saveMaintenanceRecord` 引用完整性，保证数据库不会写入脏关联。
3. 最后调整备份 v1 payload，因为备份格式要依赖最终表结构和记录关联策略。
