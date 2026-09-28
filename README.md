# Lunio

Lunio 是本地优先的车辆保养记录 App。当前仓库可以按正式第一版文档口径处理，主流程为可交互产品，包括：车辆、保养项目、保养记录、提醒、通知、停车倒计时、加油（油价预测与加油记录）、费用统计、备份恢复、手动日期和主题切换。

## 当前技术栈

- Flutter / Dart
- Riverpod：依赖注入、偏好与业务数据状态
- go_router：平级入口路由 `/reminders`、`/records`、`/me`，条件入口 `/fuel`（加油预测开关打开时才出现在底部导航），以及费用统计子页 `/cost-stats`
- Drift + SQLite：本地数据库、唯一约束、事务、备份恢复
- Material 3 + 自定义 `LunioTokens`：浅色、深色和跟随系统主题
- `flutter_local_notifications`：本地系统通知、保养提醒、停车倒计时通知

## 当前版本范围

- 提醒、记录、我的三入口 App 壳。
- 车辆新增、编辑、删除和当前应用车辆切换。
- 车型默认保养项目 bootstrap、车辆内保养项目配置、启用/禁用和删除限制。
- 保养记录新增、编辑、删除、按周期/按项目查看，以及项目费用（材料/工时/项目费用）软提示。
- 保养提醒进度、状态排序、App 内提醒和系统通知调度。
- 提醒页停车倒计时，包含滚轮入场时间、免费时长、到点通知和 Android 常驻倒计时通知。
- 停车倒计时 iOS 实时活动（iOS 16.2+：锁屏常驻卡片、灵动岛、通知中心顶部，零更新渲染，ADR 0012）。
- 加油页：省份/油品油价、手填价与数据源缓存、加满预估档位（ADR 0001/0002/0011）。
- 加油记录：日期/油品/单价/应付/实付五字段（应付/实付模型，ADR 0015）。
- 费用统计子页（`/cost-stats`）：汇总指标、项目占比、保养费用、加油费用与优惠分摊。
- 保养提醒桌面小组件（iOS WidgetKit，ADR 0013）。
- JSON 备份导出、恢复确认、事务内 replace-import 和清空数据。
- 开发者模式下的手动日期、浅色/深色/跟随系统主题。
- iOS 文件导入导出和通知设置跳转；Android 文件导入导出、通知权限、定时通知 receiver 和 exact alarm 配置。

当前不包含账号登录、云同步、服务端接口、支付预约、图片/OCR，以及保养提醒等其他业务的实时活动。

## 数据版本

- 产品/文档正式版：v1。
- Drift 数据库版本：`schemaVersion = 3`。
- JSON 备份契约：`schemaVersion = 3`。
- 车型目录 asset：`schemaVersion = 1`。

三个契约版本相互独立（升级策略见 `docs/adr/0005`）：数据库纯增量变更（新增表/列）走 `onUpgrade` 增量迁移、存量数据保留，破坏性变更才删库重建；备份解码接受 v1/v2 兼容读（纯增量缺失按空处理）+ v3，其余版本直接拒绝，加油记录结构按 ADR 0015 定义。数据库表、备份字段、偏好 key 和路由语义变更必须同步考虑版本号、测试和文档。

## 发布前仍需确认

- iOS 正式 Bundle ID、开发者团队和签名资料。
- Android 正式 applicationId、namespace 和 release signing config。
- 正式 AppIcon、启动页和商店发布资产。
- Android 物理机回归，尤其是通知权限、文件选择器、系统分享面板、返回键、键盘和安全区。

## 本地验证

```bash
flutter analyze
flutter test
flutter build ios --simulator
flutter build apk
```

纯 Markdown 文档改动优先运行：

```bash
git diff --check
```
