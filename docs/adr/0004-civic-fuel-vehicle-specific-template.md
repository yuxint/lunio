# ADR 0004：思域恢复车型专属保养模板（civicFuel）

日期：2026-09-01
状态：已接受（部分修订 ADR 0003 决定 4）

## 背景

ADR 0003 把默认保养模板收敛为按动力类型五组（fuel/hybrid/plugIn/extended/ev），
删除了老目录里思域专属的 civicFuel 精修模板（14 项，比燃油通用组多：
燃油宝、检查传动皮带、检查气门间隙、检查刹车，间隔值也按思域保养手册精修过）。
动力类型粒度的通用模板对绝大多数车型够用，但产品决定思域要保留这份专属精度。

## 决定

1. **templates.json 顶层新增 `vehicleTemplates`（车型专属模板区）**，与
   `templates`（动力类型组）并列；先放 `civicFuel` 一组，内容 = 老目录原
   14 项，字段格式与通用模板完全一致。
2. **目录条目新增可选字段 `itemTemplate`**，引用 vehicleTemplates 的键。
   思域条目 `template` 仍为 `fuel`（推荐动力类型不变，动力 chip 预选不受
   影响），另加 `itemTemplate: "civicFuel"`。加载器 fail-fast 校验：
   itemTemplate 必须能在 vehicleTemplates 里找到。
3. **专属模板不进数据库**：`vehicle_default_maintenance_items` 表仍只存
   五个动力类型组；Repository 新增 `listDefaultItemsForVehicleModel`，
   添加向导取默认项目时按（品牌+车型 命中目录条目 + 条目带 itemTemplate +
   用户所选动力类型 = 推荐动力类型）返回内存实体（catalogId 前缀
   `vtpl:`，与库里的 `tpl:` 区分）。
4. **未命中一律回退动力类型通用模板**：改选了其他动力类型（思域改选纯电）、
   非目录自定义车型、无 itemTemplate 的目录车型，行为与 ADR 0003 完全一致。
   向导第二步"恢复默认项目"的候选列表跟随加载结果，思域即 14 项。

## 后果

- 数据库 schema（v9）、备份契约（v4）都不变；已有用户的车辆与项目不受影响
  （模板只在添加车辆预填与向导内恢复时使用）。
- 动力类型粒度的默认模板仍是主规则；车型专属是白名单式例外，目前仅思域一条，
  不重新打开"品牌+车型逐条模板"的旧模式。
- `car_library/` 源数据与 `build_catalog.py` 生成脚本已移出仓库，本次为直接
  手改生成的目录 JSON；以后重抓目录时需把该例外并入生成链路。
- 模板键 `civicFuel` 不是动力类型 wire 值，只存在于 vehicleTemplates 区；
  动力类型解析（`PowertrainType.byWire`）不经过它。

## 备选方案

- **civicFuel 行写入 `vehicle_default_maintenance_items` 表、powertrainType
  列存 `'civicFuel'`**：该列语义是动力类型 wire 值，实体按枚举解析、未知值
  fail-fast 抛错，等于改列契约并牵连迁移/备份，拒绝。
- **在向导代码里硬编码思域 14 项**：业务数据进 UI 层，违反"默认数据由目录
  asset + Repository 提供"的既有约定，拒绝。
- **恢复品牌+车型逐条模板（老目录模式）**：1600+ 条目养不起人工模板，
  只恢复思域一个例外即可，拒绝。
