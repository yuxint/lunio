# Lunio 正式 v1 实施现状报告

本文是 Flutter 迁移完成后的正式 v1 现状报告。早期 Batch 0-8 的流水式迁移记录已归档为历史背景；当前阅读和后续开发应以本文的现状口径为准。

## 当前结论

- 产品/文档正式版：v1。
- Drift 数据库版本：`schemaVersion = 4`。
- JSON 备份契约：`schemaVersion = 2`。
- 主入口路由：`/reminders`、`/records`、`/me`。
- 当前仓库是本地优先车辆保养 App，不是通用 Flutter demo 或占位壳。

当前已落地：

- 车辆管理和当前应用车辆。
- 车型列表、默认保养项目模板、车辆内保养项目配置。
- 保养记录新增、编辑、删除、按周期/按项目查看。
- 保养提醒进度计算、排序、App 内提醒和系统通知调度。
- 停车倒计时、到点通知和 Android 常驻倒计时通知。
- JSON 备份导出和 replace-import 恢复。
- 清空数据、开发者模式手动日期、浅色/深色/跟随系统主题。
- iOS/Android 原生文件导入导出桥接。
- Android 通知 receiver、boot receiver、exact alarm 权限和通知小图标配置。

当前未包含：

- 账号、登录、云同步和服务端接口。
- 支付、预约、门店、图片附件、OCR 和多设备协作。
- iOS Live Activity、Dynamic Island 和 Widget Extension。
- 正式发布包名、Bundle ID、签名和商店资产。

## 核心业务实现

### 车辆和当前应用车辆

- `cars` 保存品牌、车型、当前里程和上路日期。
- 车辆唯一约束为 `brand + model + roadDate`。
- 当前应用车辆保存在 `app_preferences.appliedCarId`。
- 如果当前应用车辆为空、非法或指向已删除车辆，Repository 会回退到车辆列表第一辆；没有车辆时清空偏好。
- 删除车辆会在事务内清理该车的保养项目、保养记录和记录项目关联。

### 保养项目

- `vehicle_models` 保存可选品牌/车型。
- `vehicle_default_maintenance_items` 保存车型默认保养项目模板。
- `maintenance_items` 保存车辆内实际保养项目。
- 创建车辆时，会按车型默认模板复制一份车辆内保养项目。
- 启用状态、提醒方式、里程间隔、时间间隔和阈值都保存在车辆内项目上。
- 禁用项目不参与提醒和新增记录默认候选，但历史记录仍可引用。
- 删除或禁用项目必须保证该车至少还有一个启用项目。

### 保养记录

- 一条保养记录可包含多个保养项目。
- 同一车辆同一天只能有一条保养记录。
- 同一车辆同一天同一项目只能出现一次。
- 保存记录时会校验项目存在且属于同一车辆。
- 保存记录时，如果记录里程高于车辆当前里程，会抬高车辆当前里程；不会自动回退。
- 新增和编辑记录都是两步流程：先填记录草稿，再确认所选项目的下次提醒间隔。

### 保养提醒和通知

- 提醒页只计算当前应用车辆。
- 提醒计算复用 `MaintenanceRules.progressForItem`。
- 同时开启里程和时间提醒时，取进度百分比更高的一项作为主状态。
- 状态阈值：小于到期阈值为正常，达到到期阈值为到期，达到超期阈值为超期。
- 提醒页展示所有启用项目；通知只取到期和超期项目。
- App 内提醒支持“知道了”和“15 天内不再提醒”。
- 系统通知默认每天本地 09:00 之后按用户设置频率预排。
- 里程更新提醒频率由最近最多 5 个保养日期的平均间隔推导。

### 停车倒计时

- 停车倒计时位于提醒页当前车辆卡片和保养提醒列表之间。
- 状态保存在 `app_preferences.parkingCountdown`，包含 `startedAt` 和 `durationSeconds`。
- 这是全局临时状态，不按车辆隔离，也不进入备份。
- 剩余时间大于 20% 为正常，小于等于 20% 为即将到点，到点后为已超时。
- 倒计时进行中，入口按钮禁用，避免叠加多个倒计时。
- 系统通知开启时，保存倒计时会调度到点提醒。
- Android 额外展示 `lunio_parking_ongoing` 常驻 chronometer 通知。
- 结束倒计时、关闭系统通知、清空数据和恢复备份都需要清理停车通知。

### 日期、主题和偏好

- 所有业务日期使用 `LocalDate`，格式为 `yyyy-MM-dd`。
- 开发者模式开启、`manualDateEnabled=true` 且 `manualDate` 合法时，业务今天来自手动日期。
- `effectiveTodayProvider` 是提醒、车龄、记录默认日期和通知签名的统一今天入口。
- 主题偏好保存在 `app_preferences.themeMode`，支持 `light`、`dark` 和跟随系统。
- `appRouter` 是稳定单例，主题切换不重建路由。

### 备份和恢复

- 导出使用 `BackupPayload(schemaVersion: 2)`。
- 导出包含车辆、默认保养项目、车辆内保养项目和保养记录。
- 导出不包含 `app_preferences`，因此不迁移当前应用车辆、手动日期、主题、通知设置、提醒抑制状态或停车倒计时。
- 恢复入口先确认破坏性操作，再选择 JSON 文件。
- 恢复是 replace-import：在同一事务内先清空当前业务数据，再恢复备份内容。
- 恢复时源车辆 ID 和项目 ID 会映射为新 ID。
- 恢复完成后当前应用车辆写为第一辆恢复出来的车辆。
- 恢复失败时事务回滚，不留下半导入状态。

## 平台状态

### iOS

- Flutter iOS 工程可构建运行。
- 文件导出使用 `UIDocumentPickerViewController`。
- 文件恢复使用系统文档选择器读取 JSON 文本。
- 通知设置跳转通过 `lunio/native_notification_settings` MethodChannel。
- 当前未接入 Live Activity、Dynamic Island 或 Widget Extension。
- 发布前需确认正式 Bundle ID、开发者团队、签名资料、AppIcon 和启动页资产。

### Android

- Android 工程、SDK、模拟器运行和 APK 构建路径已打通。
- 文件导出和恢复通过 `MainActivity.kt` 的 `lunio/native_files` MethodChannel 接入。
- `AndroidManifest.xml` 已包含 scheduled notification receiver、boot receiver、`RECEIVE_BOOT_COMPLETED` 和 `SCHEDULE_EXACT_ALARM`。
- 通知初始化使用 `@drawable/ic_lunio_notification`。
- 停车倒计时包含到点 alarm 通知和 ongoing chronometer 通知。
- 当前只确认过模拟器路径；发布前应补 Android 物理机回归。
- 当前 `applicationId` 和 namespace 还是 `com.example.lunio`，release signing 仍需正式配置。

## 历史验证记录

历史迁移过程曾按 Batch 0-8 分批推进。以下记录只作为回溯依据，不代表当前待办：

- Flutter 静态检查和测试曾多次通过：`flutter analyze`、`flutter test`。
- iOS 模拟器构建曾通过：`flutter build ios --simulator`。
- Android APK 构建曾通过：`flutter build apk`。
- Android 模拟器运行验证覆盖过启动、底部三入口、车辆新增、记录新增、提醒刷新、备份分享、恢复文件选择器。
- Android 停车倒计时验证覆盖过 `lunio_parking_ongoing` 常驻通知、到点 alarm 和结束后的通知/闹钟清理。

后续修改时，以当前代码重新验证为准，不直接引用历史通过结果作为当前通过结论。

## 后续发布前建议

- 确认 iOS 正式 Bundle ID、开发者团队和签名资料。
- 确认 Android 正式 applicationId、namespace 和 release signing config。
- 替换正式 AppIcon、启动页和商店资产。
- 用 Android 13+ 真机复核通知权限、文件选择器、系统分享面板、返回键、键盘遮挡和安全区。
- 发布前重新运行 `flutter analyze`、`flutter test`、`flutter build ios --simulator` 和 `flutter build apk`。
