# 当前数据库表结构草案

本文描述当前 Flutter 技术底座里的 Drift/SQLite 表结构，作为后续讨论和调整依据。当前 schema 版本为 `1`，尚未冻结。

## 总体原则

- 本地优先，后续预留云同步。
- 业务日期使用 `yyyy-MM-dd` 字符串。
- 展示名称不作为稳定主键。
- 车辆、项目、记录必须按车辆隔离。
- 当前表结构还缺少外键约束和部分唯一约束，需在 Batch 0 讨论后补齐。

## `cars`

车辆表。

| 字段 | 类型 | 约束 | 说明 |
| --- | --- | --- | --- |
| `id` | text | primary key | 稳定车辆 ID |
| `brand` | text | not null | 品牌 |
| `model` | text | not null | 车型 |
| `brandModelKey` | text | unique | 当前用于同一品牌+车型唯一 |
| `currentMileageKm` | integer | not null | 当前里程，单位公里 |
| `roadDate` | text | not null | 上路日期，`yyyy-MM-dd` |
| `syncStatus` | text | default `synced` | 同步预留状态 |
| `updatedAt` | datetime | not null | 最后更新时间 |
| `deletedAt` | datetime | nullable | 软删除预留 |
| `version` | integer | default `1` | 同步/冲突预留版本 |

待讨论：

- `brandModelKey` 是否应长期保留唯一，还是未来允许同品牌同车型多辆车并引入车牌/昵称区分。
- 删除车辆是物理删除还是软删除；当前 Repository 是物理删除关联数据。

## `maintenance_items`

保养项目表。默认项目和自定义项目都按车辆持久化。

| 字段 | 类型 | 约束 | 说明 |
| --- | --- | --- | --- |
| `id` | text | primary key | 稳定项目 ID |
| `ownerCarId` | text | not null | 所属车辆 ID |
| `name` | text | not null | 展示名称 |
| `isDefault` | boolean | not null | 是否默认项目 |
| `enabled` | boolean | default `true` | 是否启用 |
| `catalogKey` | text | nullable | 默认项目稳定业务键 |
| `remindByMileage` | boolean | not null | 是否按里程提醒 |
| `remindByTime` | boolean | not null | 是否按时间提醒 |
| `mileageIntervalKm` | integer | nullable | 里程提醒间隔 |
| `timeIntervalMonths` | integer | nullable | 时间提醒间隔 |
| `warningThresholdPercent` | integer | default `100` | 黄色阈值 |
| `dangerThresholdPercent` | integer | default `125` | 红色阈值 |
| `sortOrder` | integer | not null | 排序 |
| `syncStatus` | text | default `synced` | 同步预留状态 |
| `updatedAt` | datetime | not null | 最后更新时间 |
| `deletedAt` | datetime | nullable | 软删除预留 |
| `version` | integer | default `1` | 同步/冲突预留版本 |

待讨论：

- 同一车辆内是否用唯一约束限制 `name` 不重复。
- 默认项目是否用唯一约束限制 `ownerCarId + catalogKey` 不重复。
- 禁用项目是否允许被历史记录继续引用。
- 是否需要单独的 `item_kind` 或 `source` 字段替代 `isDefault`。

## `maintenance_records`

保养记录主表。一条记录表示某车某天一次保养周期。

| 字段 | 类型 | 约束 | 说明 |
| --- | --- | --- | --- |
| `id` | text | primary key | 稳定记录 ID |
| `carId` | text | not null | 所属车辆 ID |
| `date` | text | not null | 保养日期，`yyyy-MM-dd` |
| `cycleKey` | text | unique | 当前用于同车同日唯一，格式 `carId::date` |
| `mileageKm` | integer | not null | 保养发生时里程 |
| `costCents` | integer | not null | 费用，单位分 |
| `note` | text | nullable | 备注 |
| `syncStatus` | text | default `synced` | 同步预留状态 |
| `updatedAt` | datetime | not null | 最后更新时间 |
| `deletedAt` | datetime | nullable | 软删除预留 |
| `version` | integer | default `1` | 同步/冲突预留版本 |

待讨论：

- 是否保留冗余 `cycleKey` 字段，还是改为数据库联合唯一索引 `carId + date`。
- `costCents` 是否足够，是否需要币种字段。
- 删除记录是否物理删除，还是为同步保留软删除。

## `maintenance_record_items`

保养记录与保养项目的关联表，用于支持一条记录多个项目和按项目拆分查看。

| 字段 | 类型 | 约束 | 说明 |
| --- | --- | --- | --- |
| `id` | text | primary key | 当前格式 `${recordId}::${itemId}` |
| `recordId` | text | not null | 记录 ID |
| `carId` | text | not null | 冗余车辆 ID，便于唯一约束和查询 |
| `itemId` | text | not null | 项目 ID |
| `date` | text | not null | 冗余日期 |
| `cycleItemKey` | text | unique | 当前用于同车同日同项目唯一，格式 `carId::date::itemId` |

待讨论：

- 是否保留冗余 `date` 和 `cycleItemKey`，还是用 join + 联合唯一索引。
- 是否增加外键：`recordId -> maintenance_records.id`、`itemId -> maintenance_items.id`。
- 是否需要 `costShareCents` 支持单项目拆分费用；当前没有。

## `app_preferences`

轻量偏好表。

| 字段 | 类型 | 约束 | 说明 |
| --- | --- | --- | --- |
| `key` | text | primary key | 偏好键 |
| `value` | text | nullable | 偏好值 |

当前已使用或计划使用的 key：

- `appliedCarId`：当前应用车辆 ID。
- `manualDateEnabled`：是否启用手动日期。
- `manualDate`：手动日期，`yyyy-MM-dd`。

待讨论：

- 是否保留 key-value 表，还是改成单行 `app_settings` 表。
- 如果后续云同步，偏好是否参与备份和同步。

## 当前建议调整方向

1. 优先补真实外键和联合唯一索引，减少依赖冗余 key 字段维护一致性。
2. 备份 v1 应至少覆盖：车辆、项目、记录、记录项目、当前应用车辆、手动日期。
3. 同步预留字段可以保留，但首版所有业务查询都应默认过滤 `deletedAt == null`。
4. 是否支持同品牌同车型多车，需要尽早决定；这会影响 `cars.brandModelKey` 和新增车辆流程。
