# 06 — 花费统计（聚合 + 页面 + 入口）

**Spec:** `.scratch/four-features-0916/spec.md`

**What to build:** 保养花费全貌：记录页一行今年花费汇总（可点），独立统计页（总/今年花费、按年横条、项目占比 Top、近 12 个月走势、车辆切换），我的页入口。纯读取聚合，不动数据库。

**Blocked by:** None — can start immediately.

**Status:** ready-for-human（实现完成：analyze 零问题 + 全量 447 测试绿；聚合纯函数 17 单测 + 4 轮变异验证全被击杀；顺带修复 LocalDate.addMonths 负数月份 bug（floor 语义）+ 回归测试。统计页视觉自查待人工）

- [x] 聚合纯函数（features 层新文件 `records/cost_stats.dart`，仿记录行组装惯例）：输入全量记录+项目清单，输出年度花费、近 12 个月走势、项目占比 Top N。口径：总额/年度/月度用记录总费用（权威值）；项目占比＝项目费用 ?? 材料+工时，再缺跳过该行。单测含 null 口径 + 变异验证
- [x] 独立统计页 `/cost-stats`：首个非 tab pushed 路由先例（默认转场、不挂主壳层）；路由单例注释同步；注意保持「主题切换不重建路由」约定
- [x] 顶部栏组件加可选 leading 位（返回键）；iOS 右滑返回天然可用
- [x] 页面内容（自绘横条，不引图表库）：总花费+今年花费汇总、按年横条、项目占比 Top N（项目名经项目清单解析，同名跨车合并）、近 12 个月走势；空态（无记录/无车）处理
- [x] 车辆切换 chips：当前用车默认，可切单车/全部；「全部」经按车记录 family provider 聚合（新增 `recordsForCarProvider` 复用既有按车取全量记录仓库方法，无新 SQL；已进 invalidateVehicleProviders 整族失效名单）
- [x] 记录页头部汇总行：今年花费 + 引导文案，整行可点进统计页；仅记录非空显示；放 header 的 data 分支
- [x] 我的页「花费统计」设置行进同一页
- [x] DESIGN.md 新增「Cost Statistics」小节（自绘横条/走势柱为全新视觉模式）+ operations-manual 新增 §4.5 统计页与入口章节
- [x] 聚合单测（17 条）+ widget 测试（8 条：页面渲染/车辆切换/空态×2/返回键/记录页汇总行×2/我的页入口）；`flutter analyze` 全绿
