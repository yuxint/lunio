# ADR 0009：业务错误 typed 化（LunioErrorException + kind 枚举）

日期：2026-09-03
状态：已接受

## 背景

Repository 的错误接口事实上是"无类型异常 + 约定英文消息子串"：主仓库抛
`StateError('这辆车当天已有保养记录…')`、`ArgumentError('At least one
maintenance item must stay enabled')` 等，UI 的翻译层 `friendlyError`
靠 `message.contains('英文子串')` 认领并翻成中文。改一条英文措辞，对应
文案就静默退回兜底"操作失败，请稍后重试"，编译期毫无报警。调用方要正确
使用写方法，必须额外知道"哪些异常消息文本会被翻译层认领"这份隐藏清单。

## 决定

1. **表单提交路径的业务规则失败改抛 `LunioErrorException`**
   （`lib/domain/errors/lunio_error.dart`）：kind 枚举是错误码
   （duplicateMaintenanceRecord / lastEnabledMaintenanceItem /
   maintenanceItemHasHistory / missingRecordItems / itemFromAnotherCar），
   `message` 就地书写用户可读中文——文案的单一事实来源在 throw 点。
2. **翻译层按类型认领**：`friendlyError` 对 `LunioErrorException` 直接
   透出 message；数据库驱动层的唯一约束冲突（SqliteException 2067，无法
   在 throw 点包装）保留文本识别兜底；其余异常兜底通用文案。英文消息
   子串匹配清单删除。
3. **范围刻意收窄**：只收"表单提交路径上需要翻译成行内提示的业务规则
   失败"。备份预校验的中文 ArgumentError（UI 直接 toast 拼接展示）、
   内部不变量断言（`ArgumentError('Car id is required')` 之类）维持
   原类型不变。
4. **配套**：表单的"校验 → saving=true → try 提交 → catch 行内回显 →
   finally 复位"骨架收进 `shared/form_submit.dart` 的 `LunioFormSubmit`
   mixin（`runSubmit` / `setFormError` / `saving` / `errorText`），
   有行内错误位的标准表单直接混入；无错误展示位的表单（通知设置、
   提醒弹窗、向导第二步）保持原状，异常照旧穿透给外层反馈。

## 后果

- 改文案不再影响错误路由；测试断言按 kind 而非文本（database_test 已
  升级为 `having((e) => e.kind, ...)`）。
- 新增业务失败 = 加一个 kind + throw 点写中文文案 + 测试断言 kind，
  三步都在代码内完成，不依赖文档记忆。
- 驱动层的 2067 兜底仍是文本匹配——若未来 drift 提供类型化异常，可把
  这段也收进类型体系。

## 修订（2026-09-26）：恢复拒绝纳入类型体系

恢复备份的预校验失败从"中文 ArgumentError + UI toast 拼接"迁为
`LunioErrorKind.backupInvalidData`（单一 kind 承载全部恢复拒绝——R35
的实体校验包装与新增的保养记录同车同日查重，区分度全在 throw 点文案），
原决定第 3 条中"备份预校验维持中文 ArgumentError"的口径作废。

理由：恢复拒绝是用户可行动的已知失败，具体原因（哪辆车哪天几条重复、
哪个字段非法）应出现在对话框里，而不是退化成 toast；此前已知拒绝里
唯一会弹对话框的路径是驱动层唯一约束（靠嗅异常文本分类，ADR 0009 明文
的兜底口径），同日查重预检补进备份仓库后（backup_repository
`_validateBackupBusinessRules` 末段，事务外），已知失败不再依赖驱动层
异常与文本匹配。

恢复 UI（profile_page `_restoreBackup`）按类型三级分支：typed 拒绝 →
对话框给 throw 点具体原因（统一附"本次恢复未写入任何数据"）；驱动层
唯一约束 → 通用对话框（文本识别保留为最后防线）；其余 → toast。
内部不变量断言（恢复事务内的英文 ArgumentError、引用完整性预校验）
维持原类型不变。
