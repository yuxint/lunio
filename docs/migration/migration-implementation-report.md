# Lunio 迁移实施报告

本文用于持续记录 Flutter 迁移后的功能点、操作步骤、页面交互、数据加载与保存方式。每个批次完成后更新，作为业务审核材料。

## 当前进度

- Batch 0：技术底座收口，已完成。
- Batch 1：设计系统与 App 壳，已完成。
- Batch 2：车辆与当前应用车辆，已完成。
- Batch 3：保养项目配置，已完成。
- Batch 4：保养记录，已完成。
- Batch 5：保养提醒，已完成。
- Batch 6：个人中心与数据能力，已完成。
- Batch 7：iOS 首版打磨，已完成工程验证；发布 Bundle ID 和签名资料待确认。
- Batch 8：Android 补齐，已完成 Android 工具链、APK 构建、模拟器运行和基础交互验证。

## 已落地：技术底座

### 数据库 v1

- 操作步骤：
  1. App 启动后初始化 Drift/SQLite 数据库。
  2. 数据表按 `schemaVersion: 1` 创建。
  3. Repository 作为业务入口读写数据库。
- 页面交互：
  - 当前阶段没有直接暴露数据库管理页面。
  - 后续车辆、项目、记录、个人中心页面都会通过 Repository 间接访问数据。
- 数据加载：
  - 车辆从 `cars` 加载。
  - 车辆默认保养项目从 `vehicle_default_maintenance_items` 按品牌 + 车型加载。
  - 车辆保养项目从 `maintenance_items` 按车辆加载。
  - 保养记录由 `maintenance_records` + `maintenance_record_items` 组合加载。
  - 应用偏好从 `app_preferences` 按 `key` 加载。
- 数据保存：
  - 主键统一由 SQLite `INTEGER PRIMARY KEY AUTOINCREMENT` 生成。
  - 日期统一保存为 `yyyy-MM-dd`。
  - 金额统一保存为 `cost_cents`，单位分。
  - 删除车辆时，业务层在同一事务物理删除车辆、车辆保养项目、保养记录、记录项目，并清理对应 `appliedCarId`。

### 保养记录保存规则

- 操作步骤：
  1. 调用 `saveMaintenanceRecord`。
  2. 校验日期、里程、费用、项目列表。
  3. 对项目 ID 去重。
  4. 校验所有项目存在且属于同一辆车。
  5. 写入 `maintenance_records`。
  6. 写入 `maintenance_record_items`。
  7. 如果记录里程大于车辆当前里程，则抬高 `cars.current_mileage_km`。
- 页面交互：
  - 提醒页和记录页右下角提供“新增保养记录”入口。
  - 新增/编辑表单已在 Batch 4 接入。
- 数据加载：
  - 新增记录时应加载当前应用车辆下已启用保养项目。
  - 编辑历史记录时允许继续引用已禁用项目。
- 数据保存：
  - 同一车辆同一天只有一条记录。
  - 同一车辆同一天同一项目只能出现一次。
  - 车辆里程只允许被更大的记录里程抬高，不回退。

### 保养提醒计算

- 操作步骤：
  1. 读取当前应用车辆。
  2. 读取该车辆保养项目。
  3. 为每个项目查找最近保养记录。
  4. 同时计算里程进度和时间进度。
  5. 取较高进度作为项目状态。
- 页面交互：
  - Batch 1 提醒页展示静态结构预览。
  - Batch 5 接入真实提醒数据、排序和空状态。
- 数据加载：
  - 有历史记录时，使用最近记录作为计算基准。
  - 无历史记录时，使用车辆上路日期和 0 里程作为计算基准。
  - 所有“今天”逻辑通过 `AppDateContext`，支持后续手动日期。
- 数据保存：
  - 提醒计算本身不保存数据。
  - 手动日期开关和日期后续保存到 `app_preferences`。

### 备份与恢复 v1

- 操作步骤：
  1. 导出时从数据库读取车辆、默认项目、保养项目、保养记录和偏好。
  2. 编码为 `schemaVersion: 1` JSON payload。
  3. 恢复时先校验 schema 版本和引用关系。
  4. 校验通过后，在事务内清空本地数据并写入备份数据。
- 页面交互：
  - Batch 1 “我的”页展示备份与恢复入口占位。
  - Batch 6 接入文件导出、文件导入、恢复确认和失败提示。
- 数据加载：
  - 导出读取 `cars`、`vehicle_default_maintenance_items`、`maintenance_items`、`maintenance_records`、`maintenance_record_items`、`app_preferences`。
- 数据保存：
  - 恢复时保留备份中的显式 ID。
  - 恢复前校验记录项目必须存在且属于记录车辆。
  - `appliedCarId` 必须为空或指向备份内存在的车辆。
  - 恢复失败时不得留下半写入数据。

## 已落地：设计系统与 App 壳

### 公共组件

- 操作步骤：
  1. App 使用 `buildLunioTheme()` 初始化统一主题。
  2. 页面优先使用 `LunioPage`、`LunioCard`、`LunioHeroCard`、`LunioStatusBadge`、`LunioSegmentedControl`、`LunioPrimaryButton`、`LunioSecondaryButton`、`LunioIconButton`。
- 页面交互：
  - 顶部标题区统一展示标题、说明和右侧操作。
  - 卡片统一白色表面、20px 圆角和轻阴影。
  - 主要按钮使用绿色，次要按钮使用浅色表面。
  - 状态标签支持正常、将到期、已超期三种语义色。
- 数据加载：
  - 公共组件不直接加载业务数据。
  - 业务页面负责把 Repository 数据转换成组件展示模型。
- 数据保存：
  - 公共组件不直接保存业务数据。
  - 表单类组件后续只负责输入值，保存动作交给功能模块。

### 三个主入口

- 操作步骤：
  1. App 默认进入 `/reminders`。
  2. 底部导航可切换 `/reminders`、`/records`、`/me`。
  3. 提醒页和记录页展示右下角“新增保养记录”入口。
- 页面交互：
  - `保养提醒`：展示当前车辆 Hero 卡、三个提醒行状态样式、车辆切换入口。
  - `保养记录`：展示按周期/按项目分段控件，可在页面内切换预览结构。
  - `我的`：展示当前应用车辆、数据备份、数据恢复、手动日期入口。
  - `新增保养记录`：打开真实表单，选择日期、里程、费用、项目和备注。
- 数据加载：
  - 当前 Batch 1 页面仍使用静态预览数据。
  - Batch 2 起逐步接入真实车辆上下文和 Repository 数据。
- 数据保存：
  - 当前 Batch 1 不写业务数据。
  - “保存占位”只展示 Toast，不调用 Repository。

## 已落地：车辆与当前应用车辆

### 车辆列表

- 操作步骤：
  1. 进入“我的”页。
  2. 页面读取车辆列表。
  3. 展示每辆车的品牌、车型、当前里程、上路日期。
  4. 当前应用车辆显示“当前”状态标签。
- 页面交互：
  - “我的”页顶部右侧提供新增车辆按钮。
  - 每辆车提供“设为当前车辆”和“删除车辆”图标按钮。
  - 没有车辆时显示空状态卡片和“新增车辆”按钮。
- 数据加载：
  - `carsProvider` 通过 Repository 从 `cars` 加载车辆列表。
  - `app_preferences.appliedCarId` 加载当前应用车辆。
  - 如果 `appliedCarId` 失效，自动回退到第一辆可用车辆并写回偏好。
- 数据保存：
  - 切换当前车辆时写入 `app_preferences` 的 `appliedCarId`。

### 编辑车辆

- 操作步骤：
  1. 在“我的”页点击车辆行的编辑按钮。
  2. 在底部弹层查看品牌车型。
  3. 修改当前里程或上路日期。
  4. 点击“保存车辆”。
- 页面交互：
  - 编辑车辆沿用底部弹层。
  - 当前阶段品牌车型在编辑时不可切换，避免触发“是否重建默认保养项目”的未定业务。
  - 当前里程仅允许输入数字。
  - 上路日期按 `yyyy-MM-dd` 校验。
  - 保存成功后关闭弹层并显示 Toast。
- 数据加载：
  - 编辑入口使用车辆列表中已加载的 `Car`。
- 数据保存：
  - 更新 `cars.current_mileage_km`、`cars.road_date` 和同步元数据。
  - 不改动该车辆已有 `maintenance_items`。

### 新增车辆

- 操作步骤：
  1. 点击“新增车辆”。
  2. 在底部弹层选择品牌车型。
  3. 输入当前里程和上路日期。
  4. 点击“保存车辆”。
  5. Repository 先确保默认保养项目基础数据存在。
  6. 保存车辆，并按品牌 + 车型复制默认项目到该车辆。
  7. 如果当前还没有应用车辆，则把新车设为当前应用车辆。
- 页面交互：
  - 新增车辆使用底部弹层。
  - 当前支持“本田 22款思域”和“日产 22款轩逸”两个车型选项，作为首批基础数据验证入口。
  - 当前里程仅允许输入数字。
  - 上路日期按 `yyyy-MM-dd` 校验。
  - 保存成功后关闭弹层并显示 Toast。
- 数据加载：
  - 默认项目从 `vehicle_default_maintenance_items` 按 `vehicle_brand + vehicle_model` 加载。
  - 页面提交前不直接读取默认项目明细，复制逻辑由 Repository 负责。
- 数据保存：
  - 车辆写入 `cars`。
  - 默认项目复制写入 `maintenance_items`，`cars_id` 使用新车辆 ID。
  - 第一辆车自动写入 `app_preferences.appliedCarId`。

### 删除车辆

- 操作步骤：
  1. 在“我的”页点击车辆行的删除按钮。
  2. 弹出确认框。
  3. 用户确认后删除车辆。
  4. Repository 同事务删除该车保养项目、保养记录、记录项目。
  5. 如果删除的是当前应用车辆，则回退到剩余第一辆车；如果没有剩余车辆，则删除 `appliedCarId` 偏好。
- 页面交互：
  - 删除车辆必须确认。
  - 删除成功后显示 Toast。
- 数据加载：
  - 删除后刷新车辆列表和当前应用车辆 Provider。
- 数据保存：
  - 物理删除 `cars` 及关联 `maintenance_items`、`maintenance_records`、`maintenance_record_items`。
  - 更新或删除 `app_preferences.appliedCarId`。

## 已落地：保养项目配置

### 项目列表

- 操作步骤：
  1. 进入“我的”页。
  2. 点击“保养项目配置”。
  3. 页面读取当前应用车辆。
  4. 页面按排序展示当前车辆的保养项目。
- 页面交互：
  - 项目配置使用底部弹层。
  - 每个项目展示名称、启用状态、默认/自定义标记、提醒规则和阈值。
  - 当前无车辆时提示先新增车辆。
- 数据加载：
  - `appliedCarMaintenanceItemsProvider` 先读取当前应用车辆，再按 `cars_id` 从 `maintenance_items` 加载。
- 数据保存：
  - 查看列表不保存数据。

### 新增自定义项目

- 操作步骤：
  1. 在保养项目配置弹层点击“新增项目”。
  2. 输入项目名称。
  3. 选择按里程提醒、按时间提醒或两者同时提醒。
  4. 输入里程间隔、时间间隔、未超期值上限、超期值上限。
  5. 选择是否启用。
  6. 点击“保存项目”。
- 页面交互：
  - 新增项目使用二级底部弹层。
  - 至少选择一种提醒方式。
  - 启用状态默认开启。
  - 保存成功后关闭弹层并显示 Toast。
- 数据加载：
  - 新增时使用当前应用车辆 ID。
- 数据保存：
  - 写入 `maintenance_items`。
  - `is_default=false`。
  - `cars_id` 使用当前应用车辆 ID。
  - 同车项目名称唯一由数据库约束保证。

### 编辑项目

- 操作步骤：
  1. 在项目卡片点击“编辑”。
  2. 修改提醒方式、间隔、阈值或启用状态。
  3. 点击“保存项目”。
- 页面交互：
  - 编辑项目使用二级底部弹层。
  - 默认项目名称不可编辑，只能调整提醒参数和启用状态。
  - 自定义项目允许编辑名称。
- 数据加载：
  - 编辑入口使用项目列表已加载的 `MaintenanceItem`。
- 数据保存：
  - 更新 `maintenance_items` 的名称、启用状态、提醒方式、间隔、阈值、排序和同步元数据。
  - 禁用项目允许被历史记录继续引用。
  - 禁用后不会在新增记录项目选择中展示。

### 启用与禁用

- 操作步骤：
  1. 在项目卡片点击“启用”或“禁用”。
  2. Repository 校验是否允许变更。
  3. 成功后刷新项目列表。
- 页面交互：
  - 启用状态通过状态标签展示。
  - 操作失败时使用 Toast 展示原因。
- 数据加载：
  - 校验时读取当前车辆其他启用项目。
- 数据保存：
  - 更新 `maintenance_items.enabled`。
  - 至少保留一个启用项目；不能把当前车辆最后一个启用项目禁用。

### 删除自定义项目

- 操作步骤：
  1. 在自定义项目卡片点击“删除”。
  2. 弹出确认框。
  3. 用户确认后，Repository 检查历史记录引用。
  4. 无历史记录时删除项目。
- 页面交互：
  - 默认项目不展示删除按钮。
  - 删除自定义项目必须确认。
  - 删除失败时使用 Toast 展示原因。
- 数据加载：
  - 删除前从 `maintenance_record_items` 检查是否存在 `item_id` 引用。
- 数据保存：
  - 无历史记录的自定义项目物理删除。
  - 有历史记录的自定义项目不能删除。
  - 删除启用项目时仍需满足“至少保留一个启用项目”。

## 已落地：保养记录

### 新增记录

- 操作步骤：
  1. 从提醒页或记录页点击右下角“+”。
  2. App 等待当前应用车辆和项目列表加载完成。
  3. 在底部弹层输入保养日期、保养里程、费用和备注。
  4. 从当前车辆启用项目中选择至少一个保养项目。
  5. 点击“保存记录”。
- 页面交互：
  - 新增记录使用底部弹层。
  - 没有当前车辆时提示先新增车辆。
  - 没有可用项目时提示先配置可用保养项目。
  - 保存成功后关闭弹层并显示 Toast。
- 数据加载：
  - 当前应用车辆来自 `app_preferences.appliedCarId`。
  - 项目选择来自当前车辆启用的 `maintenance_items`。
- 数据保存：
  - 写入 `maintenance_records`。
  - 写入 `maintenance_record_items`，保存 `maintenance_record_id + car_id + item_id + date`。
  - 同车同日唯一由数据库约束保证。
  - 同车同日同项目唯一由数据库约束保证。
  - 保存后车辆当前里程只允许上升，不回退。

### 记录列表

- 操作步骤：
  1. 进入“保养记录”页。
  2. App 读取当前应用车辆。
  3. App 加载该车辆的保养记录和项目列表。
  4. 默认按周期展示。
- 页面交互：
  - 记录页支持“按周期 / 按项目”分段切换。
  - 按周期展示日期、里程、费用、项目名称和备注。
  - 按项目拆分展示每个项目对应的记录行。
  - 无记录时展示空状态。
- 数据加载：
  - 记录从 `maintenance_records` 按 `car_id` 倒序加载。
  - 记录项目从 `maintenance_record_items` 按记录 ID 批量加载。
  - 项目名称从当前车辆 `maintenance_items` 映射。
- 数据保存：
  - 查看列表不保存数据。

### 编辑记录

- 操作步骤：
  1. 在按周期记录卡片点击“编辑”。
  2. 在底部弹层修改日期、里程、费用、备注或项目。
  3. 点击“保存记录”。
- 页面交互：
  - 编辑记录复用新增记录表单。
  - 已禁用但被当前历史记录引用的项目仍会显示并可保留。
- 数据加载：
  - 编辑入口使用列表中已加载的 `MaintenanceRecord`。
  - 表单加载当前车辆全部项目，并保留当前记录已引用项目。
- 数据保存：
  - 更新 `maintenance_records`。
  - 删除旧的 `maintenance_record_items` 后重新写入当前项目集合。
  - 车辆当前里程只允许被更大的记录里程抬高。

### 删除记录

- 操作步骤：
  1. 在按周期记录卡片点击“删除”。
  2. 弹出确认框。
  3. 用户确认后删除记录。
- 页面交互：
  - 删除记录必须确认。
  - 删除成功后刷新列表并显示 Toast。
- 数据加载：
  - 删除入口使用列表中已加载的记录 ID。
- 数据保存：
  - 事务内先删除 `maintenance_record_items`。
  - 再删除 `maintenance_records`。
  - 删除历史记录不会回退车辆当前里程。

## 已落地：保养提醒

### 提醒列表

- 操作步骤：
  1. 进入提醒页。
  2. 自动读取当前应用车辆。
  3. 计算所有启用项目提醒进度。
  4. 按紧急程度展示。
- 页面交互：
  - 当前车辆始终在页面顶部可见。
  - 正常、将到期、已超期使用统一卡片结构和语义色。
  - 顶部车辆卡片展示当前里程和最紧急项目状态。
  - 每个项目卡片展示项目名称、百分比、状态标签和计算口径说明。
  - 无车辆时展示新增车辆空状态。
  - 无启用项目时提示去“我的”配置保养项目。
- 数据加载：
  - 当前车辆来自 `app_preferences.appliedCarId`。
  - 提醒项目来自当前车辆已启用的 `maintenance_items`。
  - 最近记录来自当前车辆 `maintenance_records` 和 `maintenance_record_items`。
  - 今天日期来自 `AppDateContext`，后续可接入手动日期偏好。
- 数据保存：
  - 提醒页不直接保存数据。

### 提醒进度

- 操作步骤：
  1. 对每个启用项目查找包含该项目的最近保养记录。
  2. 有历史记录时，以最近记录日期和里程作为基准。
  3. 无历史记录时，以车辆上路日期和 0 里程作为基准。
  4. 同时计算里程进度和时间进度。
  5. 取较高进度作为最终提醒百分比。
- 页面交互：
  - 百分比以圆形进度显示。
  - 进度原因展示为“按里程计算”或“按时间计算”。
  - 已超出上限时圆形进度封顶展示，百分比文本保留真实值。
- 数据加载：
  - 当前车辆里程用于里程进度。
  - 项目自身的未超期上限和超期上限用于状态判断。
- 数据保存：
  - 提醒计算不写库。

### 提醒排序

- 操作步骤：
  1. 先按状态紧急程度排序：已超期、将到期、正常。
  2. 同状态内按进度百分比从高到低排序。
  3. 同进度时按项目排序字段排序。
- 页面交互：
  - 用户进入提醒页即可优先看到最需要处理的项目。
  - 车辆卡片“最紧急”指标与列表第一项保持一致。
- 数据加载：
  - 排序使用内存中的提醒计算结果。
- 数据保存：
  - 排序不写库。

## 已落地：个人中心与数据能力

### 数据备份

- 操作步骤：
  1. 进入“我的”页。
  2. 点击“数据备份”。
  3. App 从数据库导出 `schemaVersion: 1` payload。
  4. App 把 JSON 写入应用文档目录下的 `lunio-backup-yyyy-MM-dd.json`。
  5. 页面展示文件路径和备份 JSON。
- 页面交互：
  - 备份结果使用底部弹层展示。
  - 文件路径可选中复制。
  - JSON 内容可查看，并提供“复制 JSON”按钮。
  - iOS 上提供“分享文件”按钮，调用系统分享面板导出 JSON 文件。
  - 导出失败时使用 Toast 展示原因。
- 数据加载：
  - 导出读取 `cars`、`vehicle_default_maintenance_items`、`maintenance_items`、`maintenance_records`、`maintenance_record_items`、`app_preferences`。
- 数据保存：
  - 备份操作不改业务表。
  - 生成的 JSON 文件保存到应用文档目录。

### 数据恢复

- 操作步骤：
  1. 进入“我的”页。
  2. 点击“数据恢复”。
  3. 在底部弹层粘贴 `schemaVersion: 1` 备份 JSON。
  4. 点击“恢复数据”。
  5. App 先解码 JSON，再校验引用关系。
  6. 校验通过后用事务替换本地数据。
- 页面交互：
  - 恢复使用底部弹层。
  - iOS 上提供“选择 JSON 文件”按钮，调用系统文件选择器读取 JSON。
  - JSON 为空时直接提示。
  - 导入失败时保留弹层并展示错误，不替换原数据。
  - 恢复成功后关闭弹层并显示 Toast。
- 数据加载：
  - 输入来自用户粘贴的 JSON。
  - 校验车辆、项目、记录和偏好引用。
- 数据保存：
  - 恢复数据使用事务。
  - 恢复成功后刷新车辆、当前车辆、项目、记录和偏好 Provider。
  - 恢复失败时不留下半写入数据。

### 清空数据

- 操作步骤：
  1. 进入“我的”页。
  2. 点击“清空数据”。
  3. 确认后清空本地数据。
- 页面交互：
  - 清空前必须二次确认。
  - 成功后显示 Toast。
- 数据加载：
  - 清空操作不依赖页面预加载数据。
- 数据保存：
  - 事务内清空车辆、保养项目、保养记录、记录项目、默认项目基础数据和偏好。
  - 清空后刷新全局 Provider；默认保养项目会在后续启动/加载时重新初始化。

### 手动日期

- 操作步骤：
  1. 进入“我的”页。
  2. 点击“手动日期”。
  3. 开启或关闭手动日期。
  4. 开启时输入 `yyyy-MM-dd` 日期。
  5. 点击“保存日期”。
- 页面交互：
  - 手动日期使用底部弹层。
  - 开启后显示日期输入框。
  - 日期格式错误时在弹层内提示。
  - 保存成功后关闭弹层并显示 Toast。
- 数据加载：
  - “我的”页从 `app_preferences.manualDateEnabled` 和 `app_preferences.manualDate` 加载当前状态。
  - 提醒页通过 `effectiveTodayProvider` 读取手动日期；未开启时回退系统日期。
- 数据保存：
  - 开启时写入 `manualDateEnabled=true` 和 `manualDate=yyyy-MM-dd`。
  - 关闭时写入 `manualDateEnabled=false` 并删除 `manualDate`。
  - 手动日期会影响提醒计算中的“今天”。

## 已落地：iOS 首版打磨

### iOS 运行级链路

- 操作步骤：
  1. 启动 iPhone 17 Pro 模拟器。
  2. 构建并运行 `Runner`。
  3. 首屏进入“保养提醒”。
  4. 新增默认车辆。
  5. 新增一条机油保养记录。
  6. 切换到“保养记录”，验证按周期和按项目展示。
  7. 切换到“我的”，验证车辆、备份、恢复、清空、手动日期入口。
- 页面交互：
  - 底部三入口在 iOS 模拟器可切换。
  - 新增车辆和新增记录底部弹层可打开、保存并刷新页面。
  - 记录页“按周期 / 按项目”分段控件可点击切换。
  - “我的”页功能卡片已暴露为 iOS 语义按钮，避免只被识别为静态文本。
- 数据加载：
  - 使用当前 SQLite v1 数据契约。
  - 当前应用车辆、项目、记录、偏好均来自本地数据库。
- 数据保存：
  - 新增车辆写入 `cars`，并复制默认项目到 `maintenance_items`。
  - 新增记录写入 `maintenance_records` 和 `maintenance_record_items`。

### iOS 文件导入导出

- 操作步骤：
  1. 在“我的”页点击“数据备份”。
  2. App 生成 JSON 文件。
  3. 点击“分享文件”。
  4. iOS 打开系统分享面板。
  5. 在“数据恢复”中点击“选择 JSON 文件”。
  6. iOS 打开系统文件选择器。
- 页面交互：
  - 分享面板显示 `lunio-backup-yyyy-MM-dd.json`。
  - 文件选择器从系统“文件”界面选择 JSON。
  - 仍保留复制 JSON 和粘贴 JSON 作为跨平台兜底。
- 数据加载：
  - 文件选择器读取用户选择文件的 UTF-8 文本。
- 数据保存：
  - 分享文件不改业务数据。
  - 导入 JSON 仍走 Batch 6 的恢复事务。

### iOS 工程配置检查

- 操作步骤：
  1. 检查 `Info.plist`。
  2. 检查 AppIcon 和 LaunchScreen 资源是否存在。
  3. 使用模拟器 Debug 构建验证工程可编译运行。
- 页面交互：
  - 当前按浅色模式实现，未单独适配暗色模式。
- 数据加载：
  - 工程配置不加载业务数据。
- 数据保存：
  - 工程配置不写业务数据。
- 发布备注：
  - 当前 `CFBundleDisplayName` 为 `Lunio`。
  - 当前 Bundle ID 仍是 `com.example.lunio`，发布前需要你确认正式 Bundle ID、开发者团队和签名资料。
  - AppIcon 和 LaunchScreen 使用 Flutter 默认资源，正式视觉资产后续可替换。

## 平台补齐功能清单

### Batch 8：Android 补齐

- 操作步骤：
  1. 补齐 Android SDK / Android Studio toolchain。
  2. 检查 Android 文件导入导出、返回键、系统导航栏、安全区和键盘遮挡。
  3. 完成 Android 构建和基础真机测试。
- 页面交互：
  - 保持与 iOS 同一套 Flutter UI 和设计 token。
- 数据加载：
  - 使用同一套 Drift/SQLite Repository。
- 数据保存：
  - 使用同一套 SQLite v1 数据契约。
- 已落地的离线适配：
  - `android/app/src/main/kotlin/com/example/lunio/MainActivity.kt` 已接入 `lunio/native_files` MethodChannel。
  - Android 备份分享调用系统分享面板，以 JSON 文本方式分享备份内容。
  - Android 数据恢复调用系统文件选择器读取 JSON 文本。
- 当前状态：
  - Android Flutter 工程已存在。
  - `android/app/build.gradle.kts` 当前 `applicationId` 仍是 `com.example.lunio`，发布前需与你确认正式包名。
  - `android/app/src/main/AndroidManifest.xml` 已使用 `adjustResize`。
  - 当前机器已配置 Android SDK `/Users/tanxin/Library/Android/sdk`，`cmdline-tools/latest/bin/sdkmanager` 和 `avdmanager` 可用。
  - `flutter doctor -v` 已确认 Android toolchain 通过，Android licenses 已接受。
  - 已安装 Android 36 Google APIs arm64 system image，并创建 `lunio_api36` AVD。
  - SQLite native asset 已改为 `source: source`，使用仓库内 `third_party/sqlite/sqlite3.c`。
  - `third_party/sqlite/sqlite3.c` 和 `sqlite3.h` 来自 SQLite 官方 `sqlite-autoconf-3530000.tar.gz`，版本 3.53.0。
  - Android release APK 构建通过，产物为 `build/app/outputs/flutter-apk/app-release.apk`，大小 58.3MB。
  - Android 模拟器运行验证通过：启动后数据库正常加载，没有 `libsqlite3.so` not found。
  - Android 基础交互验证通过：提醒页、记录页、我的页、车辆新增、记录新增、备份分享、恢复文件选择器。
  - 当前仍未做真实 Android 物理机验证；发布前建议用至少一台目标 Android 真机复核文件选择器、系统分享面板、返回键、键盘遮挡和安全区。

## 验证记录

- Batch 0：
  - `flutter analyze` 通过。
  - `flutter test` 通过。
  - `flutter build ios --simulator` 通过。
- Batch 1：
  - `flutter analyze` 通过。
  - `flutter test` 通过。
  - `flutter build ios --simulator` 通过。
  - 运行级截图验证未执行：当前没有已启动的 iOS Simulator。
- Batch 2：
  - `flutter analyze` 通过。
  - `flutter test` 通过。
  - `flutter build ios --simulator` 通过。
  - 运行级截图验证未执行：当前没有已启动的 iOS Simulator。
- Batch 3：
  - `flutter analyze` 通过。
  - `flutter test` 通过。
  - `flutter build ios --simulator` 通过。
  - 运行级截图验证未执行：当前没有已启动的 iOS Simulator。
- Batch 4：
  - `flutter analyze` 通过。
  - `flutter test` 通过。
  - `flutter build ios --simulator` 通过。
  - 运行级截图验证未执行：当前没有已启动的 iOS Simulator。
- Batch 5：
  - `flutter analyze` 通过。
  - `flutter test` 通过。
  - `flutter build ios --simulator` 通过。
  - 运行级截图验证未执行：当前没有已启动的 iOS Simulator。
- Batch 6：
  - `flutter analyze` 通过。
  - `flutter test` 通过。
  - `flutter build ios --simulator` 通过。
  - 运行级截图验证未执行：当前没有已启动的 iOS Simulator。
- Batch 7：
  - `flutter analyze` 通过。
  - `flutter test` 通过。
  - `flutter build ios --simulator` 通过。
  - `build_run_sim` 通过，运行设备为 iPhone 17 Pro 模拟器。
  - 运行级检查通过：新增车辆、新增记录、提醒刷新、记录页按周期/按项目切换、我的页入口、备份分享面板、恢复文件选择器。
  - 截图留存：
    - `/var/folders/v3/t9yx1x5x129c7_49qs9ynsjc0000gn/T/screenshot_optimized_120100ad-107f-40fe-8dc5-9ccd28f014d1.jpg`
    - `/var/folders/v3/t9yx1x5x129c7_49qs9ynsjc0000gn/T/screenshot_optimized_564ba9c4-c53d-487d-bdc9-c568bf69860a.jpg`
    - `/var/folders/v3/t9yx1x5x129c7_49qs9ynsjc0000gn/T/screenshot_optimized_b0b97406-36c7-4086-a09f-d311d8ac33ac.jpg`
- Batch 8：
  - `flutter doctor -v` Android toolchain 通过：Android SDK `/Users/tanxin/Library/Android/sdk`，licenses 已接受。
  - `flutter emulators` 可发现 `lunio_api36` Android AVD。
  - 已下载 SQLite 官方 `sqlite-autoconf-3530000.tar.gz`，并把 `sqlite3.c`、`sqlite3.h` 放入 `third_party/sqlite/`。
  - `pubspec.yaml` 已配置 `hooks.user_defines.sqlite3.source: source`，路径为 `third_party/sqlite/sqlite3.c`。
  - `flutter analyze` 通过。
  - `flutter test` 通过，共 46 项测试。
  - `flutter build ios --simulator` 通过，确认 SQLite 本地源码配置未破坏 iOS 模拟器构建。
  - `flutter build apk` 通过，产物为 `build/app/outputs/flutter-apk/app-release.apk`，大小 58.3MB。
  - `adb install -r build/app/outputs/flutter-apk/app-release.apk` 通过。
  - Android AVD `lunio_api36` 运行验证通过：App 启动后数据库正常加载。
  - Android 页面交互验证通过：底部三入口切换、车辆新增、记录新增、提醒刷新、备份 JSON 生成、系统分享面板、恢复文件选择器。
  - 截图留存：
    - `/private/tmp/lunio_android_after_sqlite_source.png`
    - `/private/tmp/lunio_android_after_save_car.png`
    - `/private/tmp/lunio_android_records.png`
    - `/private/tmp/lunio_android_after_save_record.png`
    - `/private/tmp/lunio_android_system_share.png`
    - `/private/tmp/lunio_android_file_picker_open.png`
  - 未执行 Android 物理机验证：当前只覆盖 Android 模拟器。
