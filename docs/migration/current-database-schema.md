# 当前数据库表结构

本文描述 Lunio 当前的 SQLite/Drift 数据库事实。产品文档版本、数据库
`schemaVersion`、备份 JSON `schemaVersion`、车型目录 asset `schemaVersion`
当前均为 `1`（起点归一，见 docs/adr/0005）。

本文只记录当前代码事实，不记录历史版本演变。事实源是
`lib/data/database/app_database.dart` 和生成文件 `lib/data/database/app_database.g.dart`。

## 版本和升级策略（ADR 0005）

- 当前数据库：`schemaVersion = 1`。
- 只服务全新安装：新装走 `createAll` 建全部表，然后 bootstrap 从 asset
  目录灌入车型目录与默认保养模板。
- 库文件版本与代码不一致（无论升或降）时，`migration` 返回 Drift 的
  `destructiveFallback`：删光全部表再重建。系统不保留任何升级路径。
- 改表纪律：改 Drift 表结构必须把 `schemaVersion` +1（+1 本身就是触发
  删库重建的开关），改完跑 `dart run build_runner build`。
- 正式上线后本策略作废，届时另立 ADR 恢复"版本号 +1 并补升级分支"的纪律。
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
- `catalog_id`：内置车型目录稳定标识，可空；用于 bootstrap 按内置 JSON 新增、更新或删除内置行。
- `brand`：品牌。
- `model`：车型。
- `powertrain_type`：动力类型（见 docs/adr/0003），取值 `fuel`/`hybrid`/`plugIn`/`extended`/`ev`，默认 `fuel`。添加车辆时用户选择，添加后不可改。
- `current_mileage_km`：当前里程，单位公里。
- `road_date`：上路日期，格式 `yyyy-MM-dd`。
- `tank_capacity_liters`：油箱总容积，单位升，可空（添加/编辑车辆时填写，
  非必填，加油预估的加满金额用它计算；1–999、最多四位小数）。
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
- `model`：车型（懂车帝原始车系名，docs/adr/0003）。
- `template`：推荐动力类型，取值同 `cars.powertrain_type`；只在添加向导预选动力 chip 用，不参与默认项目取数。
- `sort_order`：排序值。
- `sync_status`：同步状态，默认 `synced`。
- `updated_at`：最后更新时间。
- `version`：同步/冲突预留版本号，默认 `1`。

约束：

- 主键：`id`。
- 唯一键：`catalog_id`，允许多条空值。
- 唯一键：`brand + model`。

### `vehicle_default_maintenance_items`

默认保养项目模板表。按动力类型分组（docs/adr/0003）：五组共 46 项
（fuel 10、hybrid 11、plugIn 9、extended 9、ev 7，增程组内容同插混组）。
它不归属于某一辆用户车辆；创建车辆或恢复默认配置时，按车的动力类型从这里复制到 `maintenance_items`。

字段：

- `id`：主键。
- `catalog_id`：内置模板稳定标识，可空；格式为 `tpl:<动力类型>:<templateItemId>`（如 `tpl:fuel:engine-oil`），用于 bootstrap 按内置 JSON 新增、更新或删除内置行。
- `powertrain_type`：适配的动力类型，取值同 `cars.powertrain_type`，默认 `fuel`。
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
- 唯一键：`catalog_id`，允许多条空值。
- 唯一键：`powertrain_type + item_name`。

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
- 普通索引：`cars_id`（`idx_maintenance_items_cars_id`，按车查项目）。

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
- 普通索引：`car_id`（`idx_maintenance_records_car_id`，按车拉记录）。

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
- 普通索引：`maintenance_record_id`（`idx_maintenance_record_items_record_id`，
  组装记录项目列表时按记录 id 批量查）。

业务注意：

- Repository 保存记录时会校验项目存在且属于同一车辆。
- 同一车辆同一天同一项目只能出现一次。

### `fuel_predictions`

加油预测设置表（按车辆一条；容积是 `cars` 表的字段）。

字段：

- `id`：主键。
- `car_id`：所属车辆。
- `fuel_percent`：剩余油量百分比（0–100，2% 一档，默认 50；即加满预估
  列表滚动停稳后第一行所在的档位，没有行的车按默认 50 展示）。
- `sync_status`：同步状态，默认 `synced`。
- `updated_at`：最后更新时间。
- `version`：同步/冲突预留版本号，默认 `1`。

约束：

- 主键：`id`。
- 唯一键：`car_id`。

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
- `maintenanceDueRepeat`
- `systemNotificationPermissionRequested`
- `parkingCountdown`
- `fuelPredictionEnabled`（加油预测功能开关，进开发者模式管理）
- `fuelProvince`（加油预测省份，默认 `湖北`）
- `fuelGrade`（加油预测油品编号，默认 `92`）
- `fuelPriceCache`（油价缓存 JSON，临时数据）
- `fuelManualPrices`（手填油价 JSON：`省份\u0000油品code` → 每升价，临时数据）
- `maintenanceReminderSnoozedUntil:{itemId}`
- `maintenanceReminderAcknowledgedOn:{itemId}`
- `mileageUpdateSnoozedUntil:{carId}`
- `mileageUpdateAcknowledgedOn:{carId}`

## 删除和恢复边界

- 删除车辆时，Repository 在事务内删除该车的保养项目、保养记录、记录项目关联、加油预测设置，并清理指向该车的 `appliedCarId`。
- 清空数据会删除 `app_preferences`、记录项、记录、车辆内保养项目、加油预测设置和车辆。
- 清空数据不删除 `vehicle_models` 或 `vehicle_default_maintenance_items`；bootstrap 会按内置 JSON 目录同步车型和默认项目。
- 恢复备份是 replace-import：先清空当前业务数据，再恢复备份内容，失败整体回滚。

## 备份契约边界

当前 JSON 备份契约版本为 `schemaVersion = 1`，由
`lib/data/backup/backup_codec.dart` 编码/解码。解码只认版本 1，其他版本
直接拒绝，不做旧版本字段回退（docs/adr/0005）。

备份导出包含：

- `cars`（含 `powertrainType`；含 `tankCapacityLiters`，可空）
- `maintenanceItems`
- `records`
- `fuelPrediction`（全局加油设置：省份 + 油品编号，用户改过才有值）
- `fuelPredictions`（每车加油预测设置：剩余油量）

备份不包含：

- `app_preferences`
- 当前应用车辆偏好
- 手动日期和开发者模式
- 主题和通知设置
- 提醒延后/确认状态
- 停车倒计时
- 油价缓存与手填油价（临时数据）

恢复备份时，源车辆 ID 和项目 ID 会换成新雪花 ID（事务内维护旧→新对应表）；
恢复完成后当前应用车辆写为第一辆恢复出的车辆。
