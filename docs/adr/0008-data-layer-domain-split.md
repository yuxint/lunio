# ADR 0008：数据层按域拆分（偏好门面 / 目录 / 加油 / 备份 / 主仓库）

日期：2026-09-03
状态：已接受

## 背景

`LunioRepository` 增长为 1917 行、45 个 public 方法的单一类，按文件内自己的
分节注释就横跨 7 个业务域：目录对账、车辆、保养项目、保养记录、备份、偏好
KV、停车倒计时、加油、清库。调用方（11 个 UI 文件、37 处引用）面对的是一张
45 项的平铺清单——学这份接口的成本约等于全部实现之和，没有任何分组替调用
方挡住"我不关心的另外 6/7"。

同时偏好存取是字符串协议：key 魔法串散在 5 个文件，`'true'/'false'` 比较、
`LocalDate.tryParse`、默认值语义在 providers.dart 与各调用点重复手写；key
清单的"单一事实来源"实际上是 AGENTS.md 文档而非代码。

## 决定

1. **按域拆成仓库家族**（都在 `lib/data/repositories/`，经 providers.dart
   装配，互不嵌套）：
   - `LunioRepository`（主仓库）：只保留车辆/保养项目/保养记录核心域——
     三个域共享事务（建车带项目、记录带项目更新、删车级联）；
   - `BuiltInCatalogRepository`：车型目录与默认模板两张内置表 + 首启
     bootstrap 幂等对账（与核心域零耦合，自带目录 asset memoize）；
   - `FuelRepository`：加油预测设置表 + 油价缓存/手填油价；删车级联时
     主仓库借道 `fuel.deleteForCar()` 删预测行，表知识不越过它的接缝；
   - `BackupRepository`：备份导出/恢复/清空数据（数据生命周期域）。
2. **偏好收进 `LunioPreferences` 门面**（`lib/data/preferences/`）：
   全部 key 常量、编解码（`'true'/'false'`、themeMode、LocalDate、通知
   三键批量读、停车倒计时 JSON；油价 JSON 除外——归加油域）与
   typed 读写收在一处；调用方只见 typed 方法，不再拼 key 字符串。
   通知抑制 key 的前缀常量也登记于此：写入方（通知协调器拼 key）与
   清除方（恢复备份按前缀删）共用同一组常量。
3. **共享行编解码**：`entity_row_codec.dart` 顶层函数提供每表一份的
   Row→实体 与 实体+id→Companion 构造。新增/恢复两条插入路径共用同一
   份字段清单（"恢复的数据过和手工录入同样的规则"在插入层也成立）；
   给表加字段从改 3 处（插入 helper/恢复循环/更新 helper）变为改 1 处
   编解码 + backup_codec 的 JSON 契约。
4. **id 生成器共享**：`SnowflakeIdGenerator.instance` 进程级单例。
   多模块必须从同一实例发号——两个实例在节点号相同、同一毫秒内会发出
   重复主键。
5. **主仓库构造函数保留可选默认装配**（不传偏好门面/加油仓库时按同一
   数据库连接自行 new）：模块无状态，多实例等价，测试可以只
   `LunioRepository(database)`；偏好门面只收数据库，加油/备份仓库的
   依赖为必填参数，经 providers.dart 统一装配。

## 后果

- 每个调用方只见自己域的 5-8 个方法；providers.dart 的装配关系图是
  唯一的模块关系清单。
- schemaVersion、备份契约、偏好 key 字符串与取值语义全部原样不变；
  本决定不涉及任何数据迁移（ADR 0005 口径不变）。
- 测试侧：`test/data/` 各文件按域装配模块；widget 测试经
  `test/helpers/widget_app.dart` 的 `TestRepositories` 门面播种
  （那是测试专用的一揽子引用，不是生产模块边界）。
- 油价缓存/手填油价两个 key 留在 `FuelRepository`（加油域的临时业务
  数据）而非偏好门面，经门面的 `readRaw/writeRaw` 原语存取——"key 在
  哪个模块登记"跟着业务归属走，不跟着存储介质走。
