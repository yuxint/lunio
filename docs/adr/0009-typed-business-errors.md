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
