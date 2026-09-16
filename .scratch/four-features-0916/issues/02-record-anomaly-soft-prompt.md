# 02 — 记录合法性软提示

**Spec:** `.scratch/four-features-0916/spec.md`

**What to build:** 新增/编辑保养记录第一步点「下一步」时，若草稿与已有记录构成「里程不随日期单调非降」，弹确认框说明冲突（含参照记录的日期与里程），用户可选「仍要继续」（放行进第二步）或「返回修改」（留在第一步）。软提示不拦截保存，两分支都不写库。

**Blocked by:** None — can start immediately.

**Status:** ready-for-human（实现完成；analyze + 全量 398 测试绿，无真机验收面，随手用一下即可）

- [x] 领域规则进 RecordRules 新纯函数：输入该车全量记录 + 草稿（日期/里程/自身 id），输出冲突参照记录或 null；判定＝存在 R 晚于草稿且里程更低、或早于草稿且里程更高；同日跳过（同日冲突由既有查重/唯一约束兜底）；编辑排除自身
- [x] 触发点在表单第一步「下一步」：新增与编辑都查（区别于同日查重只查新增）；记录数据未就绪跳过（保存时既有校验兜底）
- [x] 确认框仿同日查重模式：标题「与已有记录不一致」、文案含参照记录日期+里程、confirm「仍要继续」、cancel「返回修改」
- [x] 领域单测：命中两个方向、不命中、编辑排除自身；核心规则做变异验证
- [x] Widget 测试三态：弹窗出现、仍要继续进第二步、返回修改留在第一步（prior art：records 测试的查重弹窗用例）
- [x] `flutter analyze` + 相关 domain/records 测试全绿

## Comments

- 2026-09-17 实现：`RecordRules.conflictingMileageRecord`（domain 纯函数）+ 表单 `_goToIntervalStep` 改 async 接软提示（`_findMileageConflict` / `_showMileageConflictDialog`，进第二步逻辑抽成 `_enterIntervalStep` 共用出口）。变异验证 5 处（日期边界 ×2、里程边界 ×2、删自身排除）全部被测试抓住。
- 测试：领域 3 个新用例（双向命中 / 同日·等里程·单调不命中 / 编辑排除自身）；widget 4 个（三态 + 编辑态也弹，编辑态夹具播两条记录改里程触发）。全量 398 绿。
- 文档已同步：operations-manual §4.2 步骤 2a + 入口段、CONTEXT.md 新增「记录合法性软提示」词条组。
