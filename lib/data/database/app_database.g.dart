// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $CarsTable extends Cars with TableInfo<$CarsTable, CarRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CarsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _brandMeta = const VerificationMeta('brand');
  @override
  late final GeneratedColumn<String> brand = GeneratedColumn<String>(
    'brand',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
    'model',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _brandModelKeyMeta = const VerificationMeta(
    'brandModelKey',
  );
  @override
  late final GeneratedColumn<String> brandModelKey = GeneratedColumn<String>(
    'brand_model_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _currentMileageKmMeta = const VerificationMeta(
    'currentMileageKm',
  );
  @override
  late final GeneratedColumn<int> currentMileageKm = GeneratedColumn<int>(
    'current_mileage_km',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roadDateMeta = const VerificationMeta(
    'roadDate',
  );
  @override
  late final GeneratedColumn<String> roadDate = GeneratedColumn<String>(
    'road_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<String> syncStatus = GeneratedColumn<String>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('synced'),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    brand,
    model,
    brandModelKey,
    currentMileageKm,
    roadDate,
    syncStatus,
    updatedAt,
    deletedAt,
    version,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cars';
  @override
  VerificationContext validateIntegrity(
    Insertable<CarRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('brand')) {
      context.handle(
        _brandMeta,
        brand.isAcceptableOrUnknown(data['brand']!, _brandMeta),
      );
    } else if (isInserting) {
      context.missing(_brandMeta);
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    } else if (isInserting) {
      context.missing(_modelMeta);
    }
    if (data.containsKey('brand_model_key')) {
      context.handle(
        _brandModelKeyMeta,
        brandModelKey.isAcceptableOrUnknown(
          data['brand_model_key']!,
          _brandModelKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_brandModelKeyMeta);
    }
    if (data.containsKey('current_mileage_km')) {
      context.handle(
        _currentMileageKmMeta,
        currentMileageKm.isAcceptableOrUnknown(
          data['current_mileage_km']!,
          _currentMileageKmMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currentMileageKmMeta);
    }
    if (data.containsKey('road_date')) {
      context.handle(
        _roadDateMeta,
        roadDate.isAcceptableOrUnknown(data['road_date']!, _roadDateMeta),
      );
    } else if (isInserting) {
      context.missing(_roadDateMeta);
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CarRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CarRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      brand: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}brand'],
      )!,
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      )!,
      brandModelKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}brand_model_key'],
      )!,
      currentMileageKm: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}current_mileage_km'],
      )!,
      roadDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}road_date'],
      )!,
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_status'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
    );
  }

  @override
  $CarsTable createAlias(String alias) {
    return $CarsTable(attachedDatabase, alias);
  }
}

class CarRow extends DataClass implements Insertable<CarRow> {
  final String id;
  final String brand;
  final String model;
  final String brandModelKey;
  final int currentMileageKm;
  final String roadDate;
  final String syncStatus;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int version;
  const CarRow({
    required this.id,
    required this.brand,
    required this.model,
    required this.brandModelKey,
    required this.currentMileageKm,
    required this.roadDate,
    required this.syncStatus,
    required this.updatedAt,
    this.deletedAt,
    required this.version,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['brand'] = Variable<String>(brand);
    map['model'] = Variable<String>(model);
    map['brand_model_key'] = Variable<String>(brandModelKey);
    map['current_mileage_km'] = Variable<int>(currentMileageKm);
    map['road_date'] = Variable<String>(roadDate);
    map['sync_status'] = Variable<String>(syncStatus);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['version'] = Variable<int>(version);
    return map;
  }

  CarsCompanion toCompanion(bool nullToAbsent) {
    return CarsCompanion(
      id: Value(id),
      brand: Value(brand),
      model: Value(model),
      brandModelKey: Value(brandModelKey),
      currentMileageKm: Value(currentMileageKm),
      roadDate: Value(roadDate),
      syncStatus: Value(syncStatus),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      version: Value(version),
    );
  }

  factory CarRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CarRow(
      id: serializer.fromJson<String>(json['id']),
      brand: serializer.fromJson<String>(json['brand']),
      model: serializer.fromJson<String>(json['model']),
      brandModelKey: serializer.fromJson<String>(json['brandModelKey']),
      currentMileageKm: serializer.fromJson<int>(json['currentMileageKm']),
      roadDate: serializer.fromJson<String>(json['roadDate']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      version: serializer.fromJson<int>(json['version']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'brand': serializer.toJson<String>(brand),
      'model': serializer.toJson<String>(model),
      'brandModelKey': serializer.toJson<String>(brandModelKey),
      'currentMileageKm': serializer.toJson<int>(currentMileageKm),
      'roadDate': serializer.toJson<String>(roadDate),
      'syncStatus': serializer.toJson<String>(syncStatus),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'version': serializer.toJson<int>(version),
    };
  }

  CarRow copyWith({
    String? id,
    String? brand,
    String? model,
    String? brandModelKey,
    int? currentMileageKm,
    String? roadDate,
    String? syncStatus,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    int? version,
  }) => CarRow(
    id: id ?? this.id,
    brand: brand ?? this.brand,
    model: model ?? this.model,
    brandModelKey: brandModelKey ?? this.brandModelKey,
    currentMileageKm: currentMileageKm ?? this.currentMileageKm,
    roadDate: roadDate ?? this.roadDate,
    syncStatus: syncStatus ?? this.syncStatus,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    version: version ?? this.version,
  );
  CarRow copyWithCompanion(CarsCompanion data) {
    return CarRow(
      id: data.id.present ? data.id.value : this.id,
      brand: data.brand.present ? data.brand.value : this.brand,
      model: data.model.present ? data.model.value : this.model,
      brandModelKey: data.brandModelKey.present
          ? data.brandModelKey.value
          : this.brandModelKey,
      currentMileageKm: data.currentMileageKm.present
          ? data.currentMileageKm.value
          : this.currentMileageKm,
      roadDate: data.roadDate.present ? data.roadDate.value : this.roadDate,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      version: data.version.present ? data.version.value : this.version,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CarRow(')
          ..write('id: $id, ')
          ..write('brand: $brand, ')
          ..write('model: $model, ')
          ..write('brandModelKey: $brandModelKey, ')
          ..write('currentMileageKm: $currentMileageKm, ')
          ..write('roadDate: $roadDate, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    brand,
    model,
    brandModelKey,
    currentMileageKm,
    roadDate,
    syncStatus,
    updatedAt,
    deletedAt,
    version,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CarRow &&
          other.id == this.id &&
          other.brand == this.brand &&
          other.model == this.model &&
          other.brandModelKey == this.brandModelKey &&
          other.currentMileageKm == this.currentMileageKm &&
          other.roadDate == this.roadDate &&
          other.syncStatus == this.syncStatus &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.version == this.version);
}

class CarsCompanion extends UpdateCompanion<CarRow> {
  final Value<String> id;
  final Value<String> brand;
  final Value<String> model;
  final Value<String> brandModelKey;
  final Value<int> currentMileageKm;
  final Value<String> roadDate;
  final Value<String> syncStatus;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> version;
  final Value<int> rowid;
  const CarsCompanion({
    this.id = const Value.absent(),
    this.brand = const Value.absent(),
    this.model = const Value.absent(),
    this.brandModelKey = const Value.absent(),
    this.currentMileageKm = const Value.absent(),
    this.roadDate = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CarsCompanion.insert({
    required String id,
    required String brand,
    required String model,
    required String brandModelKey,
    required int currentMileageKm,
    required String roadDate,
    this.syncStatus = const Value.absent(),
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       brand = Value(brand),
       model = Value(model),
       brandModelKey = Value(brandModelKey),
       currentMileageKm = Value(currentMileageKm),
       roadDate = Value(roadDate),
       updatedAt = Value(updatedAt);
  static Insertable<CarRow> custom({
    Expression<String>? id,
    Expression<String>? brand,
    Expression<String>? model,
    Expression<String>? brandModelKey,
    Expression<int>? currentMileageKm,
    Expression<String>? roadDate,
    Expression<String>? syncStatus,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? version,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (brand != null) 'brand': brand,
      if (model != null) 'model': model,
      if (brandModelKey != null) 'brand_model_key': brandModelKey,
      if (currentMileageKm != null) 'current_mileage_km': currentMileageKm,
      if (roadDate != null) 'road_date': roadDate,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (version != null) 'version': version,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CarsCompanion copyWith({
    Value<String>? id,
    Value<String>? brand,
    Value<String>? model,
    Value<String>? brandModelKey,
    Value<int>? currentMileageKm,
    Value<String>? roadDate,
    Value<String>? syncStatus,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? version,
    Value<int>? rowid,
  }) {
    return CarsCompanion(
      id: id ?? this.id,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      brandModelKey: brandModelKey ?? this.brandModelKey,
      currentMileageKm: currentMileageKm ?? this.currentMileageKm,
      roadDate: roadDate ?? this.roadDate,
      syncStatus: syncStatus ?? this.syncStatus,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      version: version ?? this.version,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (brand.present) {
      map['brand'] = Variable<String>(brand.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (brandModelKey.present) {
      map['brand_model_key'] = Variable<String>(brandModelKey.value);
    }
    if (currentMileageKm.present) {
      map['current_mileage_km'] = Variable<int>(currentMileageKm.value);
    }
    if (roadDate.present) {
      map['road_date'] = Variable<String>(roadDate.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CarsCompanion(')
          ..write('id: $id, ')
          ..write('brand: $brand, ')
          ..write('model: $model, ')
          ..write('brandModelKey: $brandModelKey, ')
          ..write('currentMileageKm: $currentMileageKm, ')
          ..write('roadDate: $roadDate, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MaintenanceItemsTable extends MaintenanceItems
    with TableInfo<$MaintenanceItemsTable, MaintenanceItemRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MaintenanceItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerCarIdMeta = const VerificationMeta(
    'ownerCarId',
  );
  @override
  late final GeneratedColumn<String> ownerCarId = GeneratedColumn<String>(
    'owner_car_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isDefaultMeta = const VerificationMeta(
    'isDefault',
  );
  @override
  late final GeneratedColumn<bool> isDefault = GeneratedColumn<bool>(
    'is_default',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_default" IN (0, 1))',
    ),
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _catalogKeyMeta = const VerificationMeta(
    'catalogKey',
  );
  @override
  late final GeneratedColumn<String> catalogKey = GeneratedColumn<String>(
    'catalog_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _remindByMileageMeta = const VerificationMeta(
    'remindByMileage',
  );
  @override
  late final GeneratedColumn<bool> remindByMileage = GeneratedColumn<bool>(
    'remind_by_mileage',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("remind_by_mileage" IN (0, 1))',
    ),
  );
  static const VerificationMeta _remindByTimeMeta = const VerificationMeta(
    'remindByTime',
  );
  @override
  late final GeneratedColumn<bool> remindByTime = GeneratedColumn<bool>(
    'remind_by_time',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("remind_by_time" IN (0, 1))',
    ),
  );
  static const VerificationMeta _mileageIntervalKmMeta = const VerificationMeta(
    'mileageIntervalKm',
  );
  @override
  late final GeneratedColumn<int> mileageIntervalKm = GeneratedColumn<int>(
    'mileage_interval_km',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _timeIntervalMonthsMeta =
      const VerificationMeta('timeIntervalMonths');
  @override
  late final GeneratedColumn<int> timeIntervalMonths = GeneratedColumn<int>(
    'time_interval_months',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _warningThresholdPercentMeta =
      const VerificationMeta('warningThresholdPercent');
  @override
  late final GeneratedColumn<int> warningThresholdPercent =
      GeneratedColumn<int>(
        'warning_threshold_percent',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
        defaultValue: const Constant(100),
      );
  static const VerificationMeta _dangerThresholdPercentMeta =
      const VerificationMeta('dangerThresholdPercent');
  @override
  late final GeneratedColumn<int> dangerThresholdPercent = GeneratedColumn<int>(
    'danger_threshold_percent',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(125),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<String> syncStatus = GeneratedColumn<String>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('synced'),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    ownerCarId,
    name,
    isDefault,
    enabled,
    catalogKey,
    remindByMileage,
    remindByTime,
    mileageIntervalKm,
    timeIntervalMonths,
    warningThresholdPercent,
    dangerThresholdPercent,
    sortOrder,
    syncStatus,
    updatedAt,
    deletedAt,
    version,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'maintenance_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<MaintenanceItemRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('owner_car_id')) {
      context.handle(
        _ownerCarIdMeta,
        ownerCarId.isAcceptableOrUnknown(
          data['owner_car_id']!,
          _ownerCarIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerCarIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('is_default')) {
      context.handle(
        _isDefaultMeta,
        isDefault.isAcceptableOrUnknown(data['is_default']!, _isDefaultMeta),
      );
    } else if (isInserting) {
      context.missing(_isDefaultMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('catalog_key')) {
      context.handle(
        _catalogKeyMeta,
        catalogKey.isAcceptableOrUnknown(data['catalog_key']!, _catalogKeyMeta),
      );
    }
    if (data.containsKey('remind_by_mileage')) {
      context.handle(
        _remindByMileageMeta,
        remindByMileage.isAcceptableOrUnknown(
          data['remind_by_mileage']!,
          _remindByMileageMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_remindByMileageMeta);
    }
    if (data.containsKey('remind_by_time')) {
      context.handle(
        _remindByTimeMeta,
        remindByTime.isAcceptableOrUnknown(
          data['remind_by_time']!,
          _remindByTimeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_remindByTimeMeta);
    }
    if (data.containsKey('mileage_interval_km')) {
      context.handle(
        _mileageIntervalKmMeta,
        mileageIntervalKm.isAcceptableOrUnknown(
          data['mileage_interval_km']!,
          _mileageIntervalKmMeta,
        ),
      );
    }
    if (data.containsKey('time_interval_months')) {
      context.handle(
        _timeIntervalMonthsMeta,
        timeIntervalMonths.isAcceptableOrUnknown(
          data['time_interval_months']!,
          _timeIntervalMonthsMeta,
        ),
      );
    }
    if (data.containsKey('warning_threshold_percent')) {
      context.handle(
        _warningThresholdPercentMeta,
        warningThresholdPercent.isAcceptableOrUnknown(
          data['warning_threshold_percent']!,
          _warningThresholdPercentMeta,
        ),
      );
    }
    if (data.containsKey('danger_threshold_percent')) {
      context.handle(
        _dangerThresholdPercentMeta,
        dangerThresholdPercent.isAcceptableOrUnknown(
          data['danger_threshold_percent']!,
          _dangerThresholdPercentMeta,
        ),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    } else if (isInserting) {
      context.missing(_sortOrderMeta);
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MaintenanceItemRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MaintenanceItemRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      ownerCarId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_car_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      isDefault: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_default'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      catalogKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}catalog_key'],
      ),
      remindByMileage: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}remind_by_mileage'],
      )!,
      remindByTime: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}remind_by_time'],
      )!,
      mileageIntervalKm: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}mileage_interval_km'],
      ),
      timeIntervalMonths: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}time_interval_months'],
      ),
      warningThresholdPercent: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}warning_threshold_percent'],
      )!,
      dangerThresholdPercent: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}danger_threshold_percent'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_status'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
    );
  }

  @override
  $MaintenanceItemsTable createAlias(String alias) {
    return $MaintenanceItemsTable(attachedDatabase, alias);
  }
}

class MaintenanceItemRow extends DataClass
    implements Insertable<MaintenanceItemRow> {
  final String id;
  final String ownerCarId;
  final String name;
  final bool isDefault;
  final bool enabled;
  final String? catalogKey;
  final bool remindByMileage;
  final bool remindByTime;
  final int? mileageIntervalKm;
  final int? timeIntervalMonths;
  final int warningThresholdPercent;
  final int dangerThresholdPercent;
  final int sortOrder;
  final String syncStatus;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int version;
  const MaintenanceItemRow({
    required this.id,
    required this.ownerCarId,
    required this.name,
    required this.isDefault,
    required this.enabled,
    this.catalogKey,
    required this.remindByMileage,
    required this.remindByTime,
    this.mileageIntervalKm,
    this.timeIntervalMonths,
    required this.warningThresholdPercent,
    required this.dangerThresholdPercent,
    required this.sortOrder,
    required this.syncStatus,
    required this.updatedAt,
    this.deletedAt,
    required this.version,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['owner_car_id'] = Variable<String>(ownerCarId);
    map['name'] = Variable<String>(name);
    map['is_default'] = Variable<bool>(isDefault);
    map['enabled'] = Variable<bool>(enabled);
    if (!nullToAbsent || catalogKey != null) {
      map['catalog_key'] = Variable<String>(catalogKey);
    }
    map['remind_by_mileage'] = Variable<bool>(remindByMileage);
    map['remind_by_time'] = Variable<bool>(remindByTime);
    if (!nullToAbsent || mileageIntervalKm != null) {
      map['mileage_interval_km'] = Variable<int>(mileageIntervalKm);
    }
    if (!nullToAbsent || timeIntervalMonths != null) {
      map['time_interval_months'] = Variable<int>(timeIntervalMonths);
    }
    map['warning_threshold_percent'] = Variable<int>(warningThresholdPercent);
    map['danger_threshold_percent'] = Variable<int>(dangerThresholdPercent);
    map['sort_order'] = Variable<int>(sortOrder);
    map['sync_status'] = Variable<String>(syncStatus);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['version'] = Variable<int>(version);
    return map;
  }

  MaintenanceItemsCompanion toCompanion(bool nullToAbsent) {
    return MaintenanceItemsCompanion(
      id: Value(id),
      ownerCarId: Value(ownerCarId),
      name: Value(name),
      isDefault: Value(isDefault),
      enabled: Value(enabled),
      catalogKey: catalogKey == null && nullToAbsent
          ? const Value.absent()
          : Value(catalogKey),
      remindByMileage: Value(remindByMileage),
      remindByTime: Value(remindByTime),
      mileageIntervalKm: mileageIntervalKm == null && nullToAbsent
          ? const Value.absent()
          : Value(mileageIntervalKm),
      timeIntervalMonths: timeIntervalMonths == null && nullToAbsent
          ? const Value.absent()
          : Value(timeIntervalMonths),
      warningThresholdPercent: Value(warningThresholdPercent),
      dangerThresholdPercent: Value(dangerThresholdPercent),
      sortOrder: Value(sortOrder),
      syncStatus: Value(syncStatus),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      version: Value(version),
    );
  }

  factory MaintenanceItemRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MaintenanceItemRow(
      id: serializer.fromJson<String>(json['id']),
      ownerCarId: serializer.fromJson<String>(json['ownerCarId']),
      name: serializer.fromJson<String>(json['name']),
      isDefault: serializer.fromJson<bool>(json['isDefault']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      catalogKey: serializer.fromJson<String?>(json['catalogKey']),
      remindByMileage: serializer.fromJson<bool>(json['remindByMileage']),
      remindByTime: serializer.fromJson<bool>(json['remindByTime']),
      mileageIntervalKm: serializer.fromJson<int?>(json['mileageIntervalKm']),
      timeIntervalMonths: serializer.fromJson<int?>(json['timeIntervalMonths']),
      warningThresholdPercent: serializer.fromJson<int>(
        json['warningThresholdPercent'],
      ),
      dangerThresholdPercent: serializer.fromJson<int>(
        json['dangerThresholdPercent'],
      ),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      version: serializer.fromJson<int>(json['version']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ownerCarId': serializer.toJson<String>(ownerCarId),
      'name': serializer.toJson<String>(name),
      'isDefault': serializer.toJson<bool>(isDefault),
      'enabled': serializer.toJson<bool>(enabled),
      'catalogKey': serializer.toJson<String?>(catalogKey),
      'remindByMileage': serializer.toJson<bool>(remindByMileage),
      'remindByTime': serializer.toJson<bool>(remindByTime),
      'mileageIntervalKm': serializer.toJson<int?>(mileageIntervalKm),
      'timeIntervalMonths': serializer.toJson<int?>(timeIntervalMonths),
      'warningThresholdPercent': serializer.toJson<int>(
        warningThresholdPercent,
      ),
      'dangerThresholdPercent': serializer.toJson<int>(dangerThresholdPercent),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'syncStatus': serializer.toJson<String>(syncStatus),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'version': serializer.toJson<int>(version),
    };
  }

  MaintenanceItemRow copyWith({
    String? id,
    String? ownerCarId,
    String? name,
    bool? isDefault,
    bool? enabled,
    Value<String?> catalogKey = const Value.absent(),
    bool? remindByMileage,
    bool? remindByTime,
    Value<int?> mileageIntervalKm = const Value.absent(),
    Value<int?> timeIntervalMonths = const Value.absent(),
    int? warningThresholdPercent,
    int? dangerThresholdPercent,
    int? sortOrder,
    String? syncStatus,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    int? version,
  }) => MaintenanceItemRow(
    id: id ?? this.id,
    ownerCarId: ownerCarId ?? this.ownerCarId,
    name: name ?? this.name,
    isDefault: isDefault ?? this.isDefault,
    enabled: enabled ?? this.enabled,
    catalogKey: catalogKey.present ? catalogKey.value : this.catalogKey,
    remindByMileage: remindByMileage ?? this.remindByMileage,
    remindByTime: remindByTime ?? this.remindByTime,
    mileageIntervalKm: mileageIntervalKm.present
        ? mileageIntervalKm.value
        : this.mileageIntervalKm,
    timeIntervalMonths: timeIntervalMonths.present
        ? timeIntervalMonths.value
        : this.timeIntervalMonths,
    warningThresholdPercent:
        warningThresholdPercent ?? this.warningThresholdPercent,
    dangerThresholdPercent:
        dangerThresholdPercent ?? this.dangerThresholdPercent,
    sortOrder: sortOrder ?? this.sortOrder,
    syncStatus: syncStatus ?? this.syncStatus,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    version: version ?? this.version,
  );
  MaintenanceItemRow copyWithCompanion(MaintenanceItemsCompanion data) {
    return MaintenanceItemRow(
      id: data.id.present ? data.id.value : this.id,
      ownerCarId: data.ownerCarId.present
          ? data.ownerCarId.value
          : this.ownerCarId,
      name: data.name.present ? data.name.value : this.name,
      isDefault: data.isDefault.present ? data.isDefault.value : this.isDefault,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      catalogKey: data.catalogKey.present
          ? data.catalogKey.value
          : this.catalogKey,
      remindByMileage: data.remindByMileage.present
          ? data.remindByMileage.value
          : this.remindByMileage,
      remindByTime: data.remindByTime.present
          ? data.remindByTime.value
          : this.remindByTime,
      mileageIntervalKm: data.mileageIntervalKm.present
          ? data.mileageIntervalKm.value
          : this.mileageIntervalKm,
      timeIntervalMonths: data.timeIntervalMonths.present
          ? data.timeIntervalMonths.value
          : this.timeIntervalMonths,
      warningThresholdPercent: data.warningThresholdPercent.present
          ? data.warningThresholdPercent.value
          : this.warningThresholdPercent,
      dangerThresholdPercent: data.dangerThresholdPercent.present
          ? data.dangerThresholdPercent.value
          : this.dangerThresholdPercent,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      version: data.version.present ? data.version.value : this.version,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MaintenanceItemRow(')
          ..write('id: $id, ')
          ..write('ownerCarId: $ownerCarId, ')
          ..write('name: $name, ')
          ..write('isDefault: $isDefault, ')
          ..write('enabled: $enabled, ')
          ..write('catalogKey: $catalogKey, ')
          ..write('remindByMileage: $remindByMileage, ')
          ..write('remindByTime: $remindByTime, ')
          ..write('mileageIntervalKm: $mileageIntervalKm, ')
          ..write('timeIntervalMonths: $timeIntervalMonths, ')
          ..write('warningThresholdPercent: $warningThresholdPercent, ')
          ..write('dangerThresholdPercent: $dangerThresholdPercent, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    ownerCarId,
    name,
    isDefault,
    enabled,
    catalogKey,
    remindByMileage,
    remindByTime,
    mileageIntervalKm,
    timeIntervalMonths,
    warningThresholdPercent,
    dangerThresholdPercent,
    sortOrder,
    syncStatus,
    updatedAt,
    deletedAt,
    version,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MaintenanceItemRow &&
          other.id == this.id &&
          other.ownerCarId == this.ownerCarId &&
          other.name == this.name &&
          other.isDefault == this.isDefault &&
          other.enabled == this.enabled &&
          other.catalogKey == this.catalogKey &&
          other.remindByMileage == this.remindByMileage &&
          other.remindByTime == this.remindByTime &&
          other.mileageIntervalKm == this.mileageIntervalKm &&
          other.timeIntervalMonths == this.timeIntervalMonths &&
          other.warningThresholdPercent == this.warningThresholdPercent &&
          other.dangerThresholdPercent == this.dangerThresholdPercent &&
          other.sortOrder == this.sortOrder &&
          other.syncStatus == this.syncStatus &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.version == this.version);
}

class MaintenanceItemsCompanion extends UpdateCompanion<MaintenanceItemRow> {
  final Value<String> id;
  final Value<String> ownerCarId;
  final Value<String> name;
  final Value<bool> isDefault;
  final Value<bool> enabled;
  final Value<String?> catalogKey;
  final Value<bool> remindByMileage;
  final Value<bool> remindByTime;
  final Value<int?> mileageIntervalKm;
  final Value<int?> timeIntervalMonths;
  final Value<int> warningThresholdPercent;
  final Value<int> dangerThresholdPercent;
  final Value<int> sortOrder;
  final Value<String> syncStatus;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> version;
  final Value<int> rowid;
  const MaintenanceItemsCompanion({
    this.id = const Value.absent(),
    this.ownerCarId = const Value.absent(),
    this.name = const Value.absent(),
    this.isDefault = const Value.absent(),
    this.enabled = const Value.absent(),
    this.catalogKey = const Value.absent(),
    this.remindByMileage = const Value.absent(),
    this.remindByTime = const Value.absent(),
    this.mileageIntervalKm = const Value.absent(),
    this.timeIntervalMonths = const Value.absent(),
    this.warningThresholdPercent = const Value.absent(),
    this.dangerThresholdPercent = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MaintenanceItemsCompanion.insert({
    required String id,
    required String ownerCarId,
    required String name,
    required bool isDefault,
    this.enabled = const Value.absent(),
    this.catalogKey = const Value.absent(),
    required bool remindByMileage,
    required bool remindByTime,
    this.mileageIntervalKm = const Value.absent(),
    this.timeIntervalMonths = const Value.absent(),
    this.warningThresholdPercent = const Value.absent(),
    this.dangerThresholdPercent = const Value.absent(),
    required int sortOrder,
    this.syncStatus = const Value.absent(),
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       ownerCarId = Value(ownerCarId),
       name = Value(name),
       isDefault = Value(isDefault),
       remindByMileage = Value(remindByMileage),
       remindByTime = Value(remindByTime),
       sortOrder = Value(sortOrder),
       updatedAt = Value(updatedAt);
  static Insertable<MaintenanceItemRow> custom({
    Expression<String>? id,
    Expression<String>? ownerCarId,
    Expression<String>? name,
    Expression<bool>? isDefault,
    Expression<bool>? enabled,
    Expression<String>? catalogKey,
    Expression<bool>? remindByMileage,
    Expression<bool>? remindByTime,
    Expression<int>? mileageIntervalKm,
    Expression<int>? timeIntervalMonths,
    Expression<int>? warningThresholdPercent,
    Expression<int>? dangerThresholdPercent,
    Expression<int>? sortOrder,
    Expression<String>? syncStatus,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? version,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ownerCarId != null) 'owner_car_id': ownerCarId,
      if (name != null) 'name': name,
      if (isDefault != null) 'is_default': isDefault,
      if (enabled != null) 'enabled': enabled,
      if (catalogKey != null) 'catalog_key': catalogKey,
      if (remindByMileage != null) 'remind_by_mileage': remindByMileage,
      if (remindByTime != null) 'remind_by_time': remindByTime,
      if (mileageIntervalKm != null) 'mileage_interval_km': mileageIntervalKm,
      if (timeIntervalMonths != null)
        'time_interval_months': timeIntervalMonths,
      if (warningThresholdPercent != null)
        'warning_threshold_percent': warningThresholdPercent,
      if (dangerThresholdPercent != null)
        'danger_threshold_percent': dangerThresholdPercent,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (version != null) 'version': version,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MaintenanceItemsCompanion copyWith({
    Value<String>? id,
    Value<String>? ownerCarId,
    Value<String>? name,
    Value<bool>? isDefault,
    Value<bool>? enabled,
    Value<String?>? catalogKey,
    Value<bool>? remindByMileage,
    Value<bool>? remindByTime,
    Value<int?>? mileageIntervalKm,
    Value<int?>? timeIntervalMonths,
    Value<int>? warningThresholdPercent,
    Value<int>? dangerThresholdPercent,
    Value<int>? sortOrder,
    Value<String>? syncStatus,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? version,
    Value<int>? rowid,
  }) {
    return MaintenanceItemsCompanion(
      id: id ?? this.id,
      ownerCarId: ownerCarId ?? this.ownerCarId,
      name: name ?? this.name,
      isDefault: isDefault ?? this.isDefault,
      enabled: enabled ?? this.enabled,
      catalogKey: catalogKey ?? this.catalogKey,
      remindByMileage: remindByMileage ?? this.remindByMileage,
      remindByTime: remindByTime ?? this.remindByTime,
      mileageIntervalKm: mileageIntervalKm ?? this.mileageIntervalKm,
      timeIntervalMonths: timeIntervalMonths ?? this.timeIntervalMonths,
      warningThresholdPercent:
          warningThresholdPercent ?? this.warningThresholdPercent,
      dangerThresholdPercent:
          dangerThresholdPercent ?? this.dangerThresholdPercent,
      sortOrder: sortOrder ?? this.sortOrder,
      syncStatus: syncStatus ?? this.syncStatus,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      version: version ?? this.version,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ownerCarId.present) {
      map['owner_car_id'] = Variable<String>(ownerCarId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (isDefault.present) {
      map['is_default'] = Variable<bool>(isDefault.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (catalogKey.present) {
      map['catalog_key'] = Variable<String>(catalogKey.value);
    }
    if (remindByMileage.present) {
      map['remind_by_mileage'] = Variable<bool>(remindByMileage.value);
    }
    if (remindByTime.present) {
      map['remind_by_time'] = Variable<bool>(remindByTime.value);
    }
    if (mileageIntervalKm.present) {
      map['mileage_interval_km'] = Variable<int>(mileageIntervalKm.value);
    }
    if (timeIntervalMonths.present) {
      map['time_interval_months'] = Variable<int>(timeIntervalMonths.value);
    }
    if (warningThresholdPercent.present) {
      map['warning_threshold_percent'] = Variable<int>(
        warningThresholdPercent.value,
      );
    }
    if (dangerThresholdPercent.present) {
      map['danger_threshold_percent'] = Variable<int>(
        dangerThresholdPercent.value,
      );
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MaintenanceItemsCompanion(')
          ..write('id: $id, ')
          ..write('ownerCarId: $ownerCarId, ')
          ..write('name: $name, ')
          ..write('isDefault: $isDefault, ')
          ..write('enabled: $enabled, ')
          ..write('catalogKey: $catalogKey, ')
          ..write('remindByMileage: $remindByMileage, ')
          ..write('remindByTime: $remindByTime, ')
          ..write('mileageIntervalKm: $mileageIntervalKm, ')
          ..write('timeIntervalMonths: $timeIntervalMonths, ')
          ..write('warningThresholdPercent: $warningThresholdPercent, ')
          ..write('dangerThresholdPercent: $dangerThresholdPercent, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MaintenanceRecordsTable extends MaintenanceRecords
    with TableInfo<$MaintenanceRecordsTable, MaintenanceRecordRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MaintenanceRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _carIdMeta = const VerificationMeta('carId');
  @override
  late final GeneratedColumn<String> carId = GeneratedColumn<String>(
    'car_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cycleKeyMeta = const VerificationMeta(
    'cycleKey',
  );
  @override
  late final GeneratedColumn<String> cycleKey = GeneratedColumn<String>(
    'cycle_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _mileageKmMeta = const VerificationMeta(
    'mileageKm',
  );
  @override
  late final GeneratedColumn<int> mileageKm = GeneratedColumn<int>(
    'mileage_km',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _costCentsMeta = const VerificationMeta(
    'costCents',
  );
  @override
  late final GeneratedColumn<int> costCents = GeneratedColumn<int>(
    'cost_cents',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<String> syncStatus = GeneratedColumn<String>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('synced'),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    carId,
    date,
    cycleKey,
    mileageKm,
    costCents,
    note,
    syncStatus,
    updatedAt,
    deletedAt,
    version,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'maintenance_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<MaintenanceRecordRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('car_id')) {
      context.handle(
        _carIdMeta,
        carId.isAcceptableOrUnknown(data['car_id']!, _carIdMeta),
      );
    } else if (isInserting) {
      context.missing(_carIdMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('cycle_key')) {
      context.handle(
        _cycleKeyMeta,
        cycleKey.isAcceptableOrUnknown(data['cycle_key']!, _cycleKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_cycleKeyMeta);
    }
    if (data.containsKey('mileage_km')) {
      context.handle(
        _mileageKmMeta,
        mileageKm.isAcceptableOrUnknown(data['mileage_km']!, _mileageKmMeta),
      );
    } else if (isInserting) {
      context.missing(_mileageKmMeta);
    }
    if (data.containsKey('cost_cents')) {
      context.handle(
        _costCentsMeta,
        costCents.isAcceptableOrUnknown(data['cost_cents']!, _costCentsMeta),
      );
    } else if (isInserting) {
      context.missing(_costCentsMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MaintenanceRecordRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MaintenanceRecordRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      carId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}car_id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      cycleKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cycle_key'],
      )!,
      mileageKm: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}mileage_km'],
      )!,
      costCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cost_cents'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_status'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
    );
  }

  @override
  $MaintenanceRecordsTable createAlias(String alias) {
    return $MaintenanceRecordsTable(attachedDatabase, alias);
  }
}

class MaintenanceRecordRow extends DataClass
    implements Insertable<MaintenanceRecordRow> {
  final String id;
  final String carId;
  final String date;
  final String cycleKey;
  final int mileageKm;
  final int costCents;
  final String? note;
  final String syncStatus;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int version;
  const MaintenanceRecordRow({
    required this.id,
    required this.carId,
    required this.date,
    required this.cycleKey,
    required this.mileageKm,
    required this.costCents,
    this.note,
    required this.syncStatus,
    required this.updatedAt,
    this.deletedAt,
    required this.version,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['car_id'] = Variable<String>(carId);
    map['date'] = Variable<String>(date);
    map['cycle_key'] = Variable<String>(cycleKey);
    map['mileage_km'] = Variable<int>(mileageKm);
    map['cost_cents'] = Variable<int>(costCents);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['sync_status'] = Variable<String>(syncStatus);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['version'] = Variable<int>(version);
    return map;
  }

  MaintenanceRecordsCompanion toCompanion(bool nullToAbsent) {
    return MaintenanceRecordsCompanion(
      id: Value(id),
      carId: Value(carId),
      date: Value(date),
      cycleKey: Value(cycleKey),
      mileageKm: Value(mileageKm),
      costCents: Value(costCents),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      syncStatus: Value(syncStatus),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      version: Value(version),
    );
  }

  factory MaintenanceRecordRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MaintenanceRecordRow(
      id: serializer.fromJson<String>(json['id']),
      carId: serializer.fromJson<String>(json['carId']),
      date: serializer.fromJson<String>(json['date']),
      cycleKey: serializer.fromJson<String>(json['cycleKey']),
      mileageKm: serializer.fromJson<int>(json['mileageKm']),
      costCents: serializer.fromJson<int>(json['costCents']),
      note: serializer.fromJson<String?>(json['note']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      version: serializer.fromJson<int>(json['version']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'carId': serializer.toJson<String>(carId),
      'date': serializer.toJson<String>(date),
      'cycleKey': serializer.toJson<String>(cycleKey),
      'mileageKm': serializer.toJson<int>(mileageKm),
      'costCents': serializer.toJson<int>(costCents),
      'note': serializer.toJson<String?>(note),
      'syncStatus': serializer.toJson<String>(syncStatus),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'version': serializer.toJson<int>(version),
    };
  }

  MaintenanceRecordRow copyWith({
    String? id,
    String? carId,
    String? date,
    String? cycleKey,
    int? mileageKm,
    int? costCents,
    Value<String?> note = const Value.absent(),
    String? syncStatus,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    int? version,
  }) => MaintenanceRecordRow(
    id: id ?? this.id,
    carId: carId ?? this.carId,
    date: date ?? this.date,
    cycleKey: cycleKey ?? this.cycleKey,
    mileageKm: mileageKm ?? this.mileageKm,
    costCents: costCents ?? this.costCents,
    note: note.present ? note.value : this.note,
    syncStatus: syncStatus ?? this.syncStatus,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    version: version ?? this.version,
  );
  MaintenanceRecordRow copyWithCompanion(MaintenanceRecordsCompanion data) {
    return MaintenanceRecordRow(
      id: data.id.present ? data.id.value : this.id,
      carId: data.carId.present ? data.carId.value : this.carId,
      date: data.date.present ? data.date.value : this.date,
      cycleKey: data.cycleKey.present ? data.cycleKey.value : this.cycleKey,
      mileageKm: data.mileageKm.present ? data.mileageKm.value : this.mileageKm,
      costCents: data.costCents.present ? data.costCents.value : this.costCents,
      note: data.note.present ? data.note.value : this.note,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      version: data.version.present ? data.version.value : this.version,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MaintenanceRecordRow(')
          ..write('id: $id, ')
          ..write('carId: $carId, ')
          ..write('date: $date, ')
          ..write('cycleKey: $cycleKey, ')
          ..write('mileageKm: $mileageKm, ')
          ..write('costCents: $costCents, ')
          ..write('note: $note, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    carId,
    date,
    cycleKey,
    mileageKm,
    costCents,
    note,
    syncStatus,
    updatedAt,
    deletedAt,
    version,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MaintenanceRecordRow &&
          other.id == this.id &&
          other.carId == this.carId &&
          other.date == this.date &&
          other.cycleKey == this.cycleKey &&
          other.mileageKm == this.mileageKm &&
          other.costCents == this.costCents &&
          other.note == this.note &&
          other.syncStatus == this.syncStatus &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.version == this.version);
}

class MaintenanceRecordsCompanion
    extends UpdateCompanion<MaintenanceRecordRow> {
  final Value<String> id;
  final Value<String> carId;
  final Value<String> date;
  final Value<String> cycleKey;
  final Value<int> mileageKm;
  final Value<int> costCents;
  final Value<String?> note;
  final Value<String> syncStatus;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> version;
  final Value<int> rowid;
  const MaintenanceRecordsCompanion({
    this.id = const Value.absent(),
    this.carId = const Value.absent(),
    this.date = const Value.absent(),
    this.cycleKey = const Value.absent(),
    this.mileageKm = const Value.absent(),
    this.costCents = const Value.absent(),
    this.note = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MaintenanceRecordsCompanion.insert({
    required String id,
    required String carId,
    required String date,
    required String cycleKey,
    required int mileageKm,
    required int costCents,
    this.note = const Value.absent(),
    this.syncStatus = const Value.absent(),
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       carId = Value(carId),
       date = Value(date),
       cycleKey = Value(cycleKey),
       mileageKm = Value(mileageKm),
       costCents = Value(costCents),
       updatedAt = Value(updatedAt);
  static Insertable<MaintenanceRecordRow> custom({
    Expression<String>? id,
    Expression<String>? carId,
    Expression<String>? date,
    Expression<String>? cycleKey,
    Expression<int>? mileageKm,
    Expression<int>? costCents,
    Expression<String>? note,
    Expression<String>? syncStatus,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? version,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (carId != null) 'car_id': carId,
      if (date != null) 'date': date,
      if (cycleKey != null) 'cycle_key': cycleKey,
      if (mileageKm != null) 'mileage_km': mileageKm,
      if (costCents != null) 'cost_cents': costCents,
      if (note != null) 'note': note,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (version != null) 'version': version,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MaintenanceRecordsCompanion copyWith({
    Value<String>? id,
    Value<String>? carId,
    Value<String>? date,
    Value<String>? cycleKey,
    Value<int>? mileageKm,
    Value<int>? costCents,
    Value<String?>? note,
    Value<String>? syncStatus,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? version,
    Value<int>? rowid,
  }) {
    return MaintenanceRecordsCompanion(
      id: id ?? this.id,
      carId: carId ?? this.carId,
      date: date ?? this.date,
      cycleKey: cycleKey ?? this.cycleKey,
      mileageKm: mileageKm ?? this.mileageKm,
      costCents: costCents ?? this.costCents,
      note: note ?? this.note,
      syncStatus: syncStatus ?? this.syncStatus,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      version: version ?? this.version,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (carId.present) {
      map['car_id'] = Variable<String>(carId.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (cycleKey.present) {
      map['cycle_key'] = Variable<String>(cycleKey.value);
    }
    if (mileageKm.present) {
      map['mileage_km'] = Variable<int>(mileageKm.value);
    }
    if (costCents.present) {
      map['cost_cents'] = Variable<int>(costCents.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MaintenanceRecordsCompanion(')
          ..write('id: $id, ')
          ..write('carId: $carId, ')
          ..write('date: $date, ')
          ..write('cycleKey: $cycleKey, ')
          ..write('mileageKm: $mileageKm, ')
          ..write('costCents: $costCents, ')
          ..write('note: $note, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MaintenanceRecordItemsTable extends MaintenanceRecordItems
    with TableInfo<$MaintenanceRecordItemsTable, MaintenanceRecordItemRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MaintenanceRecordItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordIdMeta = const VerificationMeta(
    'recordId',
  );
  @override
  late final GeneratedColumn<String> recordId = GeneratedColumn<String>(
    'record_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _carIdMeta = const VerificationMeta('carId');
  @override
  late final GeneratedColumn<String> carId = GeneratedColumn<String>(
    'car_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cycleItemKeyMeta = const VerificationMeta(
    'cycleItemKey',
  );
  @override
  late final GeneratedColumn<String> cycleItemKey = GeneratedColumn<String>(
    'cycle_item_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    recordId,
    carId,
    itemId,
    date,
    cycleItemKey,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'maintenance_record_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<MaintenanceRecordItemRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('record_id')) {
      context.handle(
        _recordIdMeta,
        recordId.isAcceptableOrUnknown(data['record_id']!, _recordIdMeta),
      );
    } else if (isInserting) {
      context.missing(_recordIdMeta);
    }
    if (data.containsKey('car_id')) {
      context.handle(
        _carIdMeta,
        carId.isAcceptableOrUnknown(data['car_id']!, _carIdMeta),
      );
    } else if (isInserting) {
      context.missing(_carIdMeta);
    }
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('cycle_item_key')) {
      context.handle(
        _cycleItemKeyMeta,
        cycleItemKey.isAcceptableOrUnknown(
          data['cycle_item_key']!,
          _cycleItemKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_cycleItemKeyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MaintenanceRecordItemRow map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MaintenanceRecordItemRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      recordId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}record_id'],
      )!,
      carId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}car_id'],
      )!,
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      cycleItemKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cycle_item_key'],
      )!,
    );
  }

  @override
  $MaintenanceRecordItemsTable createAlias(String alias) {
    return $MaintenanceRecordItemsTable(attachedDatabase, alias);
  }
}

class MaintenanceRecordItemRow extends DataClass
    implements Insertable<MaintenanceRecordItemRow> {
  final String id;
  final String recordId;
  final String carId;
  final String itemId;
  final String date;
  final String cycleItemKey;
  const MaintenanceRecordItemRow({
    required this.id,
    required this.recordId,
    required this.carId,
    required this.itemId,
    required this.date,
    required this.cycleItemKey,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['record_id'] = Variable<String>(recordId);
    map['car_id'] = Variable<String>(carId);
    map['item_id'] = Variable<String>(itemId);
    map['date'] = Variable<String>(date);
    map['cycle_item_key'] = Variable<String>(cycleItemKey);
    return map;
  }

  MaintenanceRecordItemsCompanion toCompanion(bool nullToAbsent) {
    return MaintenanceRecordItemsCompanion(
      id: Value(id),
      recordId: Value(recordId),
      carId: Value(carId),
      itemId: Value(itemId),
      date: Value(date),
      cycleItemKey: Value(cycleItemKey),
    );
  }

  factory MaintenanceRecordItemRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MaintenanceRecordItemRow(
      id: serializer.fromJson<String>(json['id']),
      recordId: serializer.fromJson<String>(json['recordId']),
      carId: serializer.fromJson<String>(json['carId']),
      itemId: serializer.fromJson<String>(json['itemId']),
      date: serializer.fromJson<String>(json['date']),
      cycleItemKey: serializer.fromJson<String>(json['cycleItemKey']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'recordId': serializer.toJson<String>(recordId),
      'carId': serializer.toJson<String>(carId),
      'itemId': serializer.toJson<String>(itemId),
      'date': serializer.toJson<String>(date),
      'cycleItemKey': serializer.toJson<String>(cycleItemKey),
    };
  }

  MaintenanceRecordItemRow copyWith({
    String? id,
    String? recordId,
    String? carId,
    String? itemId,
    String? date,
    String? cycleItemKey,
  }) => MaintenanceRecordItemRow(
    id: id ?? this.id,
    recordId: recordId ?? this.recordId,
    carId: carId ?? this.carId,
    itemId: itemId ?? this.itemId,
    date: date ?? this.date,
    cycleItemKey: cycleItemKey ?? this.cycleItemKey,
  );
  MaintenanceRecordItemRow copyWithCompanion(
    MaintenanceRecordItemsCompanion data,
  ) {
    return MaintenanceRecordItemRow(
      id: data.id.present ? data.id.value : this.id,
      recordId: data.recordId.present ? data.recordId.value : this.recordId,
      carId: data.carId.present ? data.carId.value : this.carId,
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      date: data.date.present ? data.date.value : this.date,
      cycleItemKey: data.cycleItemKey.present
          ? data.cycleItemKey.value
          : this.cycleItemKey,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MaintenanceRecordItemRow(')
          ..write('id: $id, ')
          ..write('recordId: $recordId, ')
          ..write('carId: $carId, ')
          ..write('itemId: $itemId, ')
          ..write('date: $date, ')
          ..write('cycleItemKey: $cycleItemKey')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, recordId, carId, itemId, date, cycleItemKey);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MaintenanceRecordItemRow &&
          other.id == this.id &&
          other.recordId == this.recordId &&
          other.carId == this.carId &&
          other.itemId == this.itemId &&
          other.date == this.date &&
          other.cycleItemKey == this.cycleItemKey);
}

class MaintenanceRecordItemsCompanion
    extends UpdateCompanion<MaintenanceRecordItemRow> {
  final Value<String> id;
  final Value<String> recordId;
  final Value<String> carId;
  final Value<String> itemId;
  final Value<String> date;
  final Value<String> cycleItemKey;
  final Value<int> rowid;
  const MaintenanceRecordItemsCompanion({
    this.id = const Value.absent(),
    this.recordId = const Value.absent(),
    this.carId = const Value.absent(),
    this.itemId = const Value.absent(),
    this.date = const Value.absent(),
    this.cycleItemKey = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MaintenanceRecordItemsCompanion.insert({
    required String id,
    required String recordId,
    required String carId,
    required String itemId,
    required String date,
    required String cycleItemKey,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       recordId = Value(recordId),
       carId = Value(carId),
       itemId = Value(itemId),
       date = Value(date),
       cycleItemKey = Value(cycleItemKey);
  static Insertable<MaintenanceRecordItemRow> custom({
    Expression<String>? id,
    Expression<String>? recordId,
    Expression<String>? carId,
    Expression<String>? itemId,
    Expression<String>? date,
    Expression<String>? cycleItemKey,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (recordId != null) 'record_id': recordId,
      if (carId != null) 'car_id': carId,
      if (itemId != null) 'item_id': itemId,
      if (date != null) 'date': date,
      if (cycleItemKey != null) 'cycle_item_key': cycleItemKey,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MaintenanceRecordItemsCompanion copyWith({
    Value<String>? id,
    Value<String>? recordId,
    Value<String>? carId,
    Value<String>? itemId,
    Value<String>? date,
    Value<String>? cycleItemKey,
    Value<int>? rowid,
  }) {
    return MaintenanceRecordItemsCompanion(
      id: id ?? this.id,
      recordId: recordId ?? this.recordId,
      carId: carId ?? this.carId,
      itemId: itemId ?? this.itemId,
      date: date ?? this.date,
      cycleItemKey: cycleItemKey ?? this.cycleItemKey,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (recordId.present) {
      map['record_id'] = Variable<String>(recordId.value);
    }
    if (carId.present) {
      map['car_id'] = Variable<String>(carId.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (cycleItemKey.present) {
      map['cycle_item_key'] = Variable<String>(cycleItemKey.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MaintenanceRecordItemsCompanion(')
          ..write('id: $id, ')
          ..write('recordId: $recordId, ')
          ..write('carId: $carId, ')
          ..write('itemId: $itemId, ')
          ..write('date: $date, ')
          ..write('cycleItemKey: $cycleItemKey, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppPreferencesTable extends AppPreferences
    with TableInfo<$AppPreferencesTable, AppPreferenceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppPreferencesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_preferences';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppPreferenceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppPreferenceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppPreferenceRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      ),
    );
  }

  @override
  $AppPreferencesTable createAlias(String alias) {
    return $AppPreferencesTable(attachedDatabase, alias);
  }
}

class AppPreferenceRow extends DataClass
    implements Insertable<AppPreferenceRow> {
  final String key;
  final String? value;
  const AppPreferenceRow({required this.key, this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    if (!nullToAbsent || value != null) {
      map['value'] = Variable<String>(value);
    }
    return map;
  }

  AppPreferencesCompanion toCompanion(bool nullToAbsent) {
    return AppPreferencesCompanion(
      key: Value(key),
      value: value == null && nullToAbsent
          ? const Value.absent()
          : Value(value),
    );
  }

  factory AppPreferenceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppPreferenceRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String?>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String?>(value),
    };
  }

  AppPreferenceRow copyWith({
    String? key,
    Value<String?> value = const Value.absent(),
  }) => AppPreferenceRow(
    key: key ?? this.key,
    value: value.present ? value.value : this.value,
  );
  AppPreferenceRow copyWithCompanion(AppPreferencesCompanion data) {
    return AppPreferenceRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppPreferenceRow(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppPreferenceRow &&
          other.key == this.key &&
          other.value == this.value);
}

class AppPreferencesCompanion extends UpdateCompanion<AppPreferenceRow> {
  final Value<String> key;
  final Value<String?> value;
  final Value<int> rowid;
  const AppPreferencesCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppPreferencesCompanion.insert({
    required String key,
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : key = Value(key);
  static Insertable<AppPreferenceRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppPreferencesCompanion copyWith({
    Value<String>? key,
    Value<String?>? value,
    Value<int>? rowid,
  }) {
    return AppPreferencesCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppPreferencesCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CarsTable cars = $CarsTable(this);
  late final $MaintenanceItemsTable maintenanceItems = $MaintenanceItemsTable(
    this,
  );
  late final $MaintenanceRecordsTable maintenanceRecords =
      $MaintenanceRecordsTable(this);
  late final $MaintenanceRecordItemsTable maintenanceRecordItems =
      $MaintenanceRecordItemsTable(this);
  late final $AppPreferencesTable appPreferences = $AppPreferencesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    cars,
    maintenanceItems,
    maintenanceRecords,
    maintenanceRecordItems,
    appPreferences,
  ];
}

typedef $$CarsTableCreateCompanionBuilder =
    CarsCompanion Function({
      required String id,
      required String brand,
      required String model,
      required String brandModelKey,
      required int currentMileageKm,
      required String roadDate,
      Value<String> syncStatus,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> version,
      Value<int> rowid,
    });
typedef $$CarsTableUpdateCompanionBuilder =
    CarsCompanion Function({
      Value<String> id,
      Value<String> brand,
      Value<String> model,
      Value<String> brandModelKey,
      Value<int> currentMileageKm,
      Value<String> roadDate,
      Value<String> syncStatus,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> version,
      Value<int> rowid,
    });

class $$CarsTableFilterComposer extends Composer<_$AppDatabase, $CarsTable> {
  $$CarsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get brand => $composableBuilder(
    column: $table.brand,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get brandModelKey => $composableBuilder(
    column: $table.brandModelKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get currentMileageKm => $composableBuilder(
    column: $table.currentMileageKm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get roadDate => $composableBuilder(
    column: $table.roadDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CarsTableOrderingComposer extends Composer<_$AppDatabase, $CarsTable> {
  $$CarsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get brand => $composableBuilder(
    column: $table.brand,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get brandModelKey => $composableBuilder(
    column: $table.brandModelKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get currentMileageKm => $composableBuilder(
    column: $table.currentMileageKm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get roadDate => $composableBuilder(
    column: $table.roadDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CarsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CarsTable> {
  $$CarsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get brand =>
      $composableBuilder(column: $table.brand, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<String> get brandModelKey => $composableBuilder(
    column: $table.brandModelKey,
    builder: (column) => column,
  );

  GeneratedColumn<int> get currentMileageKm => $composableBuilder(
    column: $table.currentMileageKm,
    builder: (column) => column,
  );

  GeneratedColumn<String> get roadDate =>
      $composableBuilder(column: $table.roadDate, builder: (column) => column);

  GeneratedColumn<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);
}

class $$CarsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CarsTable,
          CarRow,
          $$CarsTableFilterComposer,
          $$CarsTableOrderingComposer,
          $$CarsTableAnnotationComposer,
          $$CarsTableCreateCompanionBuilder,
          $$CarsTableUpdateCompanionBuilder,
          (CarRow, BaseReferences<_$AppDatabase, $CarsTable, CarRow>),
          CarRow,
          PrefetchHooks Function()
        > {
  $$CarsTableTableManager(_$AppDatabase db, $CarsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CarsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CarsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CarsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> brand = const Value.absent(),
                Value<String> model = const Value.absent(),
                Value<String> brandModelKey = const Value.absent(),
                Value<int> currentMileageKm = const Value.absent(),
                Value<String> roadDate = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CarsCompanion(
                id: id,
                brand: brand,
                model: model,
                brandModelKey: brandModelKey,
                currentMileageKm: currentMileageKm,
                roadDate: roadDate,
                syncStatus: syncStatus,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String brand,
                required String model,
                required String brandModelKey,
                required int currentMileageKm,
                required String roadDate,
                Value<String> syncStatus = const Value.absent(),
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CarsCompanion.insert(
                id: id,
                brand: brand,
                model: model,
                brandModelKey: brandModelKey,
                currentMileageKm: currentMileageKm,
                roadDate: roadDate,
                syncStatus: syncStatus,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CarsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CarsTable,
      CarRow,
      $$CarsTableFilterComposer,
      $$CarsTableOrderingComposer,
      $$CarsTableAnnotationComposer,
      $$CarsTableCreateCompanionBuilder,
      $$CarsTableUpdateCompanionBuilder,
      (CarRow, BaseReferences<_$AppDatabase, $CarsTable, CarRow>),
      CarRow,
      PrefetchHooks Function()
    >;
typedef $$MaintenanceItemsTableCreateCompanionBuilder =
    MaintenanceItemsCompanion Function({
      required String id,
      required String ownerCarId,
      required String name,
      required bool isDefault,
      Value<bool> enabled,
      Value<String?> catalogKey,
      required bool remindByMileage,
      required bool remindByTime,
      Value<int?> mileageIntervalKm,
      Value<int?> timeIntervalMonths,
      Value<int> warningThresholdPercent,
      Value<int> dangerThresholdPercent,
      required int sortOrder,
      Value<String> syncStatus,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> version,
      Value<int> rowid,
    });
typedef $$MaintenanceItemsTableUpdateCompanionBuilder =
    MaintenanceItemsCompanion Function({
      Value<String> id,
      Value<String> ownerCarId,
      Value<String> name,
      Value<bool> isDefault,
      Value<bool> enabled,
      Value<String?> catalogKey,
      Value<bool> remindByMileage,
      Value<bool> remindByTime,
      Value<int?> mileageIntervalKm,
      Value<int?> timeIntervalMonths,
      Value<int> warningThresholdPercent,
      Value<int> dangerThresholdPercent,
      Value<int> sortOrder,
      Value<String> syncStatus,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> version,
      Value<int> rowid,
    });

class $$MaintenanceItemsTableFilterComposer
    extends Composer<_$AppDatabase, $MaintenanceItemsTable> {
  $$MaintenanceItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerCarId => $composableBuilder(
    column: $table.ownerCarId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDefault => $composableBuilder(
    column: $table.isDefault,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get catalogKey => $composableBuilder(
    column: $table.catalogKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get remindByMileage => $composableBuilder(
    column: $table.remindByMileage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get remindByTime => $composableBuilder(
    column: $table.remindByTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get mileageIntervalKm => $composableBuilder(
    column: $table.mileageIntervalKm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timeIntervalMonths => $composableBuilder(
    column: $table.timeIntervalMonths,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get warningThresholdPercent => $composableBuilder(
    column: $table.warningThresholdPercent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dangerThresholdPercent => $composableBuilder(
    column: $table.dangerThresholdPercent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MaintenanceItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $MaintenanceItemsTable> {
  $$MaintenanceItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerCarId => $composableBuilder(
    column: $table.ownerCarId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDefault => $composableBuilder(
    column: $table.isDefault,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get catalogKey => $composableBuilder(
    column: $table.catalogKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get remindByMileage => $composableBuilder(
    column: $table.remindByMileage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get remindByTime => $composableBuilder(
    column: $table.remindByTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get mileageIntervalKm => $composableBuilder(
    column: $table.mileageIntervalKm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timeIntervalMonths => $composableBuilder(
    column: $table.timeIntervalMonths,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get warningThresholdPercent => $composableBuilder(
    column: $table.warningThresholdPercent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dangerThresholdPercent => $composableBuilder(
    column: $table.dangerThresholdPercent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MaintenanceItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MaintenanceItemsTable> {
  $$MaintenanceItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get ownerCarId => $composableBuilder(
    column: $table.ownerCarId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<bool> get isDefault =>
      $composableBuilder(column: $table.isDefault, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<String> get catalogKey => $composableBuilder(
    column: $table.catalogKey,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get remindByMileage => $composableBuilder(
    column: $table.remindByMileage,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get remindByTime => $composableBuilder(
    column: $table.remindByTime,
    builder: (column) => column,
  );

  GeneratedColumn<int> get mileageIntervalKm => $composableBuilder(
    column: $table.mileageIntervalKm,
    builder: (column) => column,
  );

  GeneratedColumn<int> get timeIntervalMonths => $composableBuilder(
    column: $table.timeIntervalMonths,
    builder: (column) => column,
  );

  GeneratedColumn<int> get warningThresholdPercent => $composableBuilder(
    column: $table.warningThresholdPercent,
    builder: (column) => column,
  );

  GeneratedColumn<int> get dangerThresholdPercent => $composableBuilder(
    column: $table.dangerThresholdPercent,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);
}

class $$MaintenanceItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MaintenanceItemsTable,
          MaintenanceItemRow,
          $$MaintenanceItemsTableFilterComposer,
          $$MaintenanceItemsTableOrderingComposer,
          $$MaintenanceItemsTableAnnotationComposer,
          $$MaintenanceItemsTableCreateCompanionBuilder,
          $$MaintenanceItemsTableUpdateCompanionBuilder,
          (
            MaintenanceItemRow,
            BaseReferences<
              _$AppDatabase,
              $MaintenanceItemsTable,
              MaintenanceItemRow
            >,
          ),
          MaintenanceItemRow,
          PrefetchHooks Function()
        > {
  $$MaintenanceItemsTableTableManager(
    _$AppDatabase db,
    $MaintenanceItemsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MaintenanceItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MaintenanceItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MaintenanceItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> ownerCarId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<bool> isDefault = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<String?> catalogKey = const Value.absent(),
                Value<bool> remindByMileage = const Value.absent(),
                Value<bool> remindByTime = const Value.absent(),
                Value<int?> mileageIntervalKm = const Value.absent(),
                Value<int?> timeIntervalMonths = const Value.absent(),
                Value<int> warningThresholdPercent = const Value.absent(),
                Value<int> dangerThresholdPercent = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MaintenanceItemsCompanion(
                id: id,
                ownerCarId: ownerCarId,
                name: name,
                isDefault: isDefault,
                enabled: enabled,
                catalogKey: catalogKey,
                remindByMileage: remindByMileage,
                remindByTime: remindByTime,
                mileageIntervalKm: mileageIntervalKm,
                timeIntervalMonths: timeIntervalMonths,
                warningThresholdPercent: warningThresholdPercent,
                dangerThresholdPercent: dangerThresholdPercent,
                sortOrder: sortOrder,
                syncStatus: syncStatus,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String ownerCarId,
                required String name,
                required bool isDefault,
                Value<bool> enabled = const Value.absent(),
                Value<String?> catalogKey = const Value.absent(),
                required bool remindByMileage,
                required bool remindByTime,
                Value<int?> mileageIntervalKm = const Value.absent(),
                Value<int?> timeIntervalMonths = const Value.absent(),
                Value<int> warningThresholdPercent = const Value.absent(),
                Value<int> dangerThresholdPercent = const Value.absent(),
                required int sortOrder,
                Value<String> syncStatus = const Value.absent(),
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MaintenanceItemsCompanion.insert(
                id: id,
                ownerCarId: ownerCarId,
                name: name,
                isDefault: isDefault,
                enabled: enabled,
                catalogKey: catalogKey,
                remindByMileage: remindByMileage,
                remindByTime: remindByTime,
                mileageIntervalKm: mileageIntervalKm,
                timeIntervalMonths: timeIntervalMonths,
                warningThresholdPercent: warningThresholdPercent,
                dangerThresholdPercent: dangerThresholdPercent,
                sortOrder: sortOrder,
                syncStatus: syncStatus,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MaintenanceItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MaintenanceItemsTable,
      MaintenanceItemRow,
      $$MaintenanceItemsTableFilterComposer,
      $$MaintenanceItemsTableOrderingComposer,
      $$MaintenanceItemsTableAnnotationComposer,
      $$MaintenanceItemsTableCreateCompanionBuilder,
      $$MaintenanceItemsTableUpdateCompanionBuilder,
      (
        MaintenanceItemRow,
        BaseReferences<
          _$AppDatabase,
          $MaintenanceItemsTable,
          MaintenanceItemRow
        >,
      ),
      MaintenanceItemRow,
      PrefetchHooks Function()
    >;
typedef $$MaintenanceRecordsTableCreateCompanionBuilder =
    MaintenanceRecordsCompanion Function({
      required String id,
      required String carId,
      required String date,
      required String cycleKey,
      required int mileageKm,
      required int costCents,
      Value<String?> note,
      Value<String> syncStatus,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> version,
      Value<int> rowid,
    });
typedef $$MaintenanceRecordsTableUpdateCompanionBuilder =
    MaintenanceRecordsCompanion Function({
      Value<String> id,
      Value<String> carId,
      Value<String> date,
      Value<String> cycleKey,
      Value<int> mileageKm,
      Value<int> costCents,
      Value<String?> note,
      Value<String> syncStatus,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> version,
      Value<int> rowid,
    });

class $$MaintenanceRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $MaintenanceRecordsTable> {
  $$MaintenanceRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get carId => $composableBuilder(
    column: $table.carId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cycleKey => $composableBuilder(
    column: $table.cycleKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get mileageKm => $composableBuilder(
    column: $table.mileageKm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get costCents => $composableBuilder(
    column: $table.costCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MaintenanceRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $MaintenanceRecordsTable> {
  $$MaintenanceRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get carId => $composableBuilder(
    column: $table.carId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cycleKey => $composableBuilder(
    column: $table.cycleKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get mileageKm => $composableBuilder(
    column: $table.mileageKm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get costCents => $composableBuilder(
    column: $table.costCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MaintenanceRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MaintenanceRecordsTable> {
  $$MaintenanceRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get carId =>
      $composableBuilder(column: $table.carId, builder: (column) => column);

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get cycleKey =>
      $composableBuilder(column: $table.cycleKey, builder: (column) => column);

  GeneratedColumn<int> get mileageKm =>
      $composableBuilder(column: $table.mileageKm, builder: (column) => column);

  GeneratedColumn<int> get costCents =>
      $composableBuilder(column: $table.costCents, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);
}

class $$MaintenanceRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MaintenanceRecordsTable,
          MaintenanceRecordRow,
          $$MaintenanceRecordsTableFilterComposer,
          $$MaintenanceRecordsTableOrderingComposer,
          $$MaintenanceRecordsTableAnnotationComposer,
          $$MaintenanceRecordsTableCreateCompanionBuilder,
          $$MaintenanceRecordsTableUpdateCompanionBuilder,
          (
            MaintenanceRecordRow,
            BaseReferences<
              _$AppDatabase,
              $MaintenanceRecordsTable,
              MaintenanceRecordRow
            >,
          ),
          MaintenanceRecordRow,
          PrefetchHooks Function()
        > {
  $$MaintenanceRecordsTableTableManager(
    _$AppDatabase db,
    $MaintenanceRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MaintenanceRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MaintenanceRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MaintenanceRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> carId = const Value.absent(),
                Value<String> date = const Value.absent(),
                Value<String> cycleKey = const Value.absent(),
                Value<int> mileageKm = const Value.absent(),
                Value<int> costCents = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MaintenanceRecordsCompanion(
                id: id,
                carId: carId,
                date: date,
                cycleKey: cycleKey,
                mileageKm: mileageKm,
                costCents: costCents,
                note: note,
                syncStatus: syncStatus,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String carId,
                required String date,
                required String cycleKey,
                required int mileageKm,
                required int costCents,
                Value<String?> note = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MaintenanceRecordsCompanion.insert(
                id: id,
                carId: carId,
                date: date,
                cycleKey: cycleKey,
                mileageKm: mileageKm,
                costCents: costCents,
                note: note,
                syncStatus: syncStatus,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MaintenanceRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MaintenanceRecordsTable,
      MaintenanceRecordRow,
      $$MaintenanceRecordsTableFilterComposer,
      $$MaintenanceRecordsTableOrderingComposer,
      $$MaintenanceRecordsTableAnnotationComposer,
      $$MaintenanceRecordsTableCreateCompanionBuilder,
      $$MaintenanceRecordsTableUpdateCompanionBuilder,
      (
        MaintenanceRecordRow,
        BaseReferences<
          _$AppDatabase,
          $MaintenanceRecordsTable,
          MaintenanceRecordRow
        >,
      ),
      MaintenanceRecordRow,
      PrefetchHooks Function()
    >;
typedef $$MaintenanceRecordItemsTableCreateCompanionBuilder =
    MaintenanceRecordItemsCompanion Function({
      required String id,
      required String recordId,
      required String carId,
      required String itemId,
      required String date,
      required String cycleItemKey,
      Value<int> rowid,
    });
typedef $$MaintenanceRecordItemsTableUpdateCompanionBuilder =
    MaintenanceRecordItemsCompanion Function({
      Value<String> id,
      Value<String> recordId,
      Value<String> carId,
      Value<String> itemId,
      Value<String> date,
      Value<String> cycleItemKey,
      Value<int> rowid,
    });

class $$MaintenanceRecordItemsTableFilterComposer
    extends Composer<_$AppDatabase, $MaintenanceRecordItemsTable> {
  $$MaintenanceRecordItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recordId => $composableBuilder(
    column: $table.recordId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get carId => $composableBuilder(
    column: $table.carId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cycleItemKey => $composableBuilder(
    column: $table.cycleItemKey,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MaintenanceRecordItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $MaintenanceRecordItemsTable> {
  $$MaintenanceRecordItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recordId => $composableBuilder(
    column: $table.recordId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get carId => $composableBuilder(
    column: $table.carId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cycleItemKey => $composableBuilder(
    column: $table.cycleItemKey,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MaintenanceRecordItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MaintenanceRecordItemsTable> {
  $$MaintenanceRecordItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get recordId =>
      $composableBuilder(column: $table.recordId, builder: (column) => column);

  GeneratedColumn<String> get carId =>
      $composableBuilder(column: $table.carId, builder: (column) => column);

  GeneratedColumn<String> get itemId =>
      $composableBuilder(column: $table.itemId, builder: (column) => column);

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get cycleItemKey => $composableBuilder(
    column: $table.cycleItemKey,
    builder: (column) => column,
  );
}

class $$MaintenanceRecordItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MaintenanceRecordItemsTable,
          MaintenanceRecordItemRow,
          $$MaintenanceRecordItemsTableFilterComposer,
          $$MaintenanceRecordItemsTableOrderingComposer,
          $$MaintenanceRecordItemsTableAnnotationComposer,
          $$MaintenanceRecordItemsTableCreateCompanionBuilder,
          $$MaintenanceRecordItemsTableUpdateCompanionBuilder,
          (
            MaintenanceRecordItemRow,
            BaseReferences<
              _$AppDatabase,
              $MaintenanceRecordItemsTable,
              MaintenanceRecordItemRow
            >,
          ),
          MaintenanceRecordItemRow,
          PrefetchHooks Function()
        > {
  $$MaintenanceRecordItemsTableTableManager(
    _$AppDatabase db,
    $MaintenanceRecordItemsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MaintenanceRecordItemsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$MaintenanceRecordItemsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$MaintenanceRecordItemsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> recordId = const Value.absent(),
                Value<String> carId = const Value.absent(),
                Value<String> itemId = const Value.absent(),
                Value<String> date = const Value.absent(),
                Value<String> cycleItemKey = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MaintenanceRecordItemsCompanion(
                id: id,
                recordId: recordId,
                carId: carId,
                itemId: itemId,
                date: date,
                cycleItemKey: cycleItemKey,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String recordId,
                required String carId,
                required String itemId,
                required String date,
                required String cycleItemKey,
                Value<int> rowid = const Value.absent(),
              }) => MaintenanceRecordItemsCompanion.insert(
                id: id,
                recordId: recordId,
                carId: carId,
                itemId: itemId,
                date: date,
                cycleItemKey: cycleItemKey,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MaintenanceRecordItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MaintenanceRecordItemsTable,
      MaintenanceRecordItemRow,
      $$MaintenanceRecordItemsTableFilterComposer,
      $$MaintenanceRecordItemsTableOrderingComposer,
      $$MaintenanceRecordItemsTableAnnotationComposer,
      $$MaintenanceRecordItemsTableCreateCompanionBuilder,
      $$MaintenanceRecordItemsTableUpdateCompanionBuilder,
      (
        MaintenanceRecordItemRow,
        BaseReferences<
          _$AppDatabase,
          $MaintenanceRecordItemsTable,
          MaintenanceRecordItemRow
        >,
      ),
      MaintenanceRecordItemRow,
      PrefetchHooks Function()
    >;
typedef $$AppPreferencesTableCreateCompanionBuilder =
    AppPreferencesCompanion Function({
      required String key,
      Value<String?> value,
      Value<int> rowid,
    });
typedef $$AppPreferencesTableUpdateCompanionBuilder =
    AppPreferencesCompanion Function({
      Value<String> key,
      Value<String?> value,
      Value<int> rowid,
    });

class $$AppPreferencesTableFilterComposer
    extends Composer<_$AppDatabase, $AppPreferencesTable> {
  $$AppPreferencesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppPreferencesTableOrderingComposer
    extends Composer<_$AppDatabase, $AppPreferencesTable> {
  $$AppPreferencesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppPreferencesTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppPreferencesTable> {
  $$AppPreferencesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$AppPreferencesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppPreferencesTable,
          AppPreferenceRow,
          $$AppPreferencesTableFilterComposer,
          $$AppPreferencesTableOrderingComposer,
          $$AppPreferencesTableAnnotationComposer,
          $$AppPreferencesTableCreateCompanionBuilder,
          $$AppPreferencesTableUpdateCompanionBuilder,
          (
            AppPreferenceRow,
            BaseReferences<
              _$AppDatabase,
              $AppPreferencesTable,
              AppPreferenceRow
            >,
          ),
          AppPreferenceRow,
          PrefetchHooks Function()
        > {
  $$AppPreferencesTableTableManager(
    _$AppDatabase db,
    $AppPreferencesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppPreferencesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppPreferencesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppPreferencesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String?> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) =>
                  AppPreferencesCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                Value<String?> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppPreferencesCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppPreferencesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppPreferencesTable,
      AppPreferenceRow,
      $$AppPreferencesTableFilterComposer,
      $$AppPreferencesTableOrderingComposer,
      $$AppPreferencesTableAnnotationComposer,
      $$AppPreferencesTableCreateCompanionBuilder,
      $$AppPreferencesTableUpdateCompanionBuilder,
      (
        AppPreferenceRow,
        BaseReferences<_$AppDatabase, $AppPreferencesTable, AppPreferenceRow>,
      ),
      AppPreferenceRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CarsTableTableManager get cars => $$CarsTableTableManager(_db, _db.cars);
  $$MaintenanceItemsTableTableManager get maintenanceItems =>
      $$MaintenanceItemsTableTableManager(_db, _db.maintenanceItems);
  $$MaintenanceRecordsTableTableManager get maintenanceRecords =>
      $$MaintenanceRecordsTableTableManager(_db, _db.maintenanceRecords);
  $$MaintenanceRecordItemsTableTableManager get maintenanceRecordItems =>
      $$MaintenanceRecordItemsTableTableManager(
        _db,
        _db.maintenanceRecordItems,
      );
  $$AppPreferencesTableTableManager get appPreferences =>
      $$AppPreferencesTableTableManager(_db, _db.appPreferences);
}
