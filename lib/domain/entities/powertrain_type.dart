// 动力类型枚举：添加车辆时用户选择的车辆动力形式。
//
// 与目录"推荐动力类型"（预选值）、默认保养模板的分组键一一对应：
// 燃油→fuel 模板、混动→hybrid、插混→plugIn、增程→extended（内容同插混）、
// 纯电→ev。wire 值是数据库列、备份 JSON、目录 asset 里存的字符串。
//
// Java 对照：类似 JPA 的 @Enumerated(EnumType.STRING) 枚举列，
// 这里把"存储值"显式收在枚举里，序列化/反序列化不用反射。
enum PowertrainType {
  fuel('fuel', '燃油'),
  hybrid('hybrid', '混动'),
  plugIn('plugIn', '插混'),
  extendedRange('extended', '增程'),
  electric('ev', '纯电');

  const PowertrainType(this.wire, this.label);

  /// 存储/序列化值（数据库 cars.powertrainType 列、备份 JSON、目录 template 字段）。
  final String wire;

  /// UI 展示文案（选择 chip、编辑车辆只读行）。
  final String label;

  /// 按存储值解析；未知值抛 ArgumentError（fail-fast，坏数据不静默降级）。
  static PowertrainType byWire(String wire) {
    return PowertrainType.values.firstWhere(
      (type) => type.wire == wire,
      orElse: () => throw ArgumentError('Unknown powertrain type: $wire'),
    );
  }
}
