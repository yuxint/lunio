# 03 — 加油记录数据层（DB v3）

**Spec:** `.scratch/four-features-0916/spec.md`

**What to build:** 加油记录的完整数据层：新表、实体、编解码、仓库、providers、动作层。本票无 UI，数据层测试全绿即验收。

**Blocked by:** None — can start immediately.

**Status:** ready-for-human（实现完成；analyze 零问题 + 全量 412 测试绿。本票无 UI、无真机验收面；恢复备份清表名单与备份导出留 04 票，加油页 UI 留 05 票）

- [x] 新表 FuelRecords：id、carId、date（text yyyy-MM-dd）、mileageKm、volumeLiters（real，与油箱容积同精度先例）、totalCostCents（分）、fullTank（bool）+ sync 三列；**不设 {carId, date} 唯一约束**（同日两箱合法）；carId 普通索引
- [x] 数据库 schemaVersion 2→3，表清单注册，跑 build_runner 并检查生成物（ADR 0005：版本不符删库重建，无升级分支）
- [x] 实体 + 行↔实体编解码成对新增（字段清单全库只有一份）；校验：里程/金额非负、升数 >0
- [x] 加油域仓库扩展：按车列表 / 保存（按 id 分新增编辑）/ 更新 / 删除；删车级联删加油记录（复用主仓库借道加油仓库的既有接缝）；恢复备份与清空数据的清理名单留待 04 票，本票先做 clearAllData 清新表
- [x] applied 派生 provider（仿既有加油预测派生模式）+ 按车 family provider；并入车辆家族失效名单
- [x] 动作层新增保存/删除两函数（写库→失效；确认框留调用方）
- [x] 加油记录**不联动**车辆当前里程（保养记录是唯一写源）
- [x] ADR 0014 新增（数据模型部分）+ migration 文档新表 + AGENTS.md 数据库版本号口径
- [x] test/data 全绿：CRUD、同车同日两条、删车级联、清空含新表
