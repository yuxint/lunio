// 检测点解析类型枚举（ADR 0021 决定 5）：一条 OBD 响应如何翻译成
// 页面上的数值。四种覆盖内置三条种子与常见标准 PID；自由公式表达式
// 是 v2（ADR 0021，避免背上 DSL 安全与校验负担）。
//
// Java 对照：JPA @Enumerated(EnumType.STRING) 枚举列——wire 值显式收在
// 枚举里（数据库 diagnostics_probes.parseType 列、备份 JSON 诊断段的
// parseType 字段、表单选项），序列化/反序列化不用反射。
//
// 解析语义（协议事实见 docs/car_obd_link/）：
//  - 油量百分比：Mode 01 `012F`，响应 `41 2F` 后首字节的百分比；
//  - 温度：Mode 01 `0105`，响应 `41 05` 后首字节 A，温度 = A − 40 ℃；
//  - 电压文本：AT 命令（如 `ATRV`）直接返回文本（如 "12.5V"）；
//  - 原始 hex：未知指令的兜底，响应原文照显（story 24）。
//
// 注意：本枚举只声明"怎么解析"，不含解析实现——PID 公式、hex 提取
// 等纯函数在诊断域的解析模块（后续票），此处不放逻辑。
enum DiagnosticsParseType {
  /// 油量百分比（内置种子 `012F`）。
  fuelLevel('fuelLevel', '油量百分比'),

  /// 温度（A−40 ℃，内置种子 `0105`）。
  coolantTemp('coolantTemp', '温度（A−40）'),

  /// 电压文本（内置种子 `ATRV`，响应即文本）。
  voltageText('voltageText', '电压文本'),

  /// 原始 hex 兜底：未知指令的响应原文照显。
  rawHex('rawHex', '原始 hex');

  const DiagnosticsParseType(this.wire, this.label);

  /// 存储/序列化值（数据库 parseType 列、备份 JSON、表单选项）。
  /// 备份 v4 起该值进 JSON 契约，改值=破坏备份兼容，须慎之又慎。
  final String wire;

  /// UI 展示文案（检测点表单的解析类型选项）。
  final String label;

  /// 按存储值解析；未知值抛 ArgumentError（fail-fast，坏数据不静默降级，
  /// 与 PowertrainType.byWire 同先例）。
  static DiagnosticsParseType byWire(String wire) {
    return DiagnosticsParseType.values.firstWhere(
      (type) => type.wire == wire,
      orElse: () => throw ArgumentError('Unknown diagnostics parse type: $wire'),
    );
  }
}
