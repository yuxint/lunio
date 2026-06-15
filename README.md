# Lunio

Lunio 是本地优先的车辆保养记录 App。当前仓库可以按正式第一版文档口径处理：主流程已经从工程骨架推进到可交互产品，包括车辆、保养项目、保养记录、提醒、通知、停车倒计时、备份恢复、手动日期和主题切换。

## 当前技术栈

- Flutter / Dart
- Riverpod：依赖注入、偏好与业务数据状态
- go_router：三入口路由，当前路径为 `/reminders`、`/records`、`/me`
- Drift + SQLite：本地数据库、唯一约束、事务、备份恢复
- Material 3 + 自定义 `LunioTokens`：浅色、深色和跟随系统主题
- `flutter_local_notifications`：本地系统通知、保养提醒、停车倒计时通知

## 当前版本范围

- 提醒、记录、我的三入口 App 壳。
- 车辆新增、编辑、删除和当前应用车辆切换。
- 车型默认保养项目 bootstrap、车辆内保养项目配置、启用/禁用和删除限制。
- 保养记录新增、编辑、删除、按周期/按项目查看。
- 保养提醒进度、状态排序、App 内提醒和系统通知调度。
- 提醒页停车倒计时，包含滚轮入场时间、免费时长、到点通知和 Android 常驻倒计时通知。
- JSON 备份导出、恢复确认、事务内 replace-import 和清空数据。
- 开发者模式下的手动日期、浅色/深色/跟随系统主题。
- iOS 文件导入导出和通知设置跳转；Android 文件导入导出、通知权限、定时通知 receiver 和 exact alarm 配置。

当前不包含账号登录、云同步、服务端接口、支付预约、图片/OCR、iOS Live Activity 或 Widget Extension。

## 数据版本

- 产品/文档正式版：v1。
- Drift 数据库版本：`schemaVersion = 4`。
- JSON 备份契约：`schemaVersion = 2`。

不要把产品文档 v1 与数据库/备份契约版本混用。数据库表、备份字段、偏好 key 和路由语义变更必须同步考虑迁移、兼容、测试和文档。

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
