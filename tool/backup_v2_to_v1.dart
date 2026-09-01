// 一次性数据转换脚本：把旧版（schemaVersion: 2）备份 JSON 转成当前契约
// （schemaVersion: 1）能导入的备份文件。
//
// 不在 App 内运行，属于仓库工具脚本（≈ Java 项目里放维护目录的一次性
// main 类），用 `dart run` 执行。
//
// 背景（ADR 0005）：备份解码只认 schemaVersion=1，且要求 Car 必须带
// powertrainType、保养项目必须带两个进度上限字段；旧版 v2 备份缺这些
// 字段，直接导入会被第一道解码拒绝。本脚本只处理这一种旧格式。
//
// 转换规则（只改必须改的，其余字段原样保留）：
//  - 顶层 schemaVersion: 2 → 1；
//  - cars 补 powertrainType（旧数据没有动力概念，按燃油车处理）和
//    tankCapacityLiters: null（可空字段，导入允许为空）；
//  - maintenanceItems 补 notOverdueUpperLimit / overdueUpperLimit，
//    取值直接读 MaintenanceItem 构造默认值，避免手写一份会过期的契约数字；
//  - sync.status 统一改 synced：当前纯本地 App 的写入约定是"所有数据
//    status 恒为 synced"（见 SyncMetadata 文件头注释），updatedAt/version 保留旧值；
//  - 顶层 fuelPrediction / fuelPredictions 由 BackupCodec.encode 补齐
//    （旧数据没有加油设置，输出 null / 空数组）。
//
// 用法：
//   dart run tool/backup_v2_to_v1.dart <旧版备份.json> [输出.json]
// 不给输出路径时，写到输入文件同目录，按 App 导出命名规则生成
// lunio-backup-yyyyMMdd-HHmmss.json。
//
// 安全性：转换结果先过 BackupCodec.decode（与 App 导入完全相同的第一道
// 严格校验），再复刻 Repository 恢复前的引用/业务校验与两处数据库唯一
// 约束，最后用 BackupCodec.encode 输出，保证文件形状与 App 真实导出一致。
// 任一步失败立即退出，不写输出文件。
import 'dart:convert';
import 'dart:io';

import 'package:lunio/data/backup/backup_codec.dart';
import 'package:lunio/domain/entities/maintenance_item.dart';
import 'package:lunio/domain/entities/powertrain_type.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';

/// 只为读取 MaintenanceItem 的两个上限默认值（100/125），
/// 避免在脚本里硬编码一份会和实体默认值脱节的数字。
final MaintenanceItem _defaultLimitsItem = MaintenanceItem(
  carsId: 0,
  name: '',
  enabled: true,
  remindByMileage: true,
  remindByTime: true,
  sortOrder: 0,
  sync: SyncMetadata(
    status: SyncStatus.synced,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
  ),
);

void main(List<String> args) {
  if (args.isEmpty || args.length > 2) {
    stderr.writeln('用法: dart run tool/backup_v2_to_v1.dart <旧版备份.json> [输出.json]');
    exit(64);
  }
  final inputPath = args[0];
  final inputFile = File(inputPath);
  if (!inputFile.existsSync()) {
    stderr.writeln('输入文件不存在: $inputPath');
    exit(66);
  }

  final raw = jsonDecode(inputFile.readAsStringSync()) as Map<String, Object?>;
  if (raw['schemaVersion'] != 2) {
    stderr.writeln('输入文件 schemaVersion=${raw['schemaVersion']}，本脚本只处理旧版 v2 备份');
    exit(65);
  }

  final converted = <String, Object?>{
    'schemaVersion': BackupCodec.currentSchemaVersion,
    'cars': _listOfMaps(raw['cars'], 'cars').map(_convertCar).toList(),
    'maintenanceItems':
        _listOfMaps(raw['maintenanceItems'], 'maintenanceItems')
            .map(_convertItem)
            .toList(),
    'records':
        _listOfMaps(raw['records'], 'records').map(_convertRecord).toList(),
  };

  // 第一道门：与 App 导入完全相同的严格解码（版本、字段类型、日期格式、枚举值）。
  final payload = const BackupCodec().decode(jsonEncode(converted));

  // 第二道门：恢复前的引用完整性 + 事务内唯一约束，提前到写文件之前检查。
  _validateForRestore(payload);

  // 用编码器输出，保证与 App 自身导出的文件形状逐字段一致。
  final outputJson = const BackupCodec().encode(payload);
  final outputPath = args.length == 2 ? args[1] : _defaultOutputPath(inputPath);
  File(outputPath).writeAsStringSync(outputJson);

  final recordItemLinks = payload.records
      .fold<int>(0, (sum, record) => sum + record.itemIds.length);
  stdout.writeln(
    '转换完成: ${payload.cars.length} 辆车 / '
    '${payload.maintenanceItems.length} 个保养项目 / '
    '${payload.records.length} 条记录 / $recordItemLinks 条记录-项目关联',
  );
  stdout.writeln('输出文件: $outputPath');
}

/// 取顶层 JSON 数组且每个元素必须是对象；key 缺失视为空数组（与 decode 行为一致）。
List<Map<String, Object?>> _listOfMaps(Object? value, String name) {
  return ((value as List?) ?? const [])
      .map((element) => (element as Map).cast<String, Object?>())
      .toList();
}

Map<String, Object?> _convertCar(Map<String, Object?> car) {
  return {
    'id': car['id'],
    'brand': car['brand'],
    'model': car['model'],
    // 旧数据没有动力类型概念，统一按燃油车导入；其他动力车型改这里。
    'powertrainType': PowertrainType.fuel.wire,
    'currentMileageKm': car['currentMileageKm'],
    'roadDate': car['roadDate'],
    'tankCapacityLiters': car['tankCapacityLiters'],
    'sync': _convertSync(car['sync']),
  };
}

Map<String, Object?> _convertItem(Map<String, Object?> item) {
  return {
    'id': item['id'],
    'carsId': item['carsId'],
    'name': item['name'],
    'enabled': item['enabled'],
    'remindByMileage': item['remindByMileage'],
    'remindByTime': item['remindByTime'],
    'mileageIntervalKm': item['mileageIntervalKm'],
    'timeIntervalMonths': item['timeIntervalMonths'],
    'notOverdueUpperLimit': _defaultLimitsItem.notOverdueUpperLimit,
    'overdueUpperLimit': _defaultLimitsItem.overdueUpperLimit,
    'sortOrder': item['sortOrder'],
    'sync': _convertSync(item['sync']),
  };
}

Map<String, Object?> _convertRecord(Map<String, Object?> record) {
  return {
    'id': record['id'],
    'carId': record['carId'],
    'date': record['date'],
    'itemIds': record['itemIds'],
    'costCents': record['costCents'],
    'mileageKm': record['mileageKm'],
    'note': record['note'],
    'sync': _convertSync(record['sync']),
  };
}

/// sync 对象归一：status 统一 synced（当前 App 的写入约定），
/// updatedAt / version 保留旧值。updatedAt 缺失会在 decode 阶段报错退出。
Map<String, Object?> _convertSync(Object? sync) {
  final old =
      (sync as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
  return {
    'status': SyncStatus.synced.name,
    'updatedAt': old['updatedAt'],
    'version': old['version'] ?? 1,
  };
}

/// 复刻 LunioRepository.restoreBackupPayload 恢复前的关键校验
/// （_validateBackupReferences 的子集 + 两处数据库唯一约束），违例直接退出。
void _validateForRestore(BackupPayload payload) {
  final carIds = <int>{};
  for (final car in payload.cars) {
    final id = car.id;
    if (id == null) _fail('cars 中存在没有 id 的条目');
    if (!carIds.add(id)) _fail('cars 中车辆 id 重复: $id');
  }

  final itemIdsByCar = <int, Set<int>>{};
  final itemKeys = <String>{};
  for (final item in payload.maintenanceItems) {
    final id = item.id;
    if (id == null) _fail('保养项目「${item.name}」没有 id');
    if (!carIds.contains(item.carsId)) {
      _fail('保养项目「${item.name}」的 carsId=${item.carsId} 没有对应车辆');
    }
    itemIdsByCar.putIfAbsent(item.carsId, () => <int>{}).add(id);
    // 数据库唯一约束 carsId + name：同车同名项目只能有一条。
    if (!itemKeys.add('${item.carsId}#${item.name}')) {
      _fail('同一辆车存在同名保养项目「${item.name}」');
    }
  }

  final recordKeys = <String>{};
  for (final record in payload.records) {
    if (!carIds.contains(record.carId)) {
      _fail('记录 ${record.id} 的 carId=${record.carId} 没有对应车辆');
    }
    if (record.costCents < 0) _fail('记录 ${record.id} 金额为负');
    if (record.mileageKm < 0) _fail('记录 ${record.id} 里程为负');
    final ids = record.itemIds.toSet();
    if (ids.isEmpty) _fail('记录 ${record.id}（${record.date}）没有关联保养项目');
    final sameCarItemIds = itemIdsByCar[record.carId] ?? const <int>{};
    for (final itemId in ids) {
      if (!sameCarItemIds.contains(itemId)) {
        _fail('记录 ${record.id} 引用了不属于本车的保养项目 $itemId');
      }
    }
    // 数据库唯一约束 carId + date：同车同日只能有一条记录。
    if (!recordKeys.add('${record.carId}#${record.date}')) {
      _fail('同一辆车同一天存在多条记录: ${record.date}');
    }
  }
}

/// 校验失败统一出口：打印原因并以 65（数据错误）退出，不写输出文件。
Never _fail(String message) {
  stderr.writeln('转换中止: $message');
  exit(65);
}

/// 按 App 导出命名规则（lunio-backup-yyyyMMdd-HHmmss.json）在输入目录生成输出路径。
String _defaultOutputPath(String inputPath) {
  final now = DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  final fileName =
      'lunio-backup-${now.year.toString().padLeft(4, '0')}'
      '${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}.json';
  return '${File(inputPath).parent.path}/$fileName';
}
