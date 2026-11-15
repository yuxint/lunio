# ADR 0025：生效今天自刷新——零点调度归 provider

日期：2026-11-15
状态：已接受

## 背景

- 「生效今天」（GLOSSARY）由 `effectiveTodayProvider` 提供：手动日期优先，
  否则系统今天。消费者至少八处：应用车辆数据束（提醒进度、通知同步快照、
  小组件快照）、费用统计数据接缝、提醒页、记录表单默认日期、加油记录
  日期上限、调价预告过期判定、车辆表单日期上限、我的页车龄。
- 新鲜度原挂在 `AppShell` 的 `_midnightRefreshTimer`：`initState` 排一个
  对准下一个本地零点的 Timer，到点 `ref.invalidate(effectiveTodayProvider)`
  再排次日；`dispose` 取消。
- 该 Timer 没有测试触达路径（零点行为在普通测试里不可见），且「今天永远
  新鲜」这个不变量不在 provider 的 interface 上——AppShell 一旦重构或移除，
  缓存会静默停在昨天，八个消费者一起读到过期日期。

## 关键取舍

- **调度寄生在 provider 体内 vs 新增 plain-Dart 时钟模块**：provider 已是
  「生效今天」的唯一 interface；再包一层模块只重复 Riverpod 的失效管线，
  手动日期读取还要异步注入，收益不抵复杂度。选前者。
- **手动日期开启时照排零点**：重算结果不变（手动日期优先），不为少一次
  重算加分支。
- **回前台不显式重算**：后台挂起的定时器恢复后补触发，与现状一致；真机
  若发现后台跨天不刷新，再补显式钩子（只是加一条转发，不推翻本决定）。
- **零点边界精确排到下一个本地零点**：Dart Timer 不会提前触发；时钟回拨
  与系统改时间不处理，与现状同口径。
- **时钟经注入**：调度用 `appDateContextProvider.readSystemNow`（测试可传
  固定或可推进时钟），纯时长计算收在 `lib/core/date/`，不碰 Flutter 与
  Riverpod。
- **定时器跟随观察者（Riverpod 3 pause 生命周期）**：无人观察「今天」时
  取消定时器、重新观察时重排。生产壳层持续观察（通知同步与小组件快照
  控制器常驻），正常路径与常驻等价；外部容器测试在组件树卸载后不留
  pending timer（组件树卸载的 pending timer 不变式要求）。生命周期回调内
  禁止 `invalidateSelf`，跨零点暂停的陈旧窗口由下一次重建收口（生产不进入
  该窗口）。

## 决定

1. 新增 `lib/core/date/midnight.dart`：纯函数
   `untilNextMidnight(DateTime now)` = 下一个本地零点 − `now`。整点零点
   返回整天而不是 0——零时长定时器会立刻触发，形成自旋。
2. `effectiveTodayProvider` 的 build 体内自调度：按注入时钟建一次性
   `Timer`，到点 `ref.invalidateSelf()`；`ref.onCancel` 取消、
   `ref.onResume` 重排、`ref.onDispose` 兜底取消。provider 名称、类型
   （`FutureProvider<LocalDate>`）与全部消费者不变；重建（零点或偏好
   纪元 bump）自然重排下一次。
3. 删除 `AppShell` 的 `_midnightRefreshTimer` 字段、
   `_scheduleMidnightDateRefresh` 方法及 `initState`/`dispose` 接线；
   AppShell 不再持有「今天」相关的任何代码。
4. 测试：`test/core/midnight_test.dart` 直测纯函数（23:59:59、整点零点、
   月末、年末、闰日与非闰年二月末）；`test/features/effective_today_test.dart`
   用 `fakeAsync` 加可推进时钟锁 provider 行为（跨零点翻页并重排次日、
   手动日期优先、容器 dispose 取消定时器且推进时间不抛）。
5. 行为保持：消费者零改动；「今天」变化经数据束 → 通知同步快照的既有
   链路传导（`NotificationSyncSnapshot` 含生效今天，ADR 0024 同轮收编），
   不需要新信号。

## 后果

- 「今天永远新鲜」成为 provider interface 的一部分；AppShell 少一个未测试
  的 Timer。
- 定时器只在有人观察「今天」时存活（pause 取消、resume 重排、dispose
  兜底）；生产壳层持续观察，正常路径与常驻同量级。
- 时钟回拨与系统改时间不覆盖（与现状一致）；真机后台跨天行为沿用「恢复
  后补触发」。暂停跨零点只在无人观察时可能发生，生产路径不进入该窗口。
- GLOSSARY 补「生效今天」词条；AGENTS 的 `core/date` 与 provider 总入口
  锚点同步。
