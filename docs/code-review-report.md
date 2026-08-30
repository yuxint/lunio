# Lunio 代码审查报告

> 审查日期：2026-08-25 · 审查范围：`lib/` 全部 43 个手写 Dart 文件（约 12,800 行，不含生成文件 `app_database.g.dart`）、`test/`、`android/`、`ios/`、`docs/`
>
> **本轮只记录问题，未修改任何代码行为**（同期完成的代码注释改动已通过 `flutter analyze` + 全量 130 个测试验证零行为变更）。
>
> 配套文档：`docs/operations-manual.md`（UI 操作 ↔ 代码对照手册）。报告中的行号基于本次注释后的代码。

---

## 目录

1. [给 Java 开发者的概念对照速查](#1-给-java-开发者的概念对照速查)
2. [工程结构总览](#2-工程结构总览)
3. [分层与架构评估](#3-分层与架构评估)
4. [问题清单（按严重度）](#4-问题清单)
5. [UI / 工具 / 组件复用评估](#5-复用评估)
6. [业务逻辑合理性](#6-业务逻辑合理性)
7. [测试覆盖评估](#7-测试覆盖评估)
8. [总体结论与修复优先级建议](#8-总体结论与修复优先级建议)

---

## 1. 给 Java 开发者的概念对照速查

读 Dart/Flutter 代码前先过一遍这张表，绝大多数语法就"翻译"过来了：

| Dart / Flutter | Java 对照 | 说明 |
|---|---|---|
| `main()` / `runApp()` | `main()` / `SpringApplication.run()` | `main` 可为 async |
| `Future<T>` / `async` / `await` | `CompletableFuture<T>` / 链式调用 | await ≈ 非阻塞的 `.get()` |
| `Widget` / `build()` | 组件（JSP/Thymeleaf 模板）/ 渲染方法 | build 会被框架反复调用，必须无副作用 |
| `StatefulWidget` + `setState` | 有状态的 ViewModel + 手动触发刷新 | setState ≈ 通知 UI 重渲染 |
| `StatelessWidget` | 纯函数组件 | 数据从构造参数进 |
| Riverpod `Provider` | Spring 单例 Bean | `lib/app/providers.dart` ≈ JavaConfig |
| Riverpod `FutureProvider` | @Async + 结果缓存的 Bean | `ref.invalidate()` ≈ 逐出缓存 |
| `ref.watch(x)` / `ref.read(x)` | 注入并订阅 / 注入一次 | read 不订阅变化 |
| Drift | MyBatis-Generator / JPA | 表用 Dart 类声明，`build_runner` 生成类型安全查询代码；`database.transaction(closure)` ≈ `@Transactional`（闭包抛异常自动回滚） |
| `MethodChannel` | 跨进程 RPC / JNI | Dart ↔ iOS(Swift) / Android(Kotlin) 原生通信 |
| `part 'x.g.dart'` | 一个类拆多文件 | 生成代码并入当前库 |
| `extension X on Y` | 给 final 类加静态方法 | 无法继承时的"补方法"语法 |
| `..` 级联 / `?.` / `!` | Builder 链 / Optional 安全调用 / 断言非空 | `!` 若为 null 会抛异常 |
| 顶层函数 / `_xxx` | static 工具方法 / private | 下划线前缀 = 库内私有 |
| `catch (_) {}` | `catch (Exception e) {}` 不处理 | 静默吞异常 |

本仓库特有约定（详见 `lib/app/providers.dart` 文件头注释）：

- **手动失效模式**：Repository 写库后**不刷缓存**，由 UI 调用 `invalidateXxxProviders(ref)` 逐出 FutureProvider 缓存触发重新查库。漏调会导致跨页面数据陈旧。
- **日期双轨**：业务"今天"用 `effectiveTodayProvider`（手动日期 ?? 系统今天）；停车倒计时和系统通知调度时刻用真实时钟。
- **两个版本号**：数据库 `schemaVersion = 5`（`lib/data/database/app_database.dart:224`）≠ 备份 JSON `schemaVersion = 2`（`lib/data/backup/backup_codec.dart`），独立演进。

---

## 2. 工程结构总览

```
lib/                                # 约 12,800 行手写代码（43 个文件）
├── main.dart                       # 启动入口（38 行）
├── app/                            # ── 装配层（≈ Spring 配置类）
│   ├── app_router.dart             #   go_router 三入口路由 + 全局单例
│   ├── lunio_app.dart              #   MaterialApp 挂载（主题/路由）
│   └── providers.dart              #   Riverpod 容器（全部 Provider + invalidate 助手）
├── core/                           # ── 基础设施（与业务无关）
│   ├── date/                       #   LocalDate、手动日期上下文
│   ├── id/                         #   雪花 id（+ 遗留 UUID 生成器）
│   ├── notifications/              #   系统通知服务（单例，359 行）
│   ├── platform/                   #   3 个 MethodChannel 原生桥
│   ├── theme/                      #   LunioTokens + ThemeData
│   └── widgets/                    #   通用基础组件（按钮/卡片/分段控件…）
├── domain/                         # ── 领域层（纯 Dart，无 Flutter/DB 依赖）
│   ├── entities/                   #   9 个实体（≈ POJO/DTO）
│   └── rules/                      #   4 组业务规则（≈ Service 静态方法）
└── data/                           # ── 数据层
    ├── database/app_database.dart  #   7 张表 + 迁移 + 惰性连接
    ├── repositories/               #   唯一 Repository（1548 行，≈ Service+DAO）
    ├── backup/backup_codec.dart    #   备份 JSON 编解码
    └── bootstrap/                  #   内置车型目录 asset 解析
features/shell/                     # ── UI 层
    ├── app_shell.dart              #   主壳（646 行）：三 tab + 通知同步引擎
    ├── reminders/                  #   提醒页 5 文件（含停车倒计时、提醒计算 view 层）
    ├── records/records_page.dart   #   记录页（列表/筛选/两步表单/删除）
    ├── profile/                    #   我的页 4 文件（车辆/项目/备份/设置）
    └── shared/                     #   shell 内共享（modal/toast/日期选择器/格式化）

test/                               # 10 个文件：domain/data/通知/60 条 widget 测试
android/ ios/                       # 原生：MainActivity.kt（3 个 channel）、SceneDelegate.swift
docs/                               # prd（当前权威）、migration、prototypes（历史）
```

依赖方向整体正确：`features → domain ← data → domain`，`core` 被各层引用；`domain` 零反向依赖（最好的层）。

---

## 3. 分层与架构评估

对照标准分层（Controller → Service → DAO → DTO）：

| 层 | 对应 | 评价 |
|---|---|---|
| `features/shell` | Controller + View | **良**。页面按 feature 分目录，交互全部走 sheet/dialog 组件化；业务规则不在 UI 里重复实现（都调 domain/rules）。 |
| `app/providers.dart` | DI 配置 | **良**。Provider 依赖图清晰、集中声明；缺点是全部全局常驻（无 autoDispose），靠手动 invalidate 刷新。 |
| `domain/entities` + `rules` | DTO + Service（纯逻辑） | **优**。零依赖、可单测、测试覆盖扎实。 |
| `data/repositories` | Service + DAO | **中**。功能完备、事务使用总体正确，但 1548 行单类承担所有表的读写（内聚性过高），且夹杂面向用户的中文文案。 |
| `core` | 基础设施 | **良**。通知服务封装完整、token 化主题做得规范。 |

### 扩展性

**好的方面**：新增车辆字段/保养项目字段的改动路径清晰（entity → 表 → repository 映射 → provider 自动带出）；sync 元数据三字段（status/updatedAt/version）已落库，为云同步预留了增量协议基础；主题 token 化让全局视觉改动收敛到一处。

**受限的方面**：

- Repository 单类无拆分（车辆/项目/记录/偏好/备份全部混在一个文件），后续表增多会持续膨胀。
- 通知同步逻辑（签名比对、权限链、调度）全部内嵌在 `AppShell` 这个 UI 组件里（`lib/features/shell/app_shell.dart:244-505`），既不可复用也难以单测——这是扩展性上最值得重构的一块。
- 错误处理靠"异常消息字符串匹配"翻译（`lib/features/shell/shared/formatters.dart` 的 `friendlyError`），没有自定义异常类型；新增错误时要同时改 Repository 抛出点和翻译表，容易漏。
- `maintenance_records` 表唯一约束（见 R4）实际上把"一天多条记录"锁死在 schema 层，未来要支持"同日多次不同项目保养"必须做迁移。

### 跨层依赖缝隙（事实清单）

| 位置 | 问题 |
|---|---|
| `lib/features/shell/profile/settings_data.dart:18` | UI 直接 import `data/backup/backup_codec.dart` 做编解码，绕过 Repository |
| `lib/features/shell/reminders/reminder_notifications.dart:19` | UI（view-data 层）直接 import `LunioRepository` 读 snooze/ack 偏好，绕过 provider |
| `lib/data/bootstrap/built_in_vehicle_catalog.dart:15` | data 层 import `flutter/services.dart`（rootBundle），data → Flutter 反向依赖 |
| `lib/data/repositories/lunio_repository.dart:1255-1257` | Repository 抛面向用户的中文文案 `StateError('这辆车当天…')`，UI 语义泄漏进数据层 |
| 全 UI 层 | 写操作普遍 `ref.read(lunioRepositoryProvider)` 直调（无 ViewModel/UseCase），对小 App 可接受，但"读走 provider、写走 repository"是混合模式 |

这些缝隙在当前规模下不构成实际故障，但决定了"以后加同步/多页面复用"时的改造成本。

---

## 4. 问题清单

> 编号 R1-R38，按严重度分三档。每条含：位置（文件:行号）、推理、建议修法。
>
> **修复状态（2026-08-26 更新）**：R2/R3/R6/R7/R8/R11/R12/R13/R15/R16/R18/R19/R21/R22/R23/R24/R25/R26/R27/R28/R29/R31/R33/R35/R37 与 §5.2、§5.3（5.3.2 除外）已修复；R1 部分修复（恢复/清空路径已补通知取消，"删除最后一辆车"路径不在本轮）；R32 部分修复（三套 sheet 骨架子项保留）。其余条目未修复（不在本轮范围）。各条目下方的【已修复】行为修复说明。
>
> **修复状态（2026-08-29 更新）**：R1 全部修复（补"删除最后一辆车"通知取消）；R4 修复（业务校验收紧为同车同日一条记录）；R5 定调为产品设计并删除死字段；R10/R14/R34 修复；R32 全部修复（三套 sheet 骨架统一到 PrototypeSheetFrame、FormActions 样板收敛为 LunioFormActions）；§7 关键缺口补齐测试（调度竞态、exact alarm 被拒、snooze 到期日边界、displayPercent 钳制、时区回退、日历步进）。

### 4.1 高优先级（正确性 / 数据一致性）

**R1 · 恢复备份/清空数据后，停车倒计时系统通知残留**
- **【全部修复 2026-08-29】** "删除最后一辆车"路径补齐：`shell_actions.dart → deleteCar` 在删除成功后 `bump()` 同步代数 + 显式 `cancelLunioNotifications()`（同步控制器在 car == null 时短路，必须动作层兜底）；widget 测试断言删车后 16 个在用 id 全部取消。此前（2026-08-26）恢复/清空两条路径已补显式取消。
- 位置：`lib/features/shell/profile/settings_data.dart`（restoreBackupFromFile / clearAllData，约 208-271 行）；`lib/core/notifications/lunio_notification_service.dart:243`（scheduleParkingCountdownNotification）
- 推理：恢复/清空只做 `notificationSyncGeneration++` + invalidate。停车进行中时恢复备份 → 偏好被清（数据库里无倒计时），但 OS 层已注册的 **9001 到点闹钟照常响铃**、**9002 Android 常驻通知**（`autoCancel:false, ongoing:true`）持续显示到 timeoutAfter。同理，清空数据后被删车辆的 8000/8900 系通知也不会被取消——`app_shell.dart` 的 `_applySystemNotificationSchedule` 在 `car == null` 时提前 return，唯一 cancel 入口不会执行。
- 建议：restore/clearAllData 动作里显式调用 `cancelParkingCountdownNotification()` + `cancelLunioNotifications()`；或让 `_syncReminderNotifications` 在 car 为 null 时也走一次"全取消"调度。

**R2 · 恢复备份会静默清空全部偏好**
- **【已修复 2026-08-26】** 恢复改走 `_clearRestorableDataInTransaction`：只清 4 张业务表 + 按前缀清提醒抑制键，偏好（主题/通知设置/手动日期/停车倒计时）整体保留；确认文案同步为「偏好设置会保留」口径。
- 位置：`lib/data/repositories/lunio_repository.dart:1079`（`_clearAllDataInTransaction` 删 `appPreferences` 整表）；恢复链路 `settings_data.dart` restoreBackupFromFile
- 推理：备份 JSON 契约不含偏好（刻意设计，见 `docs/migration/review-fix-todo.md`），恢复时清库把主题、通知设置、开发者模式、全部 snooze/ack 一起删掉。确认文案虽然写了"会清空偏好"，但用户预期"恢复数据"≈"数据回来"，主题/设置被重置是隐性损失。
- 建议：短期在确认文案里更显眼地列出会丢失的设置项；长期把偏好按 key 白名单保留（themeMode 等"设备级设置"不该随备份走）。

**R3 · 通知重调度存在"丢更新"竞态**
- **【已修复 2026-08-26】** 同步控制器（notification_sync_controller.dart）在执行中收到新签名时置 pending，本轮 finally 置空签名并用最新数据重跑一轮；reschedule 前再查一次同步代数。
- 位置：`lib/features/shell/app_shell.dart:297`（签名先置值）+ `:399`（in-flight 直接 return）
- 推理：签名变化时**先**把 `_systemNotificationSignature` 记为新值，post-frame 异步执行调度；若此刻上一轮 `_applySystemNotificationSchedule` 还在跑（内部有 1000 次 cancel await，见 R10，耗时可观），新任务被 `if (_syncingSystemNotifications) return;` 直接丢弃。之后没有新数据变化的话，**这次变更永远不会反映到系统通知**（直到下次任意数据变化或冷启动）。
- 建议：把"执行中收到新签名"改为排队（存 pending 签名，执行完比对再跑一轮），而不是丢弃。

**R4 · `maintenance_records` 唯一约束与业务规则口径冲突**
- **【已修复 2026-08-29】** 采纳"收紧业务校验"方案：`_ensureRecordIsUnique` 删除项目重叠分支，同车同日已有记录即抛 `StateError('这辆车当天已有保养记录，请编辑原记录')`（文案保持"这辆车当天"前缀以走 friendlyError 透传）；表注释与 doc 同步；补"同日不同项目也拦截"用例。`removeMaintenanceRecordItem` 删到 0 项连记录删的逻辑保留（语义是"空记录无意义"）。
- 位置：`lib/data/database/app_database.dart:155`（UNIQUE `{carId, date}`）vs `lib/data/repositories/lunio_repository.dart:1227`（`_ensureRecordIsUnique`：同日不同项目允许）
- 推理：业务校验放行"同日不同项目的第二条记录"，但插入主表时撞表级约束抛 `SqliteException(2067)`，UI 只能给通用文案"这条数据已经保存过了"。`removeMaintenanceRecordItem` 删到只剩 0 项时连记录一起删（repository 约 860 行）也是为了迁就这个约束。
- 建议：要么收紧业务校验（同日只允许一条，文案已备好"请编辑原记录"）；要么迁移 schema 把主表唯一约束改为 `{carId, date}` → 关联表 `{carId, date, itemId}` 已有约束就够。二选一，消除两层口径不一致。

**R5 · `maintenanceDueEnabled` 被硬编码 true，用户无法关闭"保养到期提醒"**
- **【已定调并清理 2026-08-29】** 确认为产品设计：保养到期提醒是 App 核心能力，不提供关闭入口。死字段整体移除：实体 `notification_settings.dart`、`notificationSettingsProvider` 批量读 key、`saveNotificationSettings` 写入项、`noticeDueForRow` 短路判断（去 settings 参数）、inApp 通知签名段、widget 测试断言、AGENTS.md 偏好 key 清单。老库残留偏好行无人读取，无害；升级首帧 inApp 签名变化触发一次幂等重算，无行为差异。
- 位置：`lib/features/shell/profile/settings_data.dart:498`（提交时硬编码）；`lib/domain/entities/notification_settings.dart`（该开关实体仍存在并被 `app_shell` 签名与 `noticeDueForRow` 消费）
- 推理：通知设置 UI 只有三个控件（系统状态/应用内开关/重复频率），提交构造 `LunioNotificationSettings(maintenanceDueEnabled: true, …)`。即使旧版本曾把该偏好写成 false，打开一次设置 sheet 保存即被覆盖回 true。
- 建议：要么在 UI 加上这个开关，要么从实体/偏好/签名里整体移除该字段（当前是"半尸"状态）。

**R6 · 通知设置 sheet 在 loading 期读默认值，保存会覆盖真实设置**
- **【已修复 2026-08-26】** 打开 sheet 前 `await ref.read(notificationSettingsProvider.future)`，加载失败 toast「设置加载失败」并返回。
- 位置：`lib/features/shell/profile/settings_data.dart:281`（`maybeWhen(orElse: () => const LunioNotificationSettings())`）
- 推理：打开 sheet 时若 `notificationSettingsProvider` 尚在 loading，初始值回退为全默认（应用内开、每周）；用户直接点"保存设置"就会把默认值写库。冷启动后立刻进设置页可复现。
- 建议：打开 sheet 前 `await ref.read(notificationSettingsProvider.future)`（与记录表单入口的做法一致）。

**R7 · iOS 文件桥注册失败无容错，备份功能可能抛未处理异常**
- **【已修复 2026-08-26】** Dart 侧两个方法捕获 PlatformException/MissingPluginException（返回 false/null + debugPrint）；iOS 侧 `configureNativeFilesChannelIfNeeded` 存 channel 属性 + guard，willConnectTo 延迟一拍与 sceneDidBecomeActive 重试，完全镜像通知设置桥。
- 位置：`ios/Runner/SceneDelegate.swift:32-50`（`lunio/native_files` 仅在 `scene(willConnectTo:)` 注册一次，无重试；对比通知设置桥有 `sceneDidBecomeActive` 重试）；Dart 侧 `lib/core/platform/native_files.dart` **不捕获 MissingPluginException**（另两个桥都捕获）
- 推理：iOS Scene 生命周期时机问题若导致 channel 未注册，点"备份/恢复"直接抛未处理异常。
- 建议：Dart 侧补 try/catch（返回 false + toast）；iOS 侧参照通知设置桥补注册重试。

### 4.2 中优先级（健壮性 / 性能）

**R8 · 全局可变 `notificationSyncGeneration` 做并发控制**
- **【已修复 2026-08-26】** 改为 `notificationSyncGenerationProvider`（NotifierProvider，bump() 自增）；恢复/清空、同步控制器、saveParkingCountdown 的快照/比对全部走 provider。
- 位置：`lib/features/shell/shared/shell_actions.dart:18`；写入点 `settings_data.dart`（恢复/清空），读取点 `app_shell.dart:396/475`
- 推理：用顶层全局变量做"作废在途任务"的代数令牌，绕过 provider 体系，测试不可注入，且覆盖不了所有在途 Future（如 `parking_countdown.dart:614` saveParkingCountdown 的通知调度链不受保护）。
- 建议：改为 Riverpod `StateProvider<int>` 或专用 Notifier。

**R9 · 停车倒计时到期后无任何状态清理**
- 位置：`lib/data/repositories/lunio_repository.dart`（`getParkingCountdown` 无过期判断）；`lib/features/shell/reminders/reminder_page.dart`（倒计时存在时"停车倒计时"按钮禁用）
- 推理：到点后卡片转为正计时"已到点"（设计如此），但偏好里的倒计时永不自动清除；用户必须手动点"结束"才能开始新倒计时。App 被杀重启后依然显示过期卡片。
- 建议：可接受的设计（保留了"已停多久"信息），但建议提供"已到点状态一键开始新计时"；或到期超过 N 小时自动清除 + 取消通知。

**R10 · 每次重排系统通知串行 cancel 1000 个 id**
- **【已修复 2026-08-29】** `cancelLunioNotifications` 改为按服务内常量（基础 id [8000, 8900] × occurrenceCount 8）精确取消 16 个在用 id；文件头 id 分配表注明改动 occurrenceCount/新增基础 id 时必须同步。widget 测试的 8000 段断言从 `isNotEmpty` 收紧为精确 16 个 id 集合。
- 位置：`lib/core/notifications/lunio_notification_service.dart:230-233`（`for id in 8000..8999 await cancel`）
- 推理：实际只使用 8000-8007 / 8900-8907 共 16 个 id。任何数据签名变化（保存一条记录、切换车辆）都触发 1000 次串行 platform channel 调用 + 16 次 zonedSchedule；同时放大 R3 的竞态窗口。
- 建议：维护"已注册 id 集合"或直接 cancel 用过的 16 个 id；一次 `cancelAll()` 也可考虑（注意别误删停车通知）。

**R11 · 提醒页 250ms Timer 全页重建**
- **【已修复 2026-08-26】** 删除页面级 250ms Timer；ParkingCountdownCard 改 ConsumerStatefulWidget 内部 1s Timer 自刷新（时钟走 appDateContext，测试可注入）；英雄卡与提醒列表不再秒级重建。
- 位置：`lib/features/shell/reminders/reminder_page.dart:55`（`Timer.periodic(250ms) → setState`）
- 推理：停车倒计时秒级刷新需要重算，但 setState 重建整页：hero 卡、提醒列表（`buildReminderRows` 对 items×records 全量重算）、`dueOverviewText`（又一次全量重算，见 `reminder_notifications.dart:484`）每秒执行 4 次。无倒计时时也在空转。
- 建议：ticker 下沉到 `ParkingCountdownCard` 内部；或用 `ValueNotifier<DateTime>` 只驱动时钟文本；无倒计时时暂停 ticker。

**R12 · AppShell 在 build 里做副作用 + 每帧拼数据签名**
- **【已修复 2026-08-26】** 通知同步抽到 `NotificationSyncController`（reminders/notification_sync_controller.dart）：start() 对 6 个 provider `ref.listenManual(fireImmediately: true)` 驱动，AppShell build 只渲染。
- 位置：`lib/features/shell/app_shell.dart:244`（`_syncReminderNotifications` 在 build 中调用并改写字段）；`lib/features/shell/reminders/reminder_notifications.dart:219`（`reminderNotificationDataSignature` 拼大字符串）
- 推理：build 每帧执行（含 250ms ticker 引发的重建），签名拼接是 O(items+records) 的字符串操作；副作用虽被 postFrameCallback 推迟到帧后，但"build 驱动 I/O"模式让权限请求、通知调度、弹窗都挂在渲染路径上，难测试且有隐式循环（权限查询 → 写偏好 → invalidate → rebuild → 再查询）。
- 建议：把通知同步抽成独立的 `Notifier`/服务类，由 provider 变化（`ref.listen`）驱动而非 build。

**R13 · 多处 async gap 后使用 `ref` 无 mounted 保护**
- **【已修复 2026-08-26】** 控制器所有 await 后补 `_disposed` 检查（弹窗前另取 shellContext() 新鲜 context）；saveParkingCountdown/clearParkingCountdown 增加 BuildContext 参数，每个 await 后 `if (!context.mounted) return;`。
- 位置：`lib/features/shell/app_shell.dart:333-385`（`_ensureInitialSystemNotificationPermission` / `_applySystemNotificationSchedule` 多个 await 后 `invalidatePreferenceProviders(ref)` / `ref.read`）；`lib/features/shell/reminders/parking_countdown.dart:614-660`（saveParkingCountdown 闭包持有外部 ref，sheet 关闭不中断链路）
- 推理：Widget 销毁后使用其 `WidgetRef` 会抛错（Riverpod 3 中对已 dispose 元素调用 invalidate 抛 `StateError`）。UI 层的 `context.mounted` 检查整体做得不错（20+ 处都有），唯独 ref 这条线没有保护。
- 建议：await 后补 `if (!mounted) return;`，或把这段逻辑移出 Widget。

**R14 · 吞异常点（静默失败）**
- **【已修复 2026-08-29】** 三处补日志：`getParkingCountdown` JSON 损坏 → `dart:developer` log；权限查询失败 → debugPrint；时区获取失败 → debugPrint（回退目标同步改为 Asia/Shanghai，见 R34）。
- 位置：
  - `lib/data/repositories/lunio_repository.dart:1048`：`getParkingCountdown` JSON 损坏 `catch (_) { return null; }`——坏数据永远留在库里且无感知；
  - `settings_data.dart`（refreshSystemNotificationPreference）：权限查询失败静默回退旧值；
  - `lunio_notification_service.dart`（`_configureLocalTimezone`）：时区获取失败回退 UTC——**非 UTC 时区的设备所有通知时刻整体偏移一个时区差**，且无日志。
- 建议：至少加 `debugPrint`/日志；时区回退应视为初始化失败并提示。

**R15 · `main()` 通知初始化无兜底**
- **【已修复 2026-08-26】** main() 包 try/catch + `markInitializationFailed()`；服务增加 `_available` 降级标志：不可用时权限/开关查询返回 false、调度/取消全部安全 no-op。补服务测试。
- 位置：`lib/main.dart:33`
- 推理：`await LunioNotificationService.instance.initialize()` 在 runApp 之前执行且无 try/catch；插件异常 = 白屏起不来。
- 建议：包 try/catch，失败降级（App 可用、通知功能标记不可用）。

**R16 · 外键式查询列缺索引**
- **【已修复 2026-08-26】** schema v6：三张业务表加 `@TableIndex`（items.cars_id / records.car_id / record_items.maintenance_record_id），onUpgrade 补 createIndex；database_test 补 sqlite_master 断言。
- 位置：`lib/data/database/app_database.dart`（`maintenance_records.car_id`、`maintenance_record_items.maintenance_record_id`、`maintenance_items.cars_id` 均无索引）；查询点如 `lunio_repository.dart` listMaintenanceRecordsForCar / maintenanceItemHasHistory / _ensureRecordIsUnique
- 推理：本地单用户数据量小，当前无感；记录上千后按车查记录、查项目历史会全表扫描。
- 建议：下次 bump schemaVersion 时顺手加三个普通索引。

**R17 · 已过期倒计时的通知调度被静默吞掉**
- 位置：`lib/core/notifications/lunio_notification_service.dart:250`（先 cancel 旧通知，再 `if (!scheduledDate.isAfter(now)) return;`）
- 推理：表单允许选过去的入场时间（时间轮只能改时分秒、初始为当天），若免费时长已过：数据库显示倒计时进行中，但既无到点闹钟也无常驻通知，无任何提示（与 R9 叠加成"看起来在计时其实什么都不会发生"）。
- 建议：保存时校验 endsAt 必须在未来，或提示"该时刻已过期"。

**R18 · monthly 重复步进未做月末钳制，月度提醒漂移**
- **【已修复 2026-08-26】** `nextMonthlyOccurrence` 做月末钳制（1.31 → 2.28/29，12.31 → 次年 1.31）；补单测与 rescheduleNotifications 通道参数的集成断言。
- 位置：`lib/core/notifications/lunio_notification_service.dart:399`（`TZDateTime(y, month+1, day)`）
- 推理：1 月 31 日排的月度提醒，下次归一化到 3 月 3 日，此后固定漂移到 3 号。对比 `LocalDate.addMonths`（`lib/core/date/local_date.dart`）有正确的 clamp 实现。
- 建议：monthly 分支改用日历库的月份加法或手动 clamp。

**R19 · 迁移产物漂移：升级库与全新安装 schema 不一致**
- **【已修复 2026-08-26】** 已在 `docs/migration/current-database-schema.md` 显式记录 v6 索引的两种等价形态（建表附带 vs createIndex）。
- 位置：`lib/data/database/app_database.dart:239-269`（v5 迁移建的是 `WHERE catalog_id IS NOT NULL` 部分唯一索引；全新安装走 createAll 生成表内 UNIQUE 约束）
- 推理：两种产物在 SQLite 语义上等价（可空列 UNIQUE 允许多 NULL），功能无差，但结构漂移会给未来写 onUpgrade 的人埋坑（以为只有一种形态）。
- 建议：在 `docs/migration/current-database-schema.md` 里显式记录两种形态；或统一为部分索引。

**R20 · v1→v2 破坏性迁移删光数据**
- 位置：`lib/data/database/app_database.dart:239-243`
- 推理：`from < 2` 时删全部表重建，v1 用户升级丢光数据。历史上可能是有意为之（v1 仅内测），但值得在文档里明确"不再有 v1 用户"后才可安心。
- 建议：无需动作，记录在案。

**R21 · build 期间修改 state 集合**
- **【已修复 2026-08-26】** 记录页筛选改为派生集合：渲染与过滤用 `_validSelections` 的过滤视图，state 仅由用户点击变更。
- 位置：`lib/features/shell/records/records_page.dart:75/80`（`selectedYears.removeWhere(...)` 在 build 的数据分支里执行）
- 推理：纯清理不触发重建，能跑；但属于 build 副作用，配合未来重构容易变成隐患。
- 建议：移到数据变化回调（provider listen）或用 derived 过滤（渲染时忽略失效选项，不改 state）。

**R22 · TextPainter 未 dispose**
- **【已修复 2026-08-26】** ItemPills 整体改 `Wrap`（spacing/runSpacing 6），删除手写装箱算法与 `_measureTextWidth`，TextPainter 泄漏随之消失。
- 位置：`lib/features/shell/shared/shared_widgets.dart:262`（`_measureTextWidth`）
- 推理：Flutter 3.16+ 要求 TextPainter dispose，debug 模式会打泄漏提示；每次 ItemPills build 都新建。
- 建议：测量完调用 `painter.dispose()`；更根本的：整个手写装箱算法可用 `Wrap` 替代。

**R23 · 切换车辆 sheet 同步读 provider，loading 期误报**
- **【已修复 2026-08-26】** showVehicleSwitcher 改 async：await carsProvider/appliedCarProvider，加载失败 toast「车辆加载失败」，后续逻辑补 context.mounted 检查。
- 位置：`lib/features/shell/profile/vehicles.dart:1052`（showVehicleSwitcher 用 `ref.read(...).maybeWhen(orElse: 空列表)`）
- 推理：冷启动车辆还在加载时点"切换车辆"，会提示"请先新增车辆"（实际有车）。按钮本身有多车才显示的守卫，窗口小但存在。
- 建议：改 `await ref.read(carsProvider.future)`。

**R24 · 列表用实体 `==` 判断"最后一项"**
- **【已修复 2026-08-26】** records_page（改 SliverList.builder 后按 index 控制行距）与 maintenance_items 两处列表全部改下标循环判断。
- 位置：`lib/features/shell/records/records_page.dart:276`（`record != records.last` 按 id 比较）；maintenance_items 列表同模式
- 推理：实体未重写 `==`（按引用比较），当前数据源去重后恰好安全；若列表出现同 id 重复对象，间距判断会错位。
- 建议：改用 `for (var i = 0; ...)` 下标或 `List.sublistView` 模式。

**R25 · 各列表非懒加载、无 key**
- **【已修复 2026-08-26】** 记录页两个列表改 `SliverList.builder` + `ValueKey('record-…')`；LunioPage 增加 slivers 构造（CustomScrollView）。其余页面维持 Column+for（量级小，加法式改动不影响）。
- 位置：`records_page.dart` 两个列表、`reminder_list.dart`、`vehicles.dart`、`maintenance_items.dart` 全部 `Column + for` 直排
- 推理：LunioPage 外层是 ListView，但列表项整块一次性构建，记录多时整页构建成本线性涨。当前量级可接受。
- 建议：记录页转 `ListView.builder` + itemKey（id）。

### 4.3 低优先级（代码卫生 / 口径 / 边界）

**R26 · 死代码与遗留 API**
- **【已修复 2026-08-26】** 全清：id_generator.dart + uuid 依赖、barrel re-export、maintenanceRepeatFrequency（内联）、停车表单 initial 死分支、isScrollControlled 参数及全部调用点、with/withoutManualDate、statusForPercent（连测试）、noHistoryBaselineMileageKm 死参数（签名收缩，doc 注明 PRD 口径）、createCar/createCarWithDefaultItems（测试改写等价替身）。`AppDateContext.manualDate` 字段保留（测试注入在用）。
- `lib/core/id/id_generator.dart`：UUID 生成器无调用方，连带 `pubspec.yaml` 的 `uuid` 依赖可移除；
- `maintenance_rules.dart` `statusForPercent`：生产无调用（仅测试），与 `_statusForItem` 双轨阈值；
- `reminder_notifications.dart` `maintenanceRepeatFrequency`：忽略全部入参直接返回设置值（预留签名）；
- `parking_countdown.dart` 表单 `initial` 编辑分支不可达（倒计时存在时入口按钮禁用）；
- `reminder_page.dart:17-21` barrel re-export 无消费者；
- `modal_feedback.dart:29` `isScrollControlled` 参数声明未使用（恒全屏）；
- `lunio_repository.dart` `createCar`/`createCarWithDefaultItems` 近乎遗留（UI 不用）；
- `providers.dart` `AppDateContext.manualDate` 生产永不填充（手动日期实际走另一个 provider）。

**R27 · 偏好读写串行无批量、无事务**
- **【已修复 2026-08-26】** Repository 新增 `getPreferenceValues`（IN 查询）/`updatePreferenceValues`（事务批量写）；notificationSettingsProvider 与 saveNotificationSettings 改用批量接口。
- 位置：`lib/app/providers.dart`（notificationSettingsProvider 串行 4 读）；`settings_data.dart` saveNotificationSettings 串行 4 写
- 建议：Repository 加批量读/事务写接口。

**R28 · bootstrap asset 重复加载 3 次**
- **【已修复 2026-08-26】** Repository 实例内 memoize 目录解析 Future（`_loadCatalog`），三个 ensure 入口共用。
- 位置：`lib/data/repositories/lunio_repository.dart:162`（ensureBootstrapData 链路里 catalog 被加载 3 次，无缓存；添加车辆向导 loadDefaultItems 又调一次）
- 建议：catalog 解析结果按启动周期缓存。

**R29 · provider 依赖存在"只借失效信号"的隐式 watch**
- **【已修复 2026-08-26】** carsProvider/appliedCarProvider 改显式 `await ref.watch(上游.future)`（行为等价，依赖一目了然）。
- 位置：`lib/app/providers.dart:164-174`（carsProvider watch bootstrap 不 await；appliedCarProvider watch carsProvider 丢弃结果只取失效信号）
- 推理：当前正确（bootstrap 不写 cars；getAppliedCar 自查车辆），但依赖关系是隐式的，重构时容易引入顺序 bug。
- 建议：加注释已做；进一步可显式化（如 appliedCarProvider 直接 await carsProvider.future）。

**R30 · 过度提取与欠提取的组件（详见 §5）**

**R31 · `maintenanceItemHasHistory` 等用 `.get()` 拉全行判空**
- **【已修复 2026-08-26】** maintenanceItemHasHistory 加 limit(1)；getAppliedCar/deleteCar/_ensureAppliedCarInTransaction 改点查（回退「id 最小的车」与原 listCars 首行语义等价）。
- 位置：`lunio_repository.dart`（maintenanceItemHasHistory / getAppliedCar / deleteCar / _ensureAppliedCarInTransaction 全表 `.get()`）
- 建议：`count()` 或 `limit(1)`。

**R32 · 重复实现**
- **【全部修复】** 2026-08-26 完成 _formatClock 合并、IntervalNumberInputRow 合并、itemRuleText/defaultItemRuleText 合并、vehicles 加载失败检查块提取；2026-08-29 完成剩余两项：三套 sheet 骨架（5.3.2）统一为 PrototypeSheetFrame（迁移 6 处默认表面 sheet + 4 处 LunioSheetScaffold 调用点，删除 LunioSheetScaffold 与 `_LunioDefaultSheetSurface`，表面容器内包透明 Material 供 ListTile 正确绘制）、表单 FormActions 样板（5.3.5）收敛为 shared 的 `LunioFormActions`（迁移 9 处手写按钮行，顺带统一 settings_data 唯一一处裸 FilledButton）。
- `_formatClock` 两份（`parking_countdown.dart` / `lunio_notification_service.dart`）；
- `RecordIntervalInputRow`（records_page）与 `ReminderRuleInputRow`（maintenance_items）几乎逐行相同；
- 三套 sheet 骨架并存（`PrototypeSheetFrame` / `_LunioDefaultSheetSurface` / `LunioSheetScaffold`）；
- `itemRuleText` / `defaultItemRuleText` 逻辑重复；
- 添加车辆与编辑车辆 sheet 里"车型/日期加载失败"检查块复制两份。

**R33 · 空态文案与实际不符**
- **【已修复 2026-08-26】** 记录页空态改为「暂无保养记录，可在提醒页点「新增保养记录」。」，文件头注释同步。
- `records_page.dart:136`："点击右下角 + 新增"——App 没有 FloatingActionButton，新增入口只在提醒页。

**R34 · DST/时区类边界（目标市场 Asia/Shanghai 无夏令时，影响有限）**
- **【已修复 2026-08-29】** 按确认的 3 步：① `_configureLocalTimezone` 失败回退从 UTC 改为 Asia/Shanghai（目标市场时区、固定 +8，测试 mock 时区通道抛错断言 `tz.local` 落点）；② 日期步进改日历加减——`_nextOccurrence` 日/两周/三周分支改 `addCalendarDays`（字段构造保持墙钟时刻，visibleForTesting 供单测）、`_nextScheduleDate` 顺延一天同步改、`snoozeUntilDate` 改 `LocalDate.addDays`（新增，DateTime 归一化跨月/跨年）；③ 海外使用场景的产品语义留待有需求再议。
- `local_date.dart:73` daysUntil 用本地午夜差（跨 DST 差 1 天）；
- 通知日/周步进用 Duration 相加（跨 DST 小时漂移）；
- snooze +15 天跨 DST 变 14/16 天；
- 时区回退 UTC（R14 已列）。

**R35 · 恢复备份不执行业务规则校验**
- **【已修复 2026-08-26】** restoreBackupPayload 在引用校验后、开事务前逐条过 `item.validate()` 与 `RecordRules.validateRecord`，失败抛中文 ArgumentError；补篡改备份（负金额/负里程/空项目/非法间隔）被拒且库未动的测试。
- 位置：`lunio_repository.dart:890`（restoreBackupPayload 只做引用完整性预校验，裸 insert）
- 推理：手工编辑的备份可注入负数金额/里程、空 itemIds 记录，破坏 RecordRules 不变量。
- 建议：恢复循环里逐条调 `RecordRules.validateRecord` / `item.validate()`。

**R36 · 里程与日期的宽松口径**
- 编辑车辆里程可任意改小（无回退校验，与"记录触发只增"并存——用户手动改小是允许的）；
- 记录日期允许未来 365 天（时间进度计算有归 0 防护，不崩溃）。
- 属产品口径宽松而非 bug，列出待确认。

**R37 · 无历史车辆的里程基线为 0（设计确认项）**
- **【已确认并收缩 2026-08-26】** 确认为 PRD 设计（无历史按 0 里程基线）；`noHistoryBaselineMileageKm` 死参数已从 progressForItem/_mileageProgress 签名移除，doc 注释写明口径。
- 位置：`lib/domain/rules/maintenance_rules.dart:130`（`noHistoryBaselineMileageKm = 0`，生产调用从不传）
- 推理：二手高里程车无记录时里程进度会立刻算出超高百分比。但产品约定"没有任何记录就不产生提醒"（`maintenanceNotices` 空记录直接返回），实际不会被轰炸；首条记录落库后基线立即修正。
- PRD 明示为设计（"无历史按上路日期与 0 里程基线"），列出仅供确认。

**R38 · 测试覆盖缺口（详见 §7）**

---

## 5. 复用评估

### 5.1 合理提取（真正的高频共享层，保留）

| 组件/工具 | 位置 | 引用次数 | 说明 |
|---|---|---|---|
| `showLunioModalSheet` | `modal_feedback.dart:24` | 16 | 全部 sheet 的统一入口 |
| `showStatusOverlay` / `StatusOverlayTone` | `modal_feedback.dart` | 13 / 25 | 统一 toast 反馈 |
| `friendlyError` | `formatters.dart` | 17 | 全部表单错误翻译 |
| `showConfirmDialog` | `modal_feedback.dart` | 6 调用点 | 危险操作确认 |
| `SmallActionButton` | `shared_widgets.dart` | 18 | 最高频 UI 组件 |
| `PrototypeSheetFrame` | `shared_widgets.dart` | 11 | 表单 sheet 骨架 |
| `showSimpleDatePicker` | `date_picker.dart` | 4 | 自绘三级日期选择器 |
| `formatNumber` / `normalizeItemName` | `formatters.dart` | 11 / 9 | 格式化工具 |
| `applyCar`/`deleteCar`/`setThemeModePreference` | `shell_actions.dart` | 跨页复用 | 动作助手 |

这一层的提取度是健康的：**提取的判断标准应该是"被多处使用且语义稳定"，以上都符合。**

### 5.2 过度提取（单调用点却放进 shared，建议回收或就地内联）——【已处理 2026-08-26】

| 组件 | 位置 | 唯一使用方 |
|---|---|---|
| `LoadingPage` / `ErrorPage` | `shared_widgets.dart:461/476` | 仅提醒页（记录/我的页各自手写 loading/error，风格反而分裂） |
| `FilterBar` | `shared_widgets.dart:20` | 仅记录页（2 个调用点在同一文件） |
| `ChoiceChipButton` | `shared_widgets.dart:418` | 仅记录表单 |
| `formatMoney` / `itemRuleText` / `defaultItemRuleText` / `mileageReminderText` 等单点格式化函数 | `formatters.dart` | 各 1 处 |

**权衡说明**：本仓库的规模下这些"伪共享"伤害不大（没有增加理解成本太多），但它们让 shared/ 看起来比实际更"公共"，新人会把页面私有组件也往里塞。建议：单调用点的组件移回使用方文件，shared/ 只保留 ≥2 个调用方的内容。

> **【已处理 2026-08-26】**：LoadingPage/ErrorPage 三页统一推广（提醒/记录/我的同构 when 分支）；FilterBar/ChoiceChipButton 回收为 records_page 私有；单点格式化函数（formatMoney/itemRuleText/defaultItemRuleText/mileageReminderText/displayPercentForThresholds/normalizeItemName 及配套紧凑文案函数）全部回收或合并到各自消费文件；formatters.dart 只保留多文件复用项。

### 5.3 该提取未提取（重复代码，建议合并）——【已全部处理 2026-08-29】

1. 【已合并】`RecordIntervalInputRow` ≡ `ReminderRuleInputRow` → shared 的 `IntervalNumberInputRow`（可选开关的数字输入行），两个表单已迁移；
2. 【已统一 2026-08-29】三套 sheet 骨架收敛为 `PrototypeSheetFrame`（15 处 sheet 全部迁移；删除 `LunioSheetScaffold` 与 `_LunioDefaultSheetSurface`）；
3. 【已合并】`_formatClock` 双实现 → formatters 的 `formatClock`（停车卡片/表单与通知服务共用）；
4. 【已替换】`ItemPills` 手写 TextPainter 装箱 → `Wrap`；
5. 【已收敛 2026-08-29】表单 FormActions 样板 → shared 的 `LunioFormActions`（9 处迁移）。

### 5.4 结论

复用水平**中上**。真正的公共层（modal/confirm/toast/日期选择器/错误翻译）质量高、复用密；问题是两端各有少量失衡：几个单点组件被过早放进 shared，几个跨文件重复没有被拉出来。均不影响正确性，属于滚动重构可消化的债务。

---

## 6. 业务逻辑合理性

### 6.1 主干逻辑（合理，测试扎实）

- **进度计算双维取大**（`MaintenanceRules.progressForItem`）：里程/时间各自算百分比取较大者展示，状态按项目自定义阈值（100/125 可调）判定——语义清晰，边界（负数归 0、无除零、月末钳制）处理到位，`test/domain/maintenance_rules_test.dart` 覆盖了闰年/月末/阈值边界。
- **里程只增**（`RecordRules.mileageAfterRecord`）：新增/编辑记录都会 max 同步到车辆，防止编辑旧记录拉低里程；有测试。
- **应用车辆回退**（`AppliedCarRules`）：偏好失效回退第一辆、无车清空；删除车辆的事务级联顺序正确；有测试。
- **bootstrap 幂等对账**：按 catalogId 对 asset 目录 upsert/删除，App 升级更新目录自动生效；有测试。
- **备份事务恢复**：引用完整性预校验 + 单一大事务 + id 重映射，冲突回滚"未写入任何数据"；回滚正确性有测试。
- **snooze/ack 两级抑制**：snooze 15 天静默系统+应用内，ack 只静默当天应用内——语义分明，实现一致。

### 6.2 明显 bug

见 R1-R7（通知残留、偏好清空、丢更新竞态、约束冲突、硬编码开关、默认值覆盖、iOS 桥容错）。

### 6.3 隐藏性 bug / 边界（容易踩、难复现）

R9（过期倒计时不清理）、R17（过期调度静默吞）、R18（月末漂移，只在 29-31 号启动复现）、R34（时区/DST 类）、R35（恶意备份注入）、R3（只在通知重排进行中恰好又有数据变化时丢更新）。

---

## 7. 测试覆盖评估

现有 10 个测试文件 / 130 个用例，全部通过：

| 文件 | 覆盖 |
|---|---|
| `test/domain/*`（5 个） | 进度计算边界、记录校验、应用车辆回退、停车进度、手动日期/LocalDate |
| `test/core/notifications` | 权限查询、9:00 调度、停车错峰、alarm 参数、取消 9001/9002 |
| `test/core/id` | 雪花 id 唯一性、时钟回拨 |
| `test/data/database_test.dart` | Repository 40+ 用例：bootstrap/约束/级联/备份往返与回滚/清空 |
| `test/data/backup_codec_test.dart` | 备份 JSON 往返 |
| `test/widget_test.dart` | ~60 条 UI 流：三入口、停车全流程、记录表单、加车向导、备份确认、ack/snooze |

**关键缺口**（与问题清单一一对应）：

- ~~恢复/清空后的通知清理（R1，无实现也无测试）~~（已补：清空/删除最后一辆车用例断言 16 个在用 id 取消）；
- ~~调度竞态交错（R3）~~（已补：widget 测试用闸门 mock 卡住第一轮 cancel，第二签名变更到达后断言 pending 重跑发生，并经变异验证有效）；
- ~~monthly 月末漂移、DST、时区回退 UTC（R18/R34）~~（已补：R18 月末钳制两条；R34 日历步进、LocalDate.addDays 边界、时区通道抛错回退 Asia/Shanghai 各一条）；
- ~~exact alarm 被拒的降级分支（测试里恒 true）~~（已补：mock 双双拒绝后断言 zonedSchedule 收到 inexactAllowWhileIdle）；
- 过期倒计时的 schedule 提前返回（R17）——仍无测试（R17 明确不在修复范围）；
- 原生桥真机行为（iOS scene 注册时序，R7）——单测天然覆盖不到，需真机手动验证；
- ~~snooze 到期日当天边界、签名稳定性、`displayPercentForThresholds` 钳制边界~~（已补：snooze 截止日当天静默/次日恢复用例、displayPercent 迁入 domain 后 3 组钳制用例；签名稳定性随 R3 竞态用例间接覆盖）。

---

## 8. 总体结论与修复优先级建议

**总体评价：这是一份质量中上的正式 v1 代码。** 分层清晰、领域层纯净、主干业务规则正确且测试密度高（130 用例）、UI 反馈模式统一、备份事务严谨。主要风险集中在**通知生命周期与数据生命周期的错位**（R1/R3/R9/R10/R17 这一族问题共享同一个根因：通知调度内嵌在 AppShell 的 build 流程里、以"全量重排"为唯一同步手段），以及少数 schema/业务口径不一致（R4/R5）。

建议修复顺序（均为后续独立任务，本轮未动）：

| 批次 | 内容 | 对应问题 |
|---|---|---|
| ① 数据安全 | 恢复/清空补通知取消；偏好保留策略确认 | R1、R2 |
| ② 通知引擎 | 重排改排队不丢更新；cancel 收敛到 16 个 id；把同步逻辑移出 AppShell | R3、R10、R12 |
| ③ 口径统一 | maintenanceDueEnabled 去留；记录唯一约束二选一；通知设置 loading 期保护 | R5、R4、R6 |
| ④ 性能 | 提醒页 ticker 下沉；签名计算降频 | R11 |
| ⑤ 健壮性 | iOS 桥容错、吞异常补日志、main 兜底、monthly 钳制 | R7、R14、R15、R18 |
| ⑥ 卫生 | 死代码清理、重复合并、索引、组件归位 | R26、R32、R16、§5 |

---

*报告完。操作步骤与代码的逐行对应关系见 `docs/operations-manual.md`。*
