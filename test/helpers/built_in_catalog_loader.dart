// 测试辅助：从磁盘读取按字母分片的内置车型目录，拼装成与旧单文件
// 相同结构的 JSON Map，供 BuiltInVehicleCatalog.fromJson 解析。
// （生产环境走 lib/data/bootstrap/built_in_vehicle_catalog.dart 的
// rootBundle 版本；测试直读文件是为了不依赖 AssetBundle。）
import 'dart:convert';
import 'dart:io';

import 'package:lunio/data/bootstrap/built_in_vehicle_catalog.dart';

/// 分片所在目录（相对仓库根，与 flutter test 的工作目录一致）。
const _catalogDir = 'assets/data/catalog';

/// 车型分片的字母清单（与生产加载器保持一致）。
const _shardLetters = [
  'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm',
  'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
];

/// 读取分片目录并拼装成完整目录 JSON Map。
Map<String, Object?> loadBuiltInCatalogJson() {
  final templates =
      jsonDecode(File('$_catalogDir/templates.json').readAsStringSync())
          as Map<String, Object?>;
  final vehicles = <Object?>[];
  for (final letter in _shardLetters) {
    final shard =
        jsonDecode(File('$_catalogDir/vehicles_$letter.json').readAsStringSync())
            as Map<String, Object?>;
    vehicles.addAll((shard['vehicles'] as List?) ?? const []);
  }
  return {
    'schemaVersion': 2,
    'templates': templates['templates'],
    'vehicleTemplates': templates['vehicleTemplates'],
    'vehicles': vehicles,
  };
}

/// 便捷入口：直接得到解析后的目录对象。
BuiltInVehicleCatalog loadBuiltInVehicleCatalogForTest() {
  return BuiltInVehicleCatalog.fromJson(loadBuiltInCatalogJson());
}
