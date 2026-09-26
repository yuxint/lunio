# ADR 0017：偏好派生缓存改"偏好纪元"，删除手工失效名单

日期：2026-09-26
状态：已接受（取代 providers.dart 的手工失效名单模型；车辆类家族手动失效不变，见 ADR 0007）

## 背景

providers.dart 有一组手工失效名单函数：`_invalidatePreferences`（11 项）+
`invalidatePreferenceProviders`（WidgetRef 薄壳）+
`invalidatePreferenceProvidersWithRef`（Ref 薄壳）+
`invalidateFuelPreferenceProviders`（重列其中 6 项的 fuel 子集）。「哪些
provider 读偏好表」这一份知识存了两遍、跨两个文件，靠 providers.dart ↔
fuel_prices.dart 的循环 import 缝合（fuel_prices 一边 import 组合根取
Bean，providers.dart 一边为名单引用油价域 provider）；`WidgetRef` 与
`Ref` 无公共父型、riverpod 未导出 `ProviderOrFamily`，名单实现里还有一
个 `dynamic` 强转。新增偏好派生 provider 时要记得去另一个文件改名单，
漏一处即跨页陈旧（providers.dart 头注释自己承认这个失败模式）——失败
模式藏在被影响代码之外，review 不可见。

仓库已有同构先例：通知同步代数（`notification_sync_guard.dart` 的
`NotifierProvider<int>`，CONTEXT.md「同步代数」）——偏好表缺的只是同一
个"数据版本号"。

## 决定

1. providers.dart 新增 `preferencesEpochProvider`
   （`PreferencesEpoch extends Notifier<int>`，build 返回 0，bump() 自增）
   ——偏好表数据的版本号，与同步代数同构。
2. 全部偏好派生 provider 在 build 首行 `ref.watch(preferencesEpochProvider)`
   （2026-09-26 时点共 11 个：providers.dart 7 个——开发者模式/手动日期/
   生效日期/主题/通知设置/加油开关/当前车加油预测设置；fuel_prices.dart
   4 个——省份/油品/手填价/油价控制器）。
3. 写点动作改为写完库 bump 一次：动作层 7 个偏好类函数
   （setThemeModePreference / saveManualDate / setDeveloperModeEnabled /
   setFuelPredictionEnabled / saveFuelProvince / saveFuelGrade /
   saveFuelManualPrice）+ 通知协调器 3 个偏好写点
   （reconcileSystemEnabled / markSystemNotificationsDisabled /
   saveNotificationSettings）。四个名单函数删除；providers.dart 不再
   import fuel_prices.dart，循环 import 消失；`dynamic` 强转随之蒸发
   （`ref.read(epoch.notifier)` 对 WidgetRef/Ref 都成立，不需要公共父型）。
4. 失效粒度统一为全局一刀切（grilling 拍板）：原 saveFuelManualPrice 的
   单点失效、saveFuelProvince/Grade 的 fuel 子集失效并入全局 bump。多出
   的重算都是本地 SQLite 单行读，且这些 provider 在今天其他写点上本来
   就会被粗粒度逐出，无新增风险面。
5. 边界保持（grilling 拍板）：
   - `appliedCarFuelPredictionProvider` 读的是加油预测**设置表**不是偏好
     表，但随纪元走（保持旧名单集合、边界不动）；其真实写点
     （`saveFuelBaseline`，档位落库）保留精准单点失效——该表不在纪元
     覆盖内。
   - `parkingCountdownProvider` 不入纪元：它是"写点直失效自己"模型
     （saveParkingCountdown / clearParkingCountdown 各自 invalidate），
     偏好写入不牵动停车卡。机制测试用负控制用例锁住这条边界。
6. 车辆/记录类家族（`invalidateVehicleProviders`）维持手动失效模型不变
   ——它们逐出的是 DB 表派生缓存，写点与读者都是动作层已知的封闭集合。

## 后果

- 「哪些 provider 读偏好表」的知识回到 provider 自己的 build 里（watch
  行与读偏好代码相邻），新增偏好派生 provider 的成本是本地一行；漏
  watch 只让该 provider 自己陈旧，不再殃及名单。
- providers.dart ↔ fuel_prices.dart 循环 import 消失（油价域单向依赖
  组合根）；`dynamic` 强转消失。
- 机制测试面：`test/features/preferences_epoch_test.dart`（bump → 两个
  域各一个抽样 provider 重查库 + 停车负控制），防止 watch 行将来被当
  废代码删掉。
- 写偏好后的失效从"逐出 N 个 provider"变"纪元 +1、被 watch 的自动重算"，
  部分写点的被逐出集合略有扩大（决定 4 的粗化），无行为回归面。
- 新增偏好派生 provider 的失败模式从"记得改另一个文件的名单"变"记得在
  自己 build 里 watch 纪元"——两者都是记忆负担，但后者写在被影响代码
  旁边，review 可见。

## 备选方案

- **名单归域所有**（fuel 名单搬进 fuel_prices.dart）：去重达成，但
  riverpod 未导出 `ProviderOrFamily`，名单只能以函数形态搬家，`dynamic`
  强转与循环 import 都保留——三个摩擦只解一个，不取。
- **偏好门面响应式化**（偏好变 watched state）：动 `LunioPreferences`
  门面契约（AGENTS.md 保护）、备份 readRaw、20 个 typed 方法，收益相同
  而改动面大一个量级，YAGNI。
- **按 key 细分纪元**（每类偏好一个版本号）：失效更精准，但今日名单本
  就是粗粒度、本地读成本可忽略，机器多一倍不值得。
