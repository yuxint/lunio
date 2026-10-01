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

## 修订（2026-10-01）：驱动层唯一约束收进类型体系

原决定第 2 条"驱动层的唯一约束冲突（无法在 throw 点包装）保留文本识别
兜底"与 2026-09-26 修订节"文本识别保留为最后防线"的口径作废。原前提
"无法包装"只对 throw 点成立——驱动异常产生在 drift/sqlite3 内部改不了
型，但**包装点可以放在仓库写路径的边界**：`data/repositories/
unique_constraint.dart` 的 `guardUniqueConstraint` 用 try/catch 包住整段
写库动作，把 `SqliteException(extendedResultCode: 2067)`（
SQLITE_CONSTRAINT_UNIQUE）翻译成新 kind `uniqueConstraint`（文案
"这条数据已经保存过了"，与原 friendlyError 文本兜底文案一致）。

- **包装面**：表单提交/恢复备份可直接撞唯一约束的仓库公开写入口——
  主仓库的建车事务/编辑车/新增项目/编辑项目/记录写管线，备份仓库的
  恢复事务（预校验只覆盖保养记录同车同日，payload 内部重复车/同名
  项目仍靠表级约束拦，widget 测试锁定的就是这条路径）。读路径、删除、
  不碰约束列的更新不包；加油域（fuel_records 故意无唯一约束 ADR 0014、
  预测设置为串行 upsert）、偏好门面与目录仓库（内部常量 key 的 upsert/
  对账）也不包。
- **识别只认扩展结果码 2067**，不认泛码 19（SQLITE_CONSTRAINT）——
  泛码还覆盖 NOT NULL/CHECK/外键，把程序 bug 误译成"已保存过"比落
  兜底文案更糟；与原文本匹配的分类语义等价。
- `friendlyError` 收成纯类型识别，`isUniqueConstraintError` 文本匹配
  删除；恢复 UI 的第二级分支从文本识别改为 typed 分支内按 kind 切换
  恢复场景专用文案。改英文措辞、换数据库驱动或升级 Drift 不再影响
  错误分类——当年引入类型化错误的动机至此全部闭环。
- 边界注记：guard 认两种到达形态——进程内连接（NativeDatabase，
  测试与 AppDatabase.forFile）异常以 SqliteException 实例原样上抛；
  生产连接 NativeDatabase.createInBackground 把 SQLite 跑在后台
  isolate，语句异常经 drift 远程协议回传时客户端**无条件**包成
  DriftRemoteException（原始 SqliteException 挂在 remoteCause 字段
  上，与是否序列化无关，drift 2.33.0 communication.dart
  _handleMessage 对每个 ErrorResponse 都包）——guard 对包装形态拆
  remoteCause 认 2067、对直接形态直接认，缺一即生产回归（机制测试
  test/data/unique_constraint_test.dart 后台 isolate 组锁死，2026-10-01
  评审补）。真序列化连接（web/wasm）的 remoteCause 是序列化描述
  而非 SqliteException 实例，认不出、原样透传——本仓生产只有后台
  isolate 连接，不在该场景内。

