# v1 数据库表结构

本文描述 Lunio Flutter 迁移第一版 SQLite 表结构。讨论时可以按 MySQL 视角表达，落地时统一转换成 SQLite 口径。

当前 schema 版本为 `1`，已按当前讨论结果定为第一版。

## MySQL 到 SQLite 的转换约定

- MySQL `AUTO_INCREMENT BIGINT/INT PRIMARY KEY` 转为 SQLite `INTEGER PRIMARY KEY AUTOINCREMENT`。
- MySQL `DATETIME` 转为 SQLite `TEXT`，建议存 ISO-8601 字符串。
- 金额字段使用 SQLite `INTEGER`，单位为分，页面层负责转换成元并保留 2 位小数。
- MySQL `BOOLEAN/TINYINT(1)` 转为 SQLite `INTEGER`，`0/1` 表示 false/true。
- MySQL 表注释和字段注释转为 DDL 前后的 `--` 注释。
- 当前不声明数据库外键约束，但字段语义会注明来源表。

## v1 DDL

```sql
-- 车辆表。
-- 删除车辆时采用物理删除，并由业务层同事务删除：
-- 1. maintenance_items 中 cars_id 等于该车辆 id 的数据；
-- 2. maintenance_records 中 car_id 等于该车辆 id 的数据；
-- 3. maintenance_record_items 中 car_id 等于该车辆 id 的数据；
-- 4. app_preferences 中 key='appliedCarId' 且 value 等于该车辆 id 的数据。
-- vehicle_default_maintenance_items 是基础数据，不随车辆删除。
CREATE TABLE cars (
  -- 自增主键。
  id INTEGER PRIMARY KEY AUTOINCREMENT,

  -- 品牌，例如“本田”“日产”。
  brand TEXT NOT NULL,

  -- 车型，例如“22款思域”“22款轩逸”。
  model TEXT NOT NULL,

  -- 当前里程，单位公里。
  current_mileage_km INTEGER NOT NULL,

  -- 上路日期，业务格式 yyyy-MM-dd。
  road_date TEXT NOT NULL,

  -- 云同步预留状态，例如 synced / pendingCreate / pendingUpdate / pendingDelete。
  sync_status TEXT NOT NULL DEFAULT 'synced',

  -- 最后更新时间，ISO-8601 字符串。
  updated_at TEXT NOT NULL,

  -- 云同步/冲突处理预留版本号。
  version INTEGER NOT NULL DEFAULT 1
);

-- 同一品牌 + 车型唯一。
-- brand_model_key 不作为表字段，只作为表达唯一性的索引口径。
CREATE UNIQUE INDEX idx_cars_brand_model
ON cars (brand, model);


-- 车辆默认保养项目基础数据表。
-- 这张表不归属于某一辆用户车辆，删除 cars 时不联动删除。
-- 新增车辆时，用户选择品牌 + 车型后，从本表加载匹配的默认项目列表；
-- 保存车辆时，再把这些默认项目复制插入 maintenance_items。
CREATE TABLE vehicle_default_maintenance_items (
  -- 自增主键。
  id INTEGER PRIMARY KEY AUTOINCREMENT,

  -- 车辆品牌。
  vehicle_brand TEXT NOT NULL,

  -- 车型。
  vehicle_model TEXT NOT NULL,

  -- 项目名称。
  item_name TEXT NOT NULL,

  -- 是否按里程提醒；0=false，1=true。
  remind_by_mileage INTEGER NOT NULL,

  -- 是否按时间提醒；0=false，1=true。
  remind_by_time INTEGER NOT NULL,

  -- 里程提醒间隔，单位公里。
  mileage_interval_km INTEGER,

  -- 时间提醒间隔，单位月。
  time_interval_months INTEGER,

  -- 未超期值上限。
  -- 进度条绿色范围固定为 0 到 not_overdue_upper_limit，默认 100。
  not_overdue_upper_limit REAL NOT NULL DEFAULT 100,

  -- 超期值上限。
  -- 进度条黄色范围为 not_overdue_upper_limit 到 overdue_upper_limit，默认 125。
  -- 大于 overdue_upper_limit 时为红色。
  overdue_upper_limit REAL NOT NULL DEFAULT 125,

  -- 项目排序。
  sort_order INTEGER NOT NULL,

  -- 云同步预留状态，例如 synced / pendingCreate / pendingUpdate / pendingDelete。
  sync_status TEXT NOT NULL DEFAULT 'synced',

  -- 最后更新时间，ISO-8601 字符串。
  updated_at TEXT NOT NULL,

  -- 云同步/冲突处理预留版本号。
  version INTEGER NOT NULL DEFAULT 1
);

-- 按品牌 + 车型加载默认项目列表。
CREATE INDEX idx_default_items_brand_model
ON vehicle_default_maintenance_items (vehicle_brand, vehicle_model);

-- 同一品牌 + 车型 + 项目名称唯一。
-- 注意：如果唯一索引只有 vehicle_brand + vehicle_model，则一个车型只能配置一条默认保养项目。
-- 当前表是一行一个项目，所以这里建议使用 vehicle_brand + vehicle_model + item_name。
CREATE UNIQUE INDEX idx_default_items_brand_model_name
ON vehicle_default_maintenance_items (vehicle_brand, vehicle_model, item_name);


-- 保养项目表。
-- cars_id 来源于 cars.id，但当前不声明数据库外键约束。
-- 默认项目和自定义项目都按用户车辆持久化。
CREATE TABLE maintenance_items (
  -- 自增主键。
  id INTEGER PRIMARY KEY AUTOINCREMENT,

  -- 所属车辆 ID，来源于 cars.id。
  cars_id INTEGER NOT NULL,

  -- 展示名称；不作为跨版本稳定主键。
  name TEXT NOT NULL,

  -- 是否默认项目；0=false，1=true。
  is_default INTEGER NOT NULL,

  -- 是否启用；禁用项目允许被历史记录继续引用，只是在新增记录时不展示。
  enabled INTEGER NOT NULL DEFAULT 1,

  -- 是否按里程提醒；0=false，1=true。
  remind_by_mileage INTEGER NOT NULL,

  -- 是否按时间提醒；0=false，1=true。
  remind_by_time INTEGER NOT NULL,

  -- 里程提醒间隔，单位公里。
  mileage_interval_km INTEGER,

  -- 时间提醒间隔，单位月。
  time_interval_months INTEGER,

  -- 未超期值上限。
  -- 进度条绿色范围固定为 0 到 not_overdue_upper_limit，默认 100。
  not_overdue_upper_limit REAL NOT NULL DEFAULT 100,

  -- 超期值上限。
  -- 进度条黄色范围为 not_overdue_upper_limit 到 overdue_upper_limit，默认 125。
  -- 大于 overdue_upper_limit 时为红色。
  overdue_upper_limit REAL NOT NULL DEFAULT 125,

  -- 同一车辆内的项目排序。
  sort_order INTEGER NOT NULL,

  -- 云同步预留状态，例如 synced / pendingCreate / pendingUpdate / pendingDelete。
  sync_status TEXT NOT NULL DEFAULT 'synced',

  -- 最后更新时间，ISO-8601 字符串。
  updated_at TEXT NOT NULL,

  -- 云同步/冲突处理预留版本号。
  version INTEGER NOT NULL DEFAULT 1
);

-- 同一车辆内项目名称唯一。
CREATE UNIQUE INDEX idx_maintenance_items_cars_name
ON maintenance_items (cars_id, name);


-- 保养记录主表。
-- car_id 来源于 cars.id，但当前不声明数据库外键约束。
-- 删除记录采用物理删除，并由业务层同步删除该记录关联的记录项目。
CREATE TABLE maintenance_records (
  -- 自增主键。
  id INTEGER PRIMARY KEY AUTOINCREMENT,

  -- 所属车辆 ID，来源于 cars.id。
  car_id INTEGER NOT NULL,

  -- 保养日期，业务格式 yyyy-MM-dd。
  date TEXT NOT NULL,

  -- 保养发生时里程，单位公里。
  mileage_km INTEGER NOT NULL,

  -- 费用，单位分。页面层负责转换成元并保留 2 位小数。
  cost_cents INTEGER NOT NULL,

  -- 备注。
  note TEXT,

  -- 云同步预留状态，例如 synced / pendingCreate / pendingUpdate / pendingDelete。
  sync_status TEXT NOT NULL DEFAULT 'synced',

  -- 最后更新时间，ISO-8601 字符串。
  updated_at TEXT NOT NULL,

  -- 云同步/冲突处理预留版本号。
  version INTEGER NOT NULL DEFAULT 1
);

-- 同一车辆同一天只能有一条保养记录。
CREATE UNIQUE INDEX idx_maintenance_records_car_date
ON maintenance_records (car_id, date);


-- 保养记录项目表。
-- 用于表达“一条保养记录包含多个保养项目”。
-- maintenance_record_id 来源于 maintenance_records.id，item_id 来源于 maintenance_items.id。
-- 当前不声明数据库外键约束。
CREATE TABLE maintenance_record_items (
  -- 自增主键。
  id INTEGER PRIMARY KEY AUTOINCREMENT,

  -- 保养记录 ID，来源于 maintenance_records.id。
  maintenance_record_id INTEGER NOT NULL,

  -- 所属车辆 ID，来源于 cars.id。
  -- 这里保留冗余值，用于表达同车同日同项目唯一口径并减少查询 join。
  car_id INTEGER NOT NULL,

  -- 保养项目 ID，来源于 maintenance_items.id。
  item_id INTEGER NOT NULL,

  -- 保养日期，业务格式 yyyy-MM-dd。
  -- 这里按当前讨论结果冗余，用于数据库层建立同车同日同项目唯一索引。
  date TEXT NOT NULL
);

-- 同一车辆同一天同项目只能出现一次。
-- 因为 maintenance_records 已经有 UNIQUE(car_id, date)，
-- 所以该索引也可以覆盖“同一条保养记录内同一项目不能重复”的约束。
CREATE UNIQUE INDEX idx_maintenance_record_items_car_date_item
ON maintenance_record_items (car_id, date, item_id);


-- 应用偏好表。
-- 参与备份，并预留云同步字段。
CREATE TABLE app_preferences (
  -- 自增主键。
  id INTEGER PRIMARY KEY AUTOINCREMENT,

  -- 偏好键，例如 appliedCarId / manualDateEnabled / manualDate。
  key TEXT NOT NULL,

  -- 偏好值。
  -- appliedCarId 的值来源于 cars.id。
  value TEXT,

  -- 云同步预留状态，例如 synced / pendingCreate / pendingUpdate / pendingDelete。
  sync_status TEXT NOT NULL DEFAULT 'synced',

  -- 最后更新时间，ISO-8601 字符串。
  updated_at TEXT NOT NULL,

  -- 云同步/冲突处理预留版本号。
  version INTEGER NOT NULL DEFAULT 1
);

-- 偏好键唯一。
CREATE UNIQUE INDEX idx_app_preferences_key
ON app_preferences (key);
```

## 表结构说明

### `cars`

- `id`：所有业务引用车辆时使用的稳定 ID。
- `brand + model`：通过唯一索引限制同一品牌+车型只能存在一辆车。
- `brandModelKey`：不再作为字段存在。
- 删除车辆：物理删除，关联数据由业务层同事务清理。
- 删除车辆时，`app_preferences` 中 `key='appliedCarId'` 且 `value` 等于该车辆 ID 的数据也要删除。

### `vehicle_default_maintenance_items`

- 这是基础数据表，不归属于用户车辆。
- 删除 `cars` 不会删除这张表的数据。
- 新增车辆时，根据用户选择的 `vehicle_brand + vehicle_model` 加载默认保养项目列表。
- 保存车辆时，把加载并经过用户确认的默认项目复制到 `maintenance_items`。
- 当前建议：
  - 用普通索引 `vehicle_brand + vehicle_model` 支持加载。
  - 用唯一索引 `vehicle_brand + vehicle_model + item_name` 防止同车型下项目名重复。

### `maintenance_items`

- `cars_id`：来源于 `cars.id`。
- `catalog_key`：已删除。
- `not_overdue_upper_limit`：未超期值上限，默认 100。
- `overdue_upper_limit`：超期值上限，默认 125。
- 进度条颜色：
  - 绿色：`0 <= progress < not_overdue_upper_limit`。
  - 黄色：`not_overdue_upper_limit <= progress < overdue_upper_limit`。
  - 红色：`progress >= overdue_upper_limit`。
- 唯一键：`cars_id + name`。
- 禁用项目：允许被历史记录继续引用；新增记录时不显示禁用项目，这是业务逻辑，不放入数据库约束。

### `maintenance_records`

- `car_id`：来源于 `cars.id`。
- `cycleKey`：去掉，不再作为字段。
- 唯一键：`car_id + date`。
- `cost_cents`：使用 `INTEGER`，单位为分；页面层负责转换成元并展示 2 位小数。
- 删除记录：物理删除，关联记录项目由业务层同事务清理。
- 不增加币种字段。

### `maintenance_record_items`

- `maintenance_record_id`：来源于 `maintenance_records.id`，用于支持一条保养记录包含多个项目。
- `car_id`：来源于 `cars.id`，当前保留冗余。
- `item_id`：来源于 `maintenance_items.id`。
- `date`：按当前讨论结果保留冗余，用于数据库层建立 `car_id + date + item_id` 唯一索引。
- `cycleItemKey`：不作为字段保留。
- 不增加 `costShareCents`。

### `app_preferences`

- `id`：自增主键。
- `key`：偏好键，唯一。
- `value`：偏好值。
- `appliedCarId`：值来源于 `cars.id`。
- `sync_status`、`updated_at`、`version`：参与后续云同步和备份。

## 已确认约定

1. `vehicle_default_maintenance_items` 使用普通索引 `vehicle_brand + vehicle_model` 加载默认项目列表，使用唯一索引 `vehicle_brand + vehicle_model + item_name` 防止同车型下项目重复。
2. `maintenance_record_items.date` 保留冗余，保存记录项目时必须与 `maintenance_records.date` 同步写入。
3. `maintenance_record_items` 只保留唯一索引 `car_id + date + item_id`，不再额外建立 `maintenance_record_id + item_id` 唯一索引。
4. 金额字段统一使用 `cost_cents INTEGER`，单位为分，页面层负责展示为元。
5. 当前不声明数据库外键约束，所有关联删除和引用校验由业务层在事务中保证。
