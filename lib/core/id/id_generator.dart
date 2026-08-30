// UUID id 生成器（≈ Java 的 java.util.UUID.randomUUID）。
//
// ⚠ 死代码：全项目没有任何调用方（Repository 实际用雪花 id），
// 且它引入的 uuid 依赖因此成为可移除项（审查报告 R29）。
// 保留仅作参考，不建议新代码使用。
import 'package:uuid/uuid.dart';

class IdGenerator {
  const IdGenerator([Uuid? uuid]) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  /// 生成 UUID v4 随机字符串。
  String next() => _uuid.v4();
}
