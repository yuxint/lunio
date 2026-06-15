# Flutter 迁移分批计划归档

本文是历史迁移计划归档，不再作为当前待执行计划使用。Lunio 当前已经进入正式 v1 文档口径，现状以 `README.md`、`docs/prd/business-logic-prd.md`、`docs/migration/current-database-schema.md` 和 `docs/migration/migration-implementation-report.md` 为准。

## 归档结论

早期迁移按 Batch 0-8 推进，目标是从 Flutter 工程骨架逐步落到可用的车辆保养 App。当前这些批次对应的主能力都已落地或转化为发布前事项。

历史批次：

- Batch 0：技术底座收口。
- Batch 1：设计系统与 App 壳。
- Batch 2：车辆与当前应用车辆。
- Batch 3：保养项目配置。
- Batch 4：保养记录。
- Batch 5：保养提醒。
- Batch 6：个人中心与数据能力。
- Batch 7：iOS 首版打磨。
- Batch 8：Android 补齐。

## 当前文档口径

- 产品/文档正式版：v1。
- Drift 数据库版本：`schemaVersion = 4`。
- JSON 备份契约：`schemaVersion = 2`。
- 当前主入口：`/reminders`、`/records`、`/me`。
- 当前能力已经包含车辆、保养项目、保养记录、提醒、通知、停车倒计时、备份恢复、手动日期、主题和基础 Android/iOS 平台适配。

## 不再沿用的旧口径

- 不再把工程描述为只交付技术底座。
- 不再把主界面描述为占位 App 壳。
- 不再把备份契约描述为 v1 payload。
- 不再把暗色模式作为待确认能力；当前代码已有浅色、深色和跟随系统主题。
- 不再把 Android 工具链补齐当成迁移待办；当前剩余的是发布前真机回归和正式签名/包名确认。

## 后续规划方式

后续新功能或重构不要继续追加 Batch 编号。推荐直接按需求建立更小的文档或 issue，明确：

- 目标行为。
- 影响的代码入口。
- 数据契约是否变化。
- 需要同步更新的文档。
- 验证命令和手动回归范围。
