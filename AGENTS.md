# AGENTS.md

## 项目定位

Lunio 是车辆保养记录 App 的 Flutter 单仓工程，当前可以按正式第一版产品处理。主壳层里包含提醒、记录、我的、车辆管理、保养项目、保养记录、通知、停车倒计时、手动日期、主题切换、备份导入导出等可交互能力。

后续协作时，先把它当作一个本地优先的车辆保养 App 处理，而不是通用 Flutter demo。

## 技术栈

- Flutter / Dart
- Riverpod：依赖注入、偏好与业务数据状态
- go_router：三入口路由，当前路径为 `/reminders`、`/records`、`/me`
- Drift + SQLite：本地数据库、唯一约束、事务、备份恢复
- Material 3 + 自定义 `LunioTokens`：浅色/深色主题 token

不要在没有明确要求时引入新框架、新状态管理、新路由方案或新的 UI 组件库。

## 关键入口

- `lib/main.dart`：App 启动入口。
- `lib/app/lunio_app.dart`：`MaterialApp.router`、主题模式和路由挂载。
- `lib/app/app_router.dart`：GoRouter 配置。`appRouter` 是稳定单例，主题切换时不要重建路由导致跳页。
- `lib/app/providers.dart`：Riverpod provider 总入口，包含数据库、Repository、车辆、当前应用车辆、保养项目、记录、手动日期、主题偏好等。
- `lib/features/shell/app_shell.dart`：主壳层入口，保留三入口页面挂载、底部导航、生命周期监听和提醒通知同步触发。
- `lib/features/shell/reminders/`：提醒页、停车倒计时、保养提醒列表、提醒通知 view data 与调度 helper。
- `lib/features/shell/records/`：记录页、记录筛选、保养记录表单和记录删除相关交互。
- `lib/features/shell/profile/`：我的页、车辆新增/编辑/切换、保养项目管理、备份导入导出、通知设置、手动日期。
- `lib/features/shell/shared/`：shell 内部共享的 modal/dialog/toast、日期选择器、格式化、错误文案和小型 UI 组件。
  - `reminders/parking_countdown.dart`：停车倒计时卡片、表单、时间选择器、保存和清除逻辑。
  - `reminders/reminder_list.dart`：保养提醒列表、提醒行、记录详情 sheet 和进度环。
  - `reminders/reminder_notifications.dart`、`reminders/reminder_dialogs.dart`：提醒 view data、系统通知调度 helper、snooze/ack key、应用内提醒弹窗。
  - `profile/vehicles.dart`：车辆列表、车辆卡片、添加/编辑车辆、车型选择和车辆切换。
  - `profile/maintenance_items.dart`：保养项目 sheet、列表、卡片、项目表单和恢复默认草稿。
  - `profile/settings_data.dart`：备份导入导出、清空数据、通知设置、手动日期和个人中心设置行。
  - `shared/shell_shared.dart`：shell shared barrel；具体实现分别在 `shared_widgets.dart`、`date_picker.dart`、`modal_feedback.dart`、`formatters.dart`、`shell_actions.dart`。
- `lib/core/theme/lunio_tokens.dart`、`lib/core/theme/lunio_theme.dart`：全局视觉 token 和 ThemeData。做全局视觉调整优先改这里。
- `DESIGN.md`：设计 token 与产品 UI 原则。改视觉、颜色、间距、反馈模式时要同步检查，必要时同步更新。

## 目录职责

- `lib/domain/entities/`：领域实体，保持纯 Dart 数据结构与基础校验。
- `lib/domain/rules/`：业务规则，例如保养进度、记录校验、当前应用车辆回退规则。优先把可测试的业务判断放这里。
- `lib/data/database/app_database.dart`：Drift 表结构与数据库连接，当前 `schemaVersion` 为 5。
- `lib/data/database/app_database.g.dart`：Drift 生成文件。改表结构后用 build_runner 生成，不要手写。
- `lib/data/repositories/lunio_repository.dart`：数据库读写、事务、默认数据、备份导入导出恢复。
- `lib/data/backup/backup_codec.dart`：`schemaVersion: 2` JSON 备份契约编码/解码。
- `lib/core/date/`：`LocalDate` 与可手动覆盖的应用日期上下文。
- `lib/core/platform/native_files.dart`：原生文件保存/选择桥接。
- `lib/core/notifications/lunio_notification_service.dart`：系统通知、保养提醒、里程更新提醒和停车倒计时通知。
- `lib/core/platform/native_notification_settings.dart`：原生通知设置跳转桥接。
- `test/domain/`：领域规则测试。
- `test/data/`：数据库、Repository、备份测试。
- `test/widget_test.dart`：主 UI smoke 与关键交互测试。
- `docs/migration/`：迁移与数据库设计资料。
- `docs/prototypes/`：历史原型，只在需要对照产品交互时参考，不要当运行时代码改。

## 数据与契约注意点

- 当前产品/文档口径是正式 v1；这不是数据库或备份契约版本。
- 当前数据库 `schemaVersion` 是 5，备份 JSON `schemaVersion` 是 2。
- 不要随意改 Drift 表字段、唯一约束、偏好 key 或备份 JSON 字段语义；如果必须改，要同时考虑迁移、兼容、测试和文档。
- 重要偏好 key 包括 `appliedCarId`、`developerModeEnabled`、`manualDateEnabled`、`manualDate`、`themeMode`、`systemNotificationsEnabled`、`inAppNotificationsEnabled`、`maintenanceDueEnabled`、`maintenanceDueRepeat`、`parkingCountdown`。不要把展示文案当作稳定标识。
- 删除车辆、恢复备份、切换当前应用车辆都涉及事务和 provider 失效，优先沿用 `LunioRepository` 与 `providers.dart` 里的现有模式。
- 默认车辆模型和默认保养项目通过 Repository bootstrap 写入，避免在 UI 层重复拼业务数据。
- 停车倒计时是临时偏好状态，落在 `app_preferences.parkingCountdown`，不进入 JSON 备份。保存、结束、关闭系统通知、清空数据和恢复备份都要同步考虑通知清理。
- 当前仓库没有 iOS Live Activity / Widget Extension 接线；不要把历史验证过的 Live Activity 方案写成当前已落地能力。

## UI 与交互约定

- 主交互按 shell 子目录拆分；改 UI 前先从 `app_shell.dart` 定位入口，再读 `reminders/`、`records/`、`profile/` 或 `shared/` 的相关局部代码，避免跨区域重构。
- 视觉改动优先走 `LunioTokens` 和 `buildLunioTheme`，不要在页面里散落新的硬编码颜色。
- 改全局视觉、产品原则或 token 时，同步检查 `DESIGN.md`。
- 瞬时成功反馈使用页面内容区内的轻量 toast 风格；不要轻易改回系统底部 `SnackBar`，也不要贴近系统状态栏。
- 车辆/保养类 UI 偏好紧凑、直接、少重复入口。能整行点击就不要再加冗余编辑图标。
- 日期选择器和底部 sheet 要注意纵向空间，优先原地切换内容，避免把下方内容挤出视野。
- 主题切换后要保持当前路由稳定，并在偏好写入和 provider 失效后再显示反馈。
- 停车倒计时位于提醒页当前车辆卡片和保养提醒列表之间；倒计时进行中入口禁用，状态颜色复用保养提醒的 normal/warning/danger 语义。
- Android 通知行为与 iOS 不完全相同：停车倒计时有 ongoing chronometer 通知和到点 alarm 通知，回归时要分别验证调度和取消。

## 修改原则

- 先读现有代码，再改。
- 只改当前任务直接相关内容，不做顺手重构。
- 保持现有目录结构、命名、文案语言和交互方式。
- 不随意重命名文件、类型、方法、字段。
- 不覆盖、回退、删除用户未明确要求处理的改动。
- 注释只写必要信息，避免解释显而易见的代码。
- 搜索优先使用 `rg`。

## 常用命令

```bash
flutter analyze
flutter test
flutter build ios --simulator
dart run build_runner build
```

验证优先级：

- Dart/Flutter 代码改动：先跑 `flutter analyze`。
- 领域规则改动：跑相关 `test/domain/*_test.dart`。
- 数据库、Repository、备份改动：跑相关 `test/data/*_test.dart`。
- UI 交互改动：跑相关 widget test；必要时补充手动启动验证。
- Drift 表结构改动：先运行 `dart run build_runner build` 并检查 `app_database.g.dart`，再顺序跑分析和测试。

这个仓库里测试或生成任务可能受 Flutter startup lock / native asset generation / codesign 临时文件影响，避免同时并行跑多个 Flutter/Dart 生成或测试命令。推荐顺序是 `dart run build_runner build`（仅表结构改动需要）→ `flutter analyze` → 定向 `flutter test ...` → 全量 `flutter test`。

## 汇报格式

最终汇报优先说明：

- 改了什么
- 风险是什么
- 验证了什么

如果有假设、未验证项或因为环境原因没法验证，要直接写明。
