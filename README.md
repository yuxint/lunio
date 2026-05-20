# Lunio

Lunio 是车辆保养记录 App 的 Flutter 单仓重构工程。当前阶段只交付技术底座，不包含完整业务 UI。

## 当前技术栈

- Flutter stable / Dart
- Riverpod：运行时上下文、仓储注入、状态管理
- go_router：三大主入口路由
- Drift + SQLite：本地持久化、唯一约束、事务与后续同步扩展
- schemaVersion 1：新备份数据契约，不兼容旧 iOS/Android 本地数据

## 已落地范围

- iOS/Android Flutter 工程骨架
- 设计 token 主题接入
- 提醒 / 记录 / 我的三入口占位 App 壳
- 车辆、保养项目、保养记录、当前应用车辆、手动日期相关基础规则
- Drift 数据库 schema 与本地 Repository
- 新版 JSON 备份 codec 雏形
- 单元测试、数据层测试、widget smoke test

## 本地验证

```bash
flutter analyze
flutter test
flutter build ios --simulator
```

当前优先 iOS。Android SDK 尚未配置时，`flutter doctor` 会报告 Android toolchain 缺失，不影响 iOS 构建。
