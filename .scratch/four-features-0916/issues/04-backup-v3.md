# 04 — 备份 v3（含加油记录）

**Spec:** `.scratch/four-features-0916/spec.md`

**What to build:** 备份契约升 v3：导出包含加油记录，旧版本（v1/v2）文件导入不报错、加油记录按空处理，恢复与清空正确处理新表。

**Blocked by:** 03 — 加油记录数据层（DB v3）

**Status:** ready-for-agent

- [ ] 备份编解码器：currentSchemaVersion=3、接受 [1,2,3]；payload 新增加油记录数组（默认空）；encode 补一段；decode 对新字段「缺失按空读入」（纯增量缺失，沿用 ADR 0010 先例）；文件头契约注释同步
- [ ] 备份仓库导出：补一次加油记录全量读
- [ ] 恢复事务：加油记录 carId 按 旧→新 映射重插；引用完整性校验加 carId 存在性检查；「恢复清表」名单加新表
- [ ] 备份 v3 round-trip 测试（含加油记录）；v2/v1 兼容读测试（沿用 codec 测试的字符串替换手法）；恢复重映射与孤儿 carId 拒绝测试；恢复/清空后加油记录清空测试
- [ ] AGENTS.md 备份版本号口径 + ADR 0014 备份章节（v2 纯增量兼容读）
- [ ] test/data 备份相关全绿
