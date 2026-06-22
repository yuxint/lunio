# 当前数据库表结构

本文描述 Lunio 正式 v1 文档口径下的当前 SQLite/Drift 数据库事实。产品文档版本是 v1；数据库版本不是 v1，当前 Drift `schemaVersion` 为 `4`。

本文只记录当前代码事实，不定义未来迁移方案。事实源是 `lib/data/database/app_database.dart` 和生成文件 `lib/data/database/app_database.g.dart`。

## 版本和迁移策略

- 当前数据库：`schemaVersion = 4`。
- schema 1 升级到 2 时，现有表会被删除并重建。
- schema 2 升级到 3 时，迁移 `maintenance_items`。
- schema 3 升级到 4 时，迁移 `cars`。
- 当前代码没有声明数据库外键约束；关联完整性由 Repository 在事务中校验和维护。

## 类型约定

- 主键使用 SQLite `INTEGER`，由代码显式写入或通过 `_nextId()` 生成。
- 业务日期保存为 `TEXT`，格式为 `yyyy-MM-dd`。
- 同步更新时间保存为 ISO-8601 `TEXT`。
- 金额保存为 `INTEGER`，单位为分。
- 布尔值由 Drift `BoolColumn` 映射到 SQLite 整数语义。

## 表结构

### `cars`

车辆表。

字段：

- `id`：主键。
- `brand`：品牌。
- `model`：车型。
- `current_mileage_km`：当前里程，单位公里。
- `road_date`：上路日期，格式 `yyyy-MM-dd`。
- `sync_status`：同步状态，默认 `synced`。
- `updated_at`：最后更新时间。
- `version`：同步/冲突预留版本号，默认 `1`。

约束：

- 主键：`id`。
- 唯一键：`brand + model + road_date`。

### `vehicle_models`

车型列表表。用于新增车辆时的品牌/车型选项和 bootstrap。

字段：

- `id`：主键。
- `brand`：品牌。
- `model`：车型。
- `sort_order`：排序值。
- `sync_status`：同步状态，默认 `synced`。
- `updated_at`：最后更新时间。
- `version`：同步/冲突预留版本号，默认 `1`。

约束：

- 主键：`id`。
- 唯一键：`brand + model`。

### `vehicle_default_maintenance_items`

车型默认保养项目模板表。它不归属于某一辆用户车辆；创建车辆或恢复默认配置时，会从这里复制到 `maintenance_items`。

字段：

- `id`：主键。
- `vehicle_brand`：车辆品牌。
- `vehicle_model`：车型。
- `item_name`：项目名称。
- `remind_by_mileage`：是否按里程提醒。
- `remind_by_time`：是否按时间提醒。
- `mileage_interval_km`：里程提醒间隔，单位公里，可空。
- `time_interval_months`：时间提醒间隔，单位月，可空。
- `not_overdue_upper_limit`：到期阈值，默认 `100`。
- `overdue_upper_limit`：超期阈值，默认 `125`。
- `sort_order`：排序值。
- `sync_status`：同步状态，默认 `synced`。
- `updated_at`：最后更新时间。
- `version`：同步/冲突预留版本号，默认 `1`。

约束：

- 主键：`id`。
- 唯一键：`vehicle_brand + vehicle_model + item_name`。

### `maintenance_items`

车辆内实际保养项目表。默认项目和用户自定义项目都落在这里，按车辆隔离。

字段：

- `id`：主键。
- `cars_id`：所属车辆 ID，来源于 `cars.id`。
- `name`：项目名称。
- `enabled`：是否启用，默认 `true`。
- `remind_by_mileage`：是否按里程提醒。
- `remind_by_time`：是否按时间提醒。
- `mileage_interval_km`：里程提醒间隔，单位公里，可空。
- `time_interval_months`：时间提醒间隔，单位月，可空。
- `not_overdue_upper_limit`：到期阈值，默认 `100`。
- `overdue_upper_limit`：超期阈值，默认 `125`。
- `sort_order`：排序值。
- `sync_status`：同步状态，默认 `synced`。
- `updated_at`：最后更新时间。
- `version`：同步/冲突预留版本号，默认 `1`。

约束：

- 主键：`id`。
- 唯一键：`cars_id + name`。

业务注意：

- 禁用项目允许被历史记录继续引用，但不参与提醒和新增记录默认候选。
- 删除或禁用项目时，Repository/UI 必须保证该车仍至少有一个启用项目。
- 有历史记录关联的项目不能删除。

### `maintenance_records`

保养记录主表。

字段：

- `id`：主键。
- `car_id`：所属车辆 ID，来源于 `cars.id`。
- `date`：保养日期，格式 `yyyy-MM-dd`。
- `mileage_km`：保养发生时里程，单位公里。
- `cost_cents`：费用，单位分。
- `note`：备注，可空。
- `sync_status`：同步状态，默认 `synced`。
- `updated_at`：最后更新时间。
- `version`：同步/冲突预留版本号，默认 `1`。

约束：

- 主键：`id`。
- 唯一键：`car_id + date`。

业务注意：

- 同一车辆同一天只能有一条保养记录。
- 保存记录时，如果记录里程高于车辆当前里程，会抬高车辆当前里程；不会因为删除或编辑记录而回退。

### `maintenance_record_items`

保养记录和保养项目关联表，用于表达一条记录包含多个项目。

字段：

- `id`：主键。
- `maintenance_record_id`：保养记录 ID，来源于 `maintenance_records.id`。
- `car_id`：所属车辆 ID，冗余保存。
- `item_id`：保养项目 ID，来源于 `maintenance_items.id`。
- `date`：保养日期，冗余保存，格式 `yyyy-MM-dd`。

约束：

- 主键：`id`。
- 唯一键：`car_id + date + item_id`。

业务注意：

- Repository 保存记录时会校验项目存在且属于同一车辆。
- 同一车辆同一天同一项目只能出现一次。

### `app_preferences`

应用偏好表。用于当前应用车辆、手动日期、主题、通知设置、提醒抑制和停车倒计时等本地状态。

字段：

- `id`：主键。
- `key`：偏好键。
- `value`：偏好值，可空。
- `sync_status`：同步状态，默认 `synced`。
- `updated_at`：最后更新时间。
- `version`：同步/冲突预留版本号，默认 `1`。

约束：

- 主键：`id`。
- 唯一键：`key`。

重要 key：

- `appliedCarId`
- `developerModeEnabled`
- `manualDateEnabled`
- `manualDate`
- `themeMode`
- `systemNotificationsEnabled`
- `inAppNotificationsEnabled`
- `maintenanceDueEnabled`
- `maintenanceDueRepeat`
- `systemNotificationPermissionRequested`
- `parkingCountdown`
- `maintenanceReminderSnoozedUntil:{itemId}`
- `maintenanceReminderAcknowledgedOn:{itemId}`
- `mileageUpdateSnoozedUntil:{carId}`
- `mileageUpdateAcknowledgedOn:{carId}`

## 删除和恢复边界

- 删除车辆时，Repository 在事务内删除该车的保养项目、保养记录、记录项目关联，并清理指向该车的 `appliedCarId`。
- 清空数据会删除 `app_preferences`、记录项、记录、车辆内保养项目和车辆。
- 清空数据不删除 `vehicle_models` 或 `vehicle_default_maintenance_items`；bootstrap 会按内置 JSON 模板补齐车型和默认项目。
- 恢复备份是 replace-import：先清空当前业务数据，再恢复备份内容，失败整体回滚。

## 备份契约边界

当前 JSON 备份契约版本为 `schemaVersion = 2`，由 `lib/data/backup/backup_codec.dart` 编码/解码。

备份导出包含：

- `cars`
- `maintenanceItems`
- `records`

备份不包含：

- `app_preferences`
- 当前应用车辆偏好
- 手动日期和开发者模式
- 主题和通知设置
- 提醒延后/确认状态
- 停车倒计时

恢复备份时，源车辆 ID 和项目 ID 会映射为新 ID；恢复完成后当前应用车辆写为第一辆恢复出的车辆。
