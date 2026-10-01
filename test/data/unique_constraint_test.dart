// 唯一约束冲突类型化包装测试（ADR 0009 2026-10-01 修订节）：
// guardUniqueConstraint 的直接单测（2067 包装、其他结果码/非驱动异常
// 透传）+ 仓库写路径边界真撞表级唯一约束的端到端断言（新增项目同名/
// 建车重复/恢复备份 payload 内部重复——三条都是没有业务前置查重、
// 只能靠驱动层 2067 拦的路径）+ 后台 isolate 连接（生产执行器形态，
// 异常经远程协议包成 DriftRemoteException）的同款回归。同日记录的
// 业务前置检查（duplicateMaintenanceRecord，不经过 guard）见
// database_test.dart。
import 'dart:io';

import 'package:drift/isolate.dart' show DriftRemoteException;
import 'package:drift/native.dart' show NativeDatabase, SqliteException;
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/data/backup/backup_codec.dart';
import 'package:lunio/data/database/app_database.dart';
import 'package:lunio/data/preferences/app_preferences.dart';
import 'package:lunio/data/repositories/backup_repository.dart';
import 'package:lunio/data/repositories/lunio_repository.dart';
import 'package:lunio/data/repositories/unique_constraint.dart';
import 'package:lunio/domain/entities/car.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';
import 'package:lunio/domain/errors/lunio_error.dart';

import '../helpers/builders.dart';
import '../helpers/widget_app.dart';

void main() {
  // ---------------- guard 函数直接单测 ----------------

  group('guardUniqueConstraint', () {
    test('wraps SQLITE_CONSTRAINT_UNIQUE (2067) into typed error', () async {
      await expectLater(
        guardUniqueConstraint<int>(() async {
          throw SqliteException(
            extendedResultCode: 2067,
            message: 'UNIQUE constraint failed: cars.brand, cars.model',
          );
        }),
        throwsA(
          isA<LunioErrorException>()
              .having((e) => e.kind, 'kind', LunioErrorKind.uniqueConstraint)
              .having(
                (e) => e.message,
                'message',
                '这条数据已经保存过了',
              ),
        ),
      );
    });

    test('passes other sqlite result codes through unwrapped', () async {
      // 泛码家族里的非 UNIQUE 约束（NOT NULL=1299）不包装——它们是
      // 程序 bug，落兜底文案比误译"已保存过"更诚实。
      final notNull = SqliteException(
        extendedResultCode: 1299,
        message: 'NOT NULL constraint failed: cars.brand',
      );
      await expectLater(
        guardUniqueConstraint<int>(() async => throw notNull),
        throwsA(same(notNull)),
      );
    });

    test('passes non-sqlite exceptions through unwrapped', () async {
      await expectLater(
        guardUniqueConstraint<void>(() async => throw ArgumentError('x')),
        throwsArgumentError,
      );
    });

    test('returns action value on success', () async {
      final result = await guardUniqueConstraint(() async => 42);
      expect(result, 42);
    });
  });

  // ---------------- 仓库写路径边界（内存库端到端） ----------------

  group('repository write boundaries', () {
    late AppDatabase database;
    late TestRepositories repos;
    late LunioRepository repository;
    late LunioPreferences preferences;
    late BackupRepository backupRepository;
    late SyncMetadata sync;

    setUp(() {
      database = AppDatabase.inMemory();
      repos = testRepository(database);
      repository = repos.repository;
      preferences = repos.preferences;
      backupRepository = repos.backupRepository;
      sync = repos.sync;
    });

    tearDown(() async {
      await database.close();
    });

    test('saveMaintenanceItem duplicate name becomes typed error', () async {
      final (carId, _) = await repos.seedCarAndItem();

      await expectLater(
        repository.saveMaintenanceItem(
          defaultOilItem(carsId: carId, name: '机油', sortOrder: 2),
        ),
        throwsA(
          isA<LunioErrorException>().having(
            (e) => e.kind,
            'kind',
            LunioErrorKind.uniqueConstraint,
          ),
        ),
      );
    });

    test('createCarWithMaintenanceItems duplicate car becomes typed error',
        () async {
      // 先裸插一辆默认车（品牌/型号/上路日期三联即身份），再用同一组
      // 身份走建车事务——撞 cars {brand,model,roadDate} 唯一约束。
      await repos.insertCarForTest(defaultCar());

      await expectLater(
        repository.createCarWithMaintenanceItems(
          defaultCar(),
          [defaultOilItem()],
        ),
        throwsA(
          isA<LunioErrorException>().having(
            (e) => e.kind,
            'kind',
            LunioErrorKind.uniqueConstraint,
          ),
        ),
      );
      // 事务整体回滚：不因先插车成功而留下半截数据（裸插那辆仍在）。
      expect(await repository.listCars(), hasLength(1));
    });

    test('updateMaintenanceItem rename to duplicate becomes typed error',
        () async {
      final (carId, firstItemId) = await repos.seedCarAndItem();
      final secondItemId = await repository.saveMaintenanceItem(
        defaultOilItem(carsId: carId, name: '机滤', sortOrder: 2),
      );
      final secondItem = (await repository.listMaintenanceItemsForCar(carId))
          .firstWhere((item) => item.id == secondItemId);

      await expectLater(
        repository.updateMaintenanceItem(
          secondItem.copyWith(name: '机油'),
        ),
        throwsA(
          isA<LunioErrorException>().having(
            (e) => e.kind,
            'kind',
            LunioErrorKind.uniqueConstraint,
          ),
        ),
      );
      expect(firstItemId, isNotNull);
    });

    test('restore payload-internal duplicate cars becomes typed error',
        () async {
      // 预校验只覆盖保养记录同车同日；payload 里两辆身份相同的车只能
      // 靠表级唯一约束拦（恢复 UI 按 kind 弹"未写入任何数据"对话框的
      // 那条路径）。
      final (carId, _) = await repos.seedCarAndItem();
      await preferences.setAppliedCarId(carId);
      final invalid = BackupPayload(
        schemaVersion: 1,
        cars: [
          Car(
            id: 99,
            brand: '本田',
            model: '22款思域',
            currentMileageKm: 12000,
            roadDate: const LocalDate(2023, 8, 12),
            sync: sync,
          ),
          Car(
            id: 100,
            brand: '本田',
            model: '22款思域',
            currentMileageKm: 13000,
            roadDate: const LocalDate(2023, 8, 12),
            sync: sync,
          ),
        ],
      );

      await expectLater(
        backupRepository.restoreBackupPayload(invalid),
        throwsA(
          isA<LunioErrorException>().having(
            (e) => e.kind,
            'kind',
            LunioErrorKind.uniqueConstraint,
          ),
        ),
      );
      // 事务已回滚：库里还是原来那辆车、偏好未动。
      expect(await database.select(database.cars).get(), hasLength(1));
      expect(await preferences.getAppliedCarId(), carId);
    });
  });

  // ---------------- 后台 isolate 连接（生产执行器形态） ----------------

  group('background isolate connection', () {
    // 生产连接 NativeDatabase.createInBackground（app_database.dart
    // _openConnection）把 SQLite 跑在后台 isolate：语句异常经 drift
    // 远程协议回传时，客户端对每个 ErrorResponse 无条件包成
    // DriftRemoteException（原始 SqliteException 挂在 remoteCause 上，
    // 与是否序列化无关，drift 2.33.0 communication.dart _handleMessage）。
    // 上面的内存库组是进程内直通、异常原样上抛，测不出这条缝——本组用
    // 同款后台 isolate + 临时文件库复刻生产形态，锁 guard 对包装形态的
    // 翻译（2026-10-01 评审：只认直接 SqliteException 在生产是净回归，
    // 被删的文本匹配经 toString() 代理反而命不丢）。
    late Directory tempDir;
    late AppDatabase database;
    late TestRepositories repos;
    late LunioRepository repository;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('lunio_unique_guard');
      database = AppDatabase.forExecutor(
        NativeDatabase.createInBackground(
          File('${tempDir.path}/lunio.sqlite'),
        ),
      );
      repos = testRepository(database);
      repository = repos.repository;
    });

    tearDown(() async {
      await database.close();
      tempDir.deleteSync(recursive: true);
    });

    test('createCar duplicate becomes typed error through remote wrap',
        () async {
      await repos.insertCarForTest(defaultCar());

      await expectLater(
        repository.createCarWithMaintenanceItems(defaultCar(), [
          defaultOilItem(),
        ]),
        throwsA(
          isA<LunioErrorException>().having(
            (e) => e.kind,
            'kind',
            LunioErrorKind.uniqueConstraint,
          ),
        ),
      );
      // 事务整体回滚：不因先插车成功而留下半截数据（裸插那辆仍在）。
      expect(await repository.listCars(), hasLength(1));
    });

    test('remote-wrapped non-unique sqlite error passes through unwrapped',
        () async {
      // 断言两件事：这条连接上异常确实以 DriftRemoteException 形态
      // 到达（否则 isA 先败，说明缝挪了）；且 remoteCause 非唯一约束
      // 冲突时不误译——"no such table"（结果码 1）原样透传。
      await expectLater(
        guardUniqueConstraint<void>(
          () => database.customStatement('INSERT INTO no_such_table VALUES (1)'),
        ),
        throwsA(
          isA<DriftRemoteException>()
              .having(
                (e) => e.remoteCause,
                'remoteCause',
                isA<SqliteException>(),
              )
              .having(
                (e) => (e.remoteCause as SqliteException).resultCode,
                'resultCode',
                1,
              ),
        ),
      );
    });
  });
}
