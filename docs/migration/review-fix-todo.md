# Review Fix TODO 归档

本文是早期 Flutter 技术底座 review 修复记录归档，不再表示当前仍有未完成 TODO。当前业务和数据事实以 `docs/prd/business-logic-prd.md`、`docs/migration/current-database-schema.md` 和代码为准。

## 已处理问题

### `LocalDate.parse` 未校验真实日历日期

- 位置：`lib/core/date/local_date.dart`
- 历史问题：旧实现只检查字符串能否回写成 `yyyy-MM-dd`，没有确认年月日是否是真实日历日期。
- 风险：`2026-02-30` 这类日期可能被 Dart `DateTime` 归一化，导致提醒进度、记录日期和导入数据口径偏移。
- 当前结果：`LocalDate.parse` 已反查归一化后的年月日，并覆盖非法日期测试。

### 保养记录可引用不存在或其他车辆的保养项目

- 位置：`lib/data/repositories/lunio_repository.dart`
- 历史问题：保存记录时只对 `itemIds` 去重，未校验项目是否存在、是否属于当前车辆。
- 风险：可能写出孤立记录项，或把 A 车记录关联到 B 车项目。
- 当前结果：Repository 保存记录时会在事务内校验项目存在且属于同一车辆。禁用项目允许被历史记录继续引用。

### 早期备份格式缺少完整语义

- 位置：`lib/data/backup/backup_codec.dart`
- 历史问题：早期备份只覆盖车辆和记录，不能表达保养项目、记录项关系和默认项目。
- 风险：恢复后项目配置和记录项目关系无法自洽。
- 当前结果：当前备份 JSON 契约为 `schemaVersion = 2`，覆盖 `cars`、`defaultMaintenanceItems`、`maintenanceItems` 和 `records`。

注意：当前 `schemaVersion = 2` 备份仍然刻意不包含 `app_preferences`。当前应用车辆、手动日期、主题、通知设置、提醒抑制状态和停车倒计时不随备份迁移。

## 已转为正式能力的旧待办

- 备份恢复 UI、文件导入导出和恢复确认已经落地。
- 删除自定义项目前检查历史记录已经纳入当前项目配置规则。
- 按项目维度查看、编辑和删除保养记录已经纳入当前记录流程。

## 使用方式

本文只用于理解早期 review 背景。后续发现新问题时，不要继续追加到本文；应按当前问题影响范围更新业务 PRD、迁移文档或对应测试。
