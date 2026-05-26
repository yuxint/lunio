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
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
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
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
    currentMileageKm,
    roadDate,
    syncStatus,
    updatedAt,
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
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {brand, model},
  ];
  @override
  CarRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CarRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
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
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
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
  final int id;
  final String brand;
  final String model;
  final int currentMileageKm;
  final String roadDate;
  final String syncStatus;
  final String updatedAt;
  final int version;
  const CarRow({
    required this.id,
    required this.brand,
    required this.model,
    required this.currentMileageKm,
    required this.roadDate,
    required this.syncStatus,
    required this.updatedAt,
    required this.version,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['brand'] = Variable<String>(brand);
    map['model'] = Variable<String>(model);
    map['current_mileage_km'] = Variable<int>(currentMileageKm);
    map['road_date'] = Variable<String>(roadDate);
    map['sync_status'] = Variable<String>(syncStatus);
    map['updated_at'] = Variable<String>(updatedAt);
    map['version'] = Variable<int>(version);
    return map;
  }

  CarsCompanion toCompanion(bool nullToAbsent) {
    return CarsCompanion(
      id: Value(id),
      brand: Value(brand),
      model: Value(model),
      currentMileageKm: Value(currentMileageKm),
      roadDate: Value(roadDate),
      syncStatus: Value(syncStatus),
      updatedAt: Value(updatedAt),
      version: Value(version),
    );
  }

  factory CarRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CarRow(
      id: serializer.fromJson<int>(json['id']),
      brand: serializer.fromJson<String>(json['brand']),
      model: serializer.fromJson<String>(json['model']),
      currentMileageKm: serializer.fromJson<int>(json['currentMileageKm']),
      roadDate: serializer.fromJson<String>(json['roadDate']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
      version: serializer.fromJson<int>(json['version']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'brand': serializer.toJson<String>(brand),
      'model': serializer.toJson<String>(model),
      'currentMileageKm': serializer.toJson<int>(currentMileageKm),
      'roadDate': serializer.toJson<String>(roadDate),
      'syncStatus': serializer.toJson<String>(syncStatus),
      'updatedAt': serializer.toJson<String>(updatedAt),
      'version': serializer.toJson<int>(version),
    };
  }

  CarRow copyWith({
    int? id,
    String? brand,
    String? model,
    int? currentMileageKm,
    String? roadDate,
    String? syncStatus,
    String? updatedAt,
    int? version,
  }) => CarRow(
    id: id ?? this.id,
    brand: brand ?? this.brand,
    model: model ?? this.model,
    currentMileageKm: currentMileageKm ?? this.currentMileageKm,
    roadDate: roadDate ?? this.roadDate,
    syncStatus: syncStatus ?? this.syncStatus,
    updatedAt: updatedAt ?? this.updatedAt,
    version: version ?? this.version,
  );
  CarRow copyWithCompanion(CarsCompanion data) {
    return CarRow(
      id: data.id.present ? data.id.value : this.id,
      brand: data.brand.present ? data.brand.value : this.brand,
      model: data.model.present ? data.model.value : this.model,
      currentMileageKm: data.currentMileageKm.present
          ? data.currentMileageKm.value
          : this.currentMileageKm,
      roadDate: data.roadDate.present ? data.roadDate.value : this.roadDate,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      version: data.version.present ? data.version.value : this.version,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CarRow(')
          ..write('id: $id, ')
          ..write('brand: $brand, ')
          ..write('model: $model, ')
          ..write('currentMileageKm: $currentMileageKm, ')
          ..write('roadDate: $roadDate, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('version: $version')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    brand,
    model,
    currentMileageKm,
    roadDate,
    syncStatus,
    updatedAt,
    version,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CarRow &&
          other.id == this.id &&
          other.brand == this.brand &&
          other.model == this.model &&
          other.currentMileageKm == this.currentMileageKm &&
          other.roadDate == this.roadDate &&
          other.syncStatus == this.syncStatus &&
          other.updatedAt == this.updatedAt &&
          other.version == this.version);
}

class CarsCompanion extends UpdateCompanion<CarRow> {
  final Value<int> id;
  final Value<String> brand;
  final Value<String> model;
  final Value<int> currentMileageKm;
  final Value<String> roadDate;
  final Value<String> syncStatus;
  final Value<String> updatedAt;
  final Value<int> version;
  const CarsCompanion({
    this.id = const Value.absent(),
    this.brand = const Value.absent(),
    this.model = const Value.absent(),
    this.currentMileageKm = const Value.absent(),
    this.roadDate = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.version = const Value.absent(),
  });
  CarsCompanion.insert({
    this.id = const Value.absent(),
    required String brand,
    required String model,
    required int currentMileageKm,
    required String roadDate,
    this.syncStatus = const Value.absent(),
    required String updatedAt,
    this.version = const Value.absent(),
  }) : brand = Value(brand),
       model = Value(model),
       currentMileageKm = Value(currentMileageKm),
       roadDate = Value(roadDate),
       updatedAt = Value(updatedAt);
  static Insertable<CarRow> custom({
    Expression<int>? id,
    Expression<String>? brand,
    Expression<String>? model,
    Expression<int>? currentMileageKm,
    Expression<String>? roadDate,
    Expression<String>? syncStatus,
    Expression<String>? updatedAt,
    Expression<int>? version,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (brand != null) 'brand': brand,
      if (model != null) 'model': model,
      if (currentMileageKm != null) 'current_mileage_km': currentMileageKm,
      if (roadDate != null) 'road_date': roadDate,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (version != null) 'version': version,
    });
  }

  CarsCompanion copyWith({
    Value<int>? id,
    Value<String>? brand,
    Value<String>? model,
    Value<int>? currentMileageKm,
    Value<String>? roadDate,
    Value<String>? syncStatus,
    Value<String>? updatedAt,
    Value<int>? version,
  }) {
    return CarsCompanion(
      id: id ?? this.id,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      currentMileageKm: currentMileageKm ?? this.currentMileageKm,
      roadDate: roadDate ?? this.roadDate,
      syncStatus: syncStatus ?? this.syncStatus,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (brand.present) {
      map['brand'] = Variable<String>(brand.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
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
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CarsCompanion(')
          ..write('id: $id, ')
          ..write('brand: $brand, ')
          ..write('model: $model, ')
          ..write('currentMileageKm: $currentMileageKm, ')
          ..write('roadDate: $roadDate, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('version: $version')
          ..write(')'))
        .toString();
  }
}

class $VehicleDefaultMaintenanceItemsTable
    extends VehicleDefaultMaintenanceItems
    with
        TableInfo<
          $VehicleDefaultMaintenanceItemsTable,
          VehicleDefaultMaintenanceItemRow
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VehicleDefaultMaintenanceItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _vehicleBrandMeta = const VerificationMeta(
    'vehicleBrand',
  );
  @override
  late final GeneratedColumn<String> vehicleBrand = GeneratedColumn<String>(
    'vehicle_brand',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _vehicleModelMeta = const VerificationMeta(
    'vehicleModel',
  );
  @override
  late final GeneratedColumn<String> vehicleModel = GeneratedColumn<String>(
    'vehicle_model',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _itemNameMeta = const VerificationMeta(
    'itemName',
  );
  @override
  late final GeneratedColumn<String> itemName = GeneratedColumn<String>(
    'item_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  static const VerificationMeta _notOverdueUpperLimitMeta =
      const VerificationMeta('notOverdueUpperLimit');
  @override
  late final GeneratedColumn<double> notOverdueUpperLimit =
      GeneratedColumn<double>(
        'not_overdue_upper_limit',
        aliasedName,
        false,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
        defaultValue: const Constant(100),
      );
  static const VerificationMeta _overdueUpperLimitMeta = const VerificationMeta(
    'overdueUpperLimit',
  );
  @override
  late final GeneratedColumn<double> overdueUpperLimit =
      GeneratedColumn<double>(
        'overdue_upper_limit',
        aliasedName,
        false,
        type: DriftSqlType.double,
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
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
    vehicleBrand,
    vehicleModel,
    itemName,
    remindByMileage,
    remindByTime,
    mileageIntervalKm,
    timeIntervalMonths,
    notOverdueUpperLimit,
    overdueUpperLimit,
    sortOrder,
    syncStatus,
    updatedAt,
    version,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'vehicle_default_maintenance_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<VehicleDefaultMaintenanceItemRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('vehicle_brand')) {
      context.handle(
        _vehicleBrandMeta,
        vehicleBrand.isAcceptableOrUnknown(
          data['vehicle_brand']!,
          _vehicleBrandMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_vehicleBrandMeta);
    }
    if (data.containsKey('vehicle_model')) {
      context.handle(
        _vehicleModelMeta,
        vehicleModel.isAcceptableOrUnknown(
          data['vehicle_model']!,
          _vehicleModelMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_vehicleModelMeta);
    }
    if (data.containsKey('item_name')) {
      context.handle(
        _itemNameMeta,
        itemName.isAcceptableOrUnknown(data['item_name']!, _itemNameMeta),
      );
    } else if (isInserting) {
      context.missing(_itemNameMeta);
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
    if (data.containsKey('not_overdue_upper_limit')) {
      context.handle(
        _notOverdueUpperLimitMeta,
        notOverdueUpperLimit.isAcceptableOrUnknown(
          data['not_overdue_upper_limit']!,
          _notOverdueUpperLimitMeta,
        ),
      );
    }
    if (data.containsKey('overdue_upper_limit')) {
      context.handle(
        _overdueUpperLimitMeta,
        overdueUpperLimit.isAcceptableOrUnknown(
          data['overdue_upper_limit']!,
          _overdueUpperLimitMeta,
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
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {vehicleBrand, vehicleModel, itemName},
  ];
  @override
  VehicleDefaultMaintenanceItemRow map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VehicleDefaultMaintenanceItemRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      vehicleBrand: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}vehicle_brand'],
      )!,
      vehicleModel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}vehicle_model'],
      )!,
      itemName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_name'],
      )!,
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
      notOverdueUpperLimit: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}not_overdue_upper_limit'],
      )!,
      overdueUpperLimit: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}overdue_upper_limit'],
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
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
    );
  }

  @override
  $VehicleDefaultMaintenanceItemsTable createAlias(String alias) {
    return $VehicleDefaultMaintenanceItemsTable(attachedDatabase, alias);
  }
}

class VehicleDefaultMaintenanceItemRow extends DataClass
    implements Insertable<VehicleDefaultMaintenanceItemRow> {
  final int id;
  final String vehicleBrand;
  final String vehicleModel;
  final String itemName;
  final bool remindByMileage;
  final bool remindByTime;
  final int? mileageIntervalKm;
  final int? timeIntervalMonths;
  final double notOverdueUpperLimit;
  final double overdueUpperLimit;
  final int sortOrder;
  final String syncStatus;
  final String updatedAt;
  final int version;
  const VehicleDefaultMaintenanceItemRow({
    required this.id,
    required this.vehicleBrand,
    required this.vehicleModel,
    required this.itemName,
    required this.remindByMileage,
    required this.remindByTime,
    this.mileageIntervalKm,
    this.timeIntervalMonths,
    required this.notOverdueUpperLimit,
    required this.overdueUpperLimit,
    required this.sortOrder,
    required this.syncStatus,
    required this.updatedAt,
    required this.version,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['vehicle_brand'] = Variable<String>(vehicleBrand);
    map['vehicle_model'] = Variable<String>(vehicleModel);
    map['item_name'] = Variable<String>(itemName);
    map['remind_by_mileage'] = Variable<bool>(remindByMileage);
    map['remind_by_time'] = Variable<bool>(remindByTime);
    if (!nullToAbsent || mileageIntervalKm != null) {
      map['mileage_interval_km'] = Variable<int>(mileageIntervalKm);
    }
    if (!nullToAbsent || timeIntervalMonths != null) {
      map['time_interval_months'] = Variable<int>(timeIntervalMonths);
    }
    map['not_overdue_upper_limit'] = Variable<double>(notOverdueUpperLimit);
    map['overdue_upper_limit'] = Variable<double>(overdueUpperLimit);
    map['sort_order'] = Variable<int>(sortOrder);
    map['sync_status'] = Variable<String>(syncStatus);
    map['updated_at'] = Variable<String>(updatedAt);
    map['version'] = Variable<int>(version);
    return map;
  }

  VehicleDefaultMaintenanceItemsCompanion toCompanion(bool nullToAbsent) {
    return VehicleDefaultMaintenanceItemsCompanion(
      id: Value(id),
      vehicleBrand: Value(vehicleBrand),
      vehicleModel: Value(vehicleModel),
      itemName: Value(itemName),
      remindByMileage: Value(remindByMileage),
      remindByTime: Value(remindByTime),
      mileageIntervalKm: mileageIntervalKm == null && nullToAbsent
          ? const Value.absent()
          : Value(mileageIntervalKm),
      timeIntervalMonths: timeIntervalMonths == null && nullToAbsent
          ? const Value.absent()
          : Value(timeIntervalMonths),
      notOverdueUpperLimit: Value(notOverdueUpperLimit),
      overdueUpperLimit: Value(overdueUpperLimit),
      sortOrder: Value(sortOrder),
      syncStatus: Value(syncStatus),
      updatedAt: Value(updatedAt),
      version: Value(version),
    );
  }

  factory VehicleDefaultMaintenanceItemRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VehicleDefaultMaintenanceItemRow(
      id: serializer.fromJson<int>(json['id']),
      vehicleBrand: serializer.fromJson<String>(json['vehicleBrand']),
      vehicleModel: serializer.fromJson<String>(json['vehicleModel']),
      itemName: serializer.fromJson<String>(json['itemName']),
      remindByMileage: serializer.fromJson<bool>(json['remindByMileage']),
      remindByTime: serializer.fromJson<bool>(json['remindByTime']),
      mileageIntervalKm: serializer.fromJson<int?>(json['mileageIntervalKm']),
      timeIntervalMonths: serializer.fromJson<int?>(json['timeIntervalMonths']),
      notOverdueUpperLimit: serializer.fromJson<double>(
        json['notOverdueUpperLimit'],
      ),
      overdueUpperLimit: serializer.fromJson<double>(json['overdueUpperLimit']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
      version: serializer.fromJson<int>(json['version']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'vehicleBrand': serializer.toJson<String>(vehicleBrand),
      'vehicleModel': serializer.toJson<String>(vehicleModel),
      'itemName': serializer.toJson<String>(itemName),
      'remindByMileage': serializer.toJson<bool>(remindByMileage),
      'remindByTime': serializer.toJson<bool>(remindByTime),
      'mileageIntervalKm': serializer.toJson<int?>(mileageIntervalKm),
      'timeIntervalMonths': serializer.toJson<int?>(timeIntervalMonths),
      'notOverdueUpperLimit': serializer.toJson<double>(notOverdueUpperLimit),
      'overdueUpperLimit': serializer.toJson<double>(overdueUpperLimit),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'syncStatus': serializer.toJson<String>(syncStatus),
      'updatedAt': serializer.toJson<String>(updatedAt),
      'version': serializer.toJson<int>(version),
    };
  }

  VehicleDefaultMaintenanceItemRow copyWith({
    int? id,
    String? vehicleBrand,
    String? vehicleModel,
    String? itemName,
    bool? remindByMileage,
    bool? remindByTime,
    Value<int?> mileageIntervalKm = const Value.absent(),
    Value<int?> timeIntervalMonths = const Value.absent(),
    double? notOverdueUpperLimit,
    double? overdueUpperLimit,
    int? sortOrder,
    String? syncStatus,
    String? updatedAt,
    int? version,
  }) => VehicleDefaultMaintenanceItemRow(
    id: id ?? this.id,
    vehicleBrand: vehicleBrand ?? this.vehicleBrand,
    vehicleModel: vehicleModel ?? this.vehicleModel,
    itemName: itemName ?? this.itemName,
    remindByMileage: remindByMileage ?? this.remindByMileage,
    remindByTime: remindByTime ?? this.remindByTime,
    mileageIntervalKm: mileageIntervalKm.present
        ? mileageIntervalKm.value
        : this.mileageIntervalKm,
    timeIntervalMonths: timeIntervalMonths.present
        ? timeIntervalMonths.value
        : this.timeIntervalMonths,
    notOverdueUpperLimit: notOverdueUpperLimit ?? this.notOverdueUpperLimit,
    overdueUpperLimit: overdueUpperLimit ?? this.overdueUpperLimit,
    sortOrder: sortOrder ?? this.sortOrder,
    syncStatus: syncStatus ?? this.syncStatus,
    updatedAt: updatedAt ?? this.updatedAt,
    version: version ?? this.version,
  );
  VehicleDefaultMaintenanceItemRow copyWithCompanion(
    VehicleDefaultMaintenanceItemsCompanion data,
  ) {
    return VehicleDefaultMaintenanceItemRow(
      id: data.id.present ? data.id.value : this.id,
      vehicleBrand: data.vehicleBrand.present
          ? data.vehicleBrand.value
          : this.vehicleBrand,
      vehicleModel: data.vehicleModel.present
          ? data.vehicleModel.value
          : this.vehicleModel,
      itemName: data.itemName.present ? data.itemName.value : this.itemName,
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
      notOverdueUpperLimit: data.notOverdueUpperLimit.present
          ? data.notOverdueUpperLimit.value
          : this.notOverdueUpperLimit,
      overdueUpperLimit: data.overdueUpperLimit.present
          ? data.overdueUpperLimit.value
          : this.overdueUpperLimit,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      version: data.version.present ? data.version.value : this.version,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VehicleDefaultMaintenanceItemRow(')
          ..write('id: $id, ')
          ..write('vehicleBrand: $vehicleBrand, ')
          ..write('vehicleModel: $vehicleModel, ')
          ..write('itemName: $itemName, ')
          ..write('remindByMileage: $remindByMileage, ')
          ..write('remindByTime: $remindByTime, ')
          ..write('mileageIntervalKm: $mileageIntervalKm, ')
          ..write('timeIntervalMonths: $timeIntervalMonths, ')
          ..write('notOverdueUpperLimit: $notOverdueUpperLimit, ')
          ..write('overdueUpperLimit: $overdueUpperLimit, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('version: $version')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    vehicleBrand,
    vehicleModel,
    itemName,
    remindByMileage,
    remindByTime,
    mileageIntervalKm,
    timeIntervalMonths,
    notOverdueUpperLimit,
    overdueUpperLimit,
    sortOrder,
    syncStatus,
    updatedAt,
    version,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VehicleDefaultMaintenanceItemRow &&
          other.id == this.id &&
          other.vehicleBrand == this.vehicleBrand &&
          other.vehicleModel == this.vehicleModel &&
          other.itemName == this.itemName &&
          other.remindByMileage == this.remindByMileage &&
          other.remindByTime == this.remindByTime &&
          other.mileageIntervalKm == this.mileageIntervalKm &&
          other.timeIntervalMonths == this.timeIntervalMonths &&
          other.notOverdueUpperLimit == this.notOverdueUpperLimit &&
          other.overdueUpperLimit == this.overdueUpperLimit &&
          other.sortOrder == this.sortOrder &&
          other.syncStatus == this.syncStatus &&
          other.updatedAt == this.updatedAt &&
          other.version == this.version);
}

class VehicleDefaultMaintenanceItemsCompanion
    extends UpdateCompanion<VehicleDefaultMaintenanceItemRow> {
  final Value<int> id;
  final Value<String> vehicleBrand;
  final Value<String> vehicleModel;
  final Value<String> itemName;
  final Value<bool> remindByMileage;
  final Value<bool> remindByTime;
  final Value<int?> mileageIntervalKm;
  final Value<int?> timeIntervalMonths;
  final Value<double> notOverdueUpperLimit;
  final Value<double> overdueUpperLimit;
  final Value<int> sortOrder;
  final Value<String> syncStatus;
  final Value<String> updatedAt;
  final Value<int> version;
  const VehicleDefaultMaintenanceItemsCompanion({
    this.id = const Value.absent(),
    this.vehicleBrand = const Value.absent(),
    this.vehicleModel = const Value.absent(),
    this.itemName = const Value.absent(),
    this.remindByMileage = const Value.absent(),
    this.remindByTime = const Value.absent(),
    this.mileageIntervalKm = const Value.absent(),
    this.timeIntervalMonths = const Value.absent(),
    this.notOverdueUpperLimit = const Value.absent(),
    this.overdueUpperLimit = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.version = const Value.absent(),
  });
  VehicleDefaultMaintenanceItemsCompanion.insert({
    this.id = const Value.absent(),
    required String vehicleBrand,
    required String vehicleModel,
    required String itemName,
    required bool remindByMileage,
    required bool remindByTime,
    this.mileageIntervalKm = const Value.absent(),
    this.timeIntervalMonths = const Value.absent(),
    this.notOverdueUpperLimit = const Value.absent(),
    this.overdueUpperLimit = const Value.absent(),
    required int sortOrder,
    this.syncStatus = const Value.absent(),
    required String updatedAt,
    this.version = const Value.absent(),
  }) : vehicleBrand = Value(vehicleBrand),
       vehicleModel = Value(vehicleModel),
       itemName = Value(itemName),
       remindByMileage = Value(remindByMileage),
       remindByTime = Value(remindByTime),
       sortOrder = Value(sortOrder),
       updatedAt = Value(updatedAt);
  static Insertable<VehicleDefaultMaintenanceItemRow> custom({
    Expression<int>? id,
    Expression<String>? vehicleBrand,
    Expression<String>? vehicleModel,
    Expression<String>? itemName,
    Expression<bool>? remindByMileage,
    Expression<bool>? remindByTime,
    Expression<int>? mileageIntervalKm,
    Expression<int>? timeIntervalMonths,
    Expression<double>? notOverdueUpperLimit,
    Expression<double>? overdueUpperLimit,
    Expression<int>? sortOrder,
    Expression<String>? syncStatus,
    Expression<String>? updatedAt,
    Expression<int>? version,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (vehicleBrand != null) 'vehicle_brand': vehicleBrand,
      if (vehicleModel != null) 'vehicle_model': vehicleModel,
      if (itemName != null) 'item_name': itemName,
      if (remindByMileage != null) 'remind_by_mileage': remindByMileage,
      if (remindByTime != null) 'remind_by_time': remindByTime,
      if (mileageIntervalKm != null) 'mileage_interval_km': mileageIntervalKm,
      if (timeIntervalMonths != null)
        'time_interval_months': timeIntervalMonths,
      if (notOverdueUpperLimit != null)
        'not_overdue_upper_limit': notOverdueUpperLimit,
      if (overdueUpperLimit != null) 'overdue_upper_limit': overdueUpperLimit,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (version != null) 'version': version,
    });
  }

  VehicleDefaultMaintenanceItemsCompanion copyWith({
    Value<int>? id,
    Value<String>? vehicleBrand,
    Value<String>? vehicleModel,
    Value<String>? itemName,
    Value<bool>? remindByMileage,
    Value<bool>? remindByTime,
    Value<int?>? mileageIntervalKm,
    Value<int?>? timeIntervalMonths,
    Value<double>? notOverdueUpperLimit,
    Value<double>? overdueUpperLimit,
    Value<int>? sortOrder,
    Value<String>? syncStatus,
    Value<String>? updatedAt,
    Value<int>? version,
  }) {
    return VehicleDefaultMaintenanceItemsCompanion(
      id: id ?? this.id,
      vehicleBrand: vehicleBrand ?? this.vehicleBrand,
      vehicleModel: vehicleModel ?? this.vehicleModel,
      itemName: itemName ?? this.itemName,
      remindByMileage: remindByMileage ?? this.remindByMileage,
      remindByTime: remindByTime ?? this.remindByTime,
      mileageIntervalKm: mileageIntervalKm ?? this.mileageIntervalKm,
      timeIntervalMonths: timeIntervalMonths ?? this.timeIntervalMonths,
      notOverdueUpperLimit: notOverdueUpperLimit ?? this.notOverdueUpperLimit,
      overdueUpperLimit: overdueUpperLimit ?? this.overdueUpperLimit,
      sortOrder: sortOrder ?? this.sortOrder,
      syncStatus: syncStatus ?? this.syncStatus,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (vehicleBrand.present) {
      map['vehicle_brand'] = Variable<String>(vehicleBrand.value);
    }
    if (vehicleModel.present) {
      map['vehicle_model'] = Variable<String>(vehicleModel.value);
    }
    if (itemName.present) {
      map['item_name'] = Variable<String>(itemName.value);
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
    if (notOverdueUpperLimit.present) {
      map['not_overdue_upper_limit'] = Variable<double>(
        notOverdueUpperLimit.value,
      );
    }
    if (overdueUpperLimit.present) {
      map['overdue_upper_limit'] = Variable<double>(overdueUpperLimit.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VehicleDefaultMaintenanceItemsCompanion(')
          ..write('id: $id, ')
          ..write('vehicleBrand: $vehicleBrand, ')
          ..write('vehicleModel: $vehicleModel, ')
          ..write('itemName: $itemName, ')
          ..write('remindByMileage: $remindByMileage, ')
          ..write('remindByTime: $remindByTime, ')
          ..write('mileageIntervalKm: $mileageIntervalKm, ')
          ..write('timeIntervalMonths: $timeIntervalMonths, ')
          ..write('notOverdueUpperLimit: $notOverdueUpperLimit, ')
          ..write('overdueUpperLimit: $overdueUpperLimit, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('version: $version')
          ..write(')'))
        .toString();
  }
}

class $VehicleModelsTable extends VehicleModels
    with TableInfo<$VehicleModelsTable, VehicleModelRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VehicleModelsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
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
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
    sortOrder,
    syncStatus,
    updatedAt,
    version,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'vehicle_models';
  @override
  VerificationContext validateIntegrity(
    Insertable<VehicleModelRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
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
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {brand, model},
  ];
  @override
  VehicleModelRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VehicleModelRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
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
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_status'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
    );
  }

  @override
  $VehicleModelsTable createAlias(String alias) {
    return $VehicleModelsTable(attachedDatabase, alias);
  }
}

class VehicleModelRow extends DataClass implements Insertable<VehicleModelRow> {
  final int id;
  final String brand;
  final String model;
  final int sortOrder;
  final String syncStatus;
  final String updatedAt;
  final int version;
  const VehicleModelRow({
    required this.id,
    required this.brand,
    required this.model,
    required this.sortOrder,
    required this.syncStatus,
    required this.updatedAt,
    required this.version,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['brand'] = Variable<String>(brand);
    map['model'] = Variable<String>(model);
    map['sort_order'] = Variable<int>(sortOrder);
    map['sync_status'] = Variable<String>(syncStatus);
    map['updated_at'] = Variable<String>(updatedAt);
    map['version'] = Variable<int>(version);
    return map;
  }

  VehicleModelsCompanion toCompanion(bool nullToAbsent) {
    return VehicleModelsCompanion(
      id: Value(id),
      brand: Value(brand),
      model: Value(model),
      sortOrder: Value(sortOrder),
      syncStatus: Value(syncStatus),
      updatedAt: Value(updatedAt),
      version: Value(version),
    );
  }

  factory VehicleModelRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VehicleModelRow(
      id: serializer.fromJson<int>(json['id']),
      brand: serializer.fromJson<String>(json['brand']),
      model: serializer.fromJson<String>(json['model']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
      version: serializer.fromJson<int>(json['version']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'brand': serializer.toJson<String>(brand),
      'model': serializer.toJson<String>(model),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'syncStatus': serializer.toJson<String>(syncStatus),
      'updatedAt': serializer.toJson<String>(updatedAt),
      'version': serializer.toJson<int>(version),
    };
  }

  VehicleModelRow copyWith({
    int? id,
    String? brand,
    String? model,
    int? sortOrder,
    String? syncStatus,
    String? updatedAt,
    int? version,
  }) => VehicleModelRow(
    id: id ?? this.id,
    brand: brand ?? this.brand,
    model: model ?? this.model,
    sortOrder: sortOrder ?? this.sortOrder,
    syncStatus: syncStatus ?? this.syncStatus,
    updatedAt: updatedAt ?? this.updatedAt,
    version: version ?? this.version,
  );
  VehicleModelRow copyWithCompanion(VehicleModelsCompanion data) {
    return VehicleModelRow(
      id: data.id.present ? data.id.value : this.id,
      brand: data.brand.present ? data.brand.value : this.brand,
      model: data.model.present ? data.model.value : this.model,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      version: data.version.present ? data.version.value : this.version,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VehicleModelRow(')
          ..write('id: $id, ')
          ..write('brand: $brand, ')
          ..write('model: $model, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('version: $version')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, brand, model, sortOrder, syncStatus, updatedAt, version);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VehicleModelRow &&
          other.id == this.id &&
          other.brand == this.brand &&
          other.model == this.model &&
          other.sortOrder == this.sortOrder &&
          other.syncStatus == this.syncStatus &&
          other.updatedAt == this.updatedAt &&
          other.version == this.version);
}

class VehicleModelsCompanion extends UpdateCompanion<VehicleModelRow> {
  final Value<int> id;
  final Value<String> brand;
  final Value<String> model;
  final Value<int> sortOrder;
  final Value<String> syncStatus;
  final Value<String> updatedAt;
  final Value<int> version;
  const VehicleModelsCompanion({
    this.id = const Value.absent(),
    this.brand = const Value.absent(),
    this.model = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.version = const Value.absent(),
  });
  VehicleModelsCompanion.insert({
    this.id = const Value.absent(),
    required String brand,
    required String model,
    required int sortOrder,
    this.syncStatus = const Value.absent(),
    required String updatedAt,
    this.version = const Value.absent(),
  }) : brand = Value(brand),
       model = Value(model),
       sortOrder = Value(sortOrder),
       updatedAt = Value(updatedAt);
  static Insertable<VehicleModelRow> custom({
    Expression<int>? id,
    Expression<String>? brand,
    Expression<String>? model,
    Expression<int>? sortOrder,
    Expression<String>? syncStatus,
    Expression<String>? updatedAt,
    Expression<int>? version,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (brand != null) 'brand': brand,
      if (model != null) 'model': model,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (version != null) 'version': version,
    });
  }

  VehicleModelsCompanion copyWith({
    Value<int>? id,
    Value<String>? brand,
    Value<String>? model,
    Value<int>? sortOrder,
    Value<String>? syncStatus,
    Value<String>? updatedAt,
    Value<int>? version,
  }) {
    return VehicleModelsCompanion(
      id: id ?? this.id,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      sortOrder: sortOrder ?? this.sortOrder,
      syncStatus: syncStatus ?? this.syncStatus,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (brand.present) {
      map['brand'] = Variable<String>(brand.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VehicleModelsCompanion(')
          ..write('id: $id, ')
          ..write('brand: $brand, ')
          ..write('model: $model, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('version: $version')
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
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _carsIdMeta = const VerificationMeta('carsId');
  @override
  late final GeneratedColumn<int> carsId = GeneratedColumn<int>(
    'cars_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
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
  static const VerificationMeta _notOverdueUpperLimitMeta =
      const VerificationMeta('notOverdueUpperLimit');
  @override
  late final GeneratedColumn<double> notOverdueUpperLimit =
      GeneratedColumn<double>(
        'not_overdue_upper_limit',
        aliasedName,
        false,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
        defaultValue: const Constant(100),
      );
  static const VerificationMeta _overdueUpperLimitMeta = const VerificationMeta(
    'overdueUpperLimit',
  );
  @override
  late final GeneratedColumn<double> overdueUpperLimit =
      GeneratedColumn<double>(
        'overdue_upper_limit',
        aliasedName,
        false,
        type: DriftSqlType.double,
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
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
    carsId,
    name,
    isDefault,
    enabled,
    remindByMileage,
    remindByTime,
    mileageIntervalKm,
    timeIntervalMonths,
    notOverdueUpperLimit,
    overdueUpperLimit,
    sortOrder,
    syncStatus,
    updatedAt,
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
    }
    if (data.containsKey('cars_id')) {
      context.handle(
        _carsIdMeta,
        carsId.isAcceptableOrUnknown(data['cars_id']!, _carsIdMeta),
      );
    } else if (isInserting) {
      context.missing(_carsIdMeta);
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
    if (data.containsKey('not_overdue_upper_limit')) {
      context.handle(
        _notOverdueUpperLimitMeta,
        notOverdueUpperLimit.isAcceptableOrUnknown(
          data['not_overdue_upper_limit']!,
          _notOverdueUpperLimitMeta,
        ),
      );
    }
    if (data.containsKey('overdue_upper_limit')) {
      context.handle(
        _overdueUpperLimitMeta,
        overdueUpperLimit.isAcceptableOrUnknown(
          data['overdue_upper_limit']!,
          _overdueUpperLimitMeta,
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
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {carsId, name},
  ];
  @override
  MaintenanceItemRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MaintenanceItemRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      carsId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cars_id'],
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
      notOverdueUpperLimit: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}not_overdue_upper_limit'],
      )!,
      overdueUpperLimit: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}overdue_upper_limit'],
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
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
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
  final int id;
  final int carsId;
  final String name;
  final bool isDefault;
  final bool enabled;
  final bool remindByMileage;
  final bool remindByTime;
  final int? mileageIntervalKm;
  final int? timeIntervalMonths;
  final double notOverdueUpperLimit;
  final double overdueUpperLimit;
  final int sortOrder;
  final String syncStatus;
  final String updatedAt;
  final int version;
  const MaintenanceItemRow({
    required this.id,
    required this.carsId,
    required this.name,
    required this.isDefault,
    required this.enabled,
    required this.remindByMileage,
    required this.remindByTime,
    this.mileageIntervalKm,
    this.timeIntervalMonths,
    required this.notOverdueUpperLimit,
    required this.overdueUpperLimit,
    required this.sortOrder,
    required this.syncStatus,
    required this.updatedAt,
    required this.version,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['cars_id'] = Variable<int>(carsId);
    map['name'] = Variable<String>(name);
    map['is_default'] = Variable<bool>(isDefault);
    map['enabled'] = Variable<bool>(enabled);
    map['remind_by_mileage'] = Variable<bool>(remindByMileage);
    map['remind_by_time'] = Variable<bool>(remindByTime);
    if (!nullToAbsent || mileageIntervalKm != null) {
      map['mileage_interval_km'] = Variable<int>(mileageIntervalKm);
    }
    if (!nullToAbsent || timeIntervalMonths != null) {
      map['time_interval_months'] = Variable<int>(timeIntervalMonths);
    }
    map['not_overdue_upper_limit'] = Variable<double>(notOverdueUpperLimit);
    map['overdue_upper_limit'] = Variable<double>(overdueUpperLimit);
    map['sort_order'] = Variable<int>(sortOrder);
    map['sync_status'] = Variable<String>(syncStatus);
    map['updated_at'] = Variable<String>(updatedAt);
    map['version'] = Variable<int>(version);
    return map;
  }

  MaintenanceItemsCompanion toCompanion(bool nullToAbsent) {
    return MaintenanceItemsCompanion(
      id: Value(id),
      carsId: Value(carsId),
      name: Value(name),
      isDefault: Value(isDefault),
      enabled: Value(enabled),
      remindByMileage: Value(remindByMileage),
      remindByTime: Value(remindByTime),
      mileageIntervalKm: mileageIntervalKm == null && nullToAbsent
          ? const Value.absent()
          : Value(mileageIntervalKm),
      timeIntervalMonths: timeIntervalMonths == null && nullToAbsent
          ? const Value.absent()
          : Value(timeIntervalMonths),
      notOverdueUpperLimit: Value(notOverdueUpperLimit),
      overdueUpperLimit: Value(overdueUpperLimit),
      sortOrder: Value(sortOrder),
      syncStatus: Value(syncStatus),
      updatedAt: Value(updatedAt),
      version: Value(version),
    );
  }

  factory MaintenanceItemRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MaintenanceItemRow(
      id: serializer.fromJson<int>(json['id']),
      carsId: serializer.fromJson<int>(json['carsId']),
      name: serializer.fromJson<String>(json['name']),
      isDefault: serializer.fromJson<bool>(json['isDefault']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      remindByMileage: serializer.fromJson<bool>(json['remindByMileage']),
      remindByTime: serializer.fromJson<bool>(json['remindByTime']),
      mileageIntervalKm: serializer.fromJson<int?>(json['mileageIntervalKm']),
      timeIntervalMonths: serializer.fromJson<int?>(json['timeIntervalMonths']),
      notOverdueUpperLimit: serializer.fromJson<double>(
        json['notOverdueUpperLimit'],
      ),
      overdueUpperLimit: serializer.fromJson<double>(json['overdueUpperLimit']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
      version: serializer.fromJson<int>(json['version']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'carsId': serializer.toJson<int>(carsId),
      'name': serializer.toJson<String>(name),
      'isDefault': serializer.toJson<bool>(isDefault),
      'enabled': serializer.toJson<bool>(enabled),
      'remindByMileage': serializer.toJson<bool>(remindByMileage),
      'remindByTime': serializer.toJson<bool>(remindByTime),
      'mileageIntervalKm': serializer.toJson<int?>(mileageIntervalKm),
      'timeIntervalMonths': serializer.toJson<int?>(timeIntervalMonths),
      'notOverdueUpperLimit': serializer.toJson<double>(notOverdueUpperLimit),
      'overdueUpperLimit': serializer.toJson<double>(overdueUpperLimit),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'syncStatus': serializer.toJson<String>(syncStatus),
      'updatedAt': serializer.toJson<String>(updatedAt),
      'version': serializer.toJson<int>(version),
    };
  }

  MaintenanceItemRow copyWith({
    int? id,
    int? carsId,
    String? name,
    bool? isDefault,
    bool? enabled,
    bool? remindByMileage,
    bool? remindByTime,
    Value<int?> mileageIntervalKm = const Value.absent(),
    Value<int?> timeIntervalMonths = const Value.absent(),
    double? notOverdueUpperLimit,
    double? overdueUpperLimit,
    int? sortOrder,
    String? syncStatus,
    String? updatedAt,
    int? version,
  }) => MaintenanceItemRow(
    id: id ?? this.id,
    carsId: carsId ?? this.carsId,
    name: name ?? this.name,
    isDefault: isDefault ?? this.isDefault,
    enabled: enabled ?? this.enabled,
    remindByMileage: remindByMileage ?? this.remindByMileage,
    remindByTime: remindByTime ?? this.remindByTime,
    mileageIntervalKm: mileageIntervalKm.present
        ? mileageIntervalKm.value
        : this.mileageIntervalKm,
    timeIntervalMonths: timeIntervalMonths.present
        ? timeIntervalMonths.value
        : this.timeIntervalMonths,
    notOverdueUpperLimit: notOverdueUpperLimit ?? this.notOverdueUpperLimit,
    overdueUpperLimit: overdueUpperLimit ?? this.overdueUpperLimit,
    sortOrder: sortOrder ?? this.sortOrder,
    syncStatus: syncStatus ?? this.syncStatus,
    updatedAt: updatedAt ?? this.updatedAt,
    version: version ?? this.version,
  );
  MaintenanceItemRow copyWithCompanion(MaintenanceItemsCompanion data) {
    return MaintenanceItemRow(
      id: data.id.present ? data.id.value : this.id,
      carsId: data.carsId.present ? data.carsId.value : this.carsId,
      name: data.name.present ? data.name.value : this.name,
      isDefault: data.isDefault.present ? data.isDefault.value : this.isDefault,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
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
      notOverdueUpperLimit: data.notOverdueUpperLimit.present
          ? data.notOverdueUpperLimit.value
          : this.notOverdueUpperLimit,
      overdueUpperLimit: data.overdueUpperLimit.present
          ? data.overdueUpperLimit.value
          : this.overdueUpperLimit,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      version: data.version.present ? data.version.value : this.version,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MaintenanceItemRow(')
          ..write('id: $id, ')
          ..write('carsId: $carsId, ')
          ..write('name: $name, ')
          ..write('isDefault: $isDefault, ')
          ..write('enabled: $enabled, ')
          ..write('remindByMileage: $remindByMileage, ')
          ..write('remindByTime: $remindByTime, ')
          ..write('mileageIntervalKm: $mileageIntervalKm, ')
          ..write('timeIntervalMonths: $timeIntervalMonths, ')
          ..write('notOverdueUpperLimit: $notOverdueUpperLimit, ')
          ..write('overdueUpperLimit: $overdueUpperLimit, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('version: $version')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    carsId,
    name,
    isDefault,
    enabled,
    remindByMileage,
    remindByTime,
    mileageIntervalKm,
    timeIntervalMonths,
    notOverdueUpperLimit,
    overdueUpperLimit,
    sortOrder,
    syncStatus,
    updatedAt,
    version,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MaintenanceItemRow &&
          other.id == this.id &&
          other.carsId == this.carsId &&
          other.name == this.name &&
          other.isDefault == this.isDefault &&
          other.enabled == this.enabled &&
          other.remindByMileage == this.remindByMileage &&
          other.remindByTime == this.remindByTime &&
          other.mileageIntervalKm == this.mileageIntervalKm &&
          other.timeIntervalMonths == this.timeIntervalMonths &&
          other.notOverdueUpperLimit == this.notOverdueUpperLimit &&
          other.overdueUpperLimit == this.overdueUpperLimit &&
          other.sortOrder == this.sortOrder &&
          other.syncStatus == this.syncStatus &&
          other.updatedAt == this.updatedAt &&
          other.version == this.version);
}

class MaintenanceItemsCompanion extends UpdateCompanion<MaintenanceItemRow> {
  final Value<int> id;
  final Value<int> carsId;
  final Value<String> name;
  final Value<bool> isDefault;
  final Value<bool> enabled;
  final Value<bool> remindByMileage;
  final Value<bool> remindByTime;
  final Value<int?> mileageIntervalKm;
  final Value<int?> timeIntervalMonths;
  final Value<double> notOverdueUpperLimit;
  final Value<double> overdueUpperLimit;
  final Value<int> sortOrder;
  final Value<String> syncStatus;
  final Value<String> updatedAt;
  final Value<int> version;
  const MaintenanceItemsCompanion({
    this.id = const Value.absent(),
    this.carsId = const Value.absent(),
    this.name = const Value.absent(),
    this.isDefault = const Value.absent(),
    this.enabled = const Value.absent(),
    this.remindByMileage = const Value.absent(),
    this.remindByTime = const Value.absent(),
    this.mileageIntervalKm = const Value.absent(),
    this.timeIntervalMonths = const Value.absent(),
    this.notOverdueUpperLimit = const Value.absent(),
    this.overdueUpperLimit = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.version = const Value.absent(),
  });
  MaintenanceItemsCompanion.insert({
    this.id = const Value.absent(),
    required int carsId,
    required String name,
    required bool isDefault,
    this.enabled = const Value.absent(),
    required bool remindByMileage,
    required bool remindByTime,
    this.mileageIntervalKm = const Value.absent(),
    this.timeIntervalMonths = const Value.absent(),
    this.notOverdueUpperLimit = const Value.absent(),
    this.overdueUpperLimit = const Value.absent(),
    required int sortOrder,
    this.syncStatus = const Value.absent(),
    required String updatedAt,
    this.version = const Value.absent(),
  }) : carsId = Value(carsId),
       name = Value(name),
       isDefault = Value(isDefault),
       remindByMileage = Value(remindByMileage),
       remindByTime = Value(remindByTime),
       sortOrder = Value(sortOrder),
       updatedAt = Value(updatedAt);
  static Insertable<MaintenanceItemRow> custom({
    Expression<int>? id,
    Expression<int>? carsId,
    Expression<String>? name,
    Expression<bool>? isDefault,
    Expression<bool>? enabled,
    Expression<bool>? remindByMileage,
    Expression<bool>? remindByTime,
    Expression<int>? mileageIntervalKm,
    Expression<int>? timeIntervalMonths,
    Expression<double>? notOverdueUpperLimit,
    Expression<double>? overdueUpperLimit,
    Expression<int>? sortOrder,
    Expression<String>? syncStatus,
    Expression<String>? updatedAt,
    Expression<int>? version,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (carsId != null) 'cars_id': carsId,
      if (name != null) 'name': name,
      if (isDefault != null) 'is_default': isDefault,
      if (enabled != null) 'enabled': enabled,
      if (remindByMileage != null) 'remind_by_mileage': remindByMileage,
      if (remindByTime != null) 'remind_by_time': remindByTime,
      if (mileageIntervalKm != null) 'mileage_interval_km': mileageIntervalKm,
      if (timeIntervalMonths != null)
        'time_interval_months': timeIntervalMonths,
      if (notOverdueUpperLimit != null)
        'not_overdue_upper_limit': notOverdueUpperLimit,
      if (overdueUpperLimit != null) 'overdue_upper_limit': overdueUpperLimit,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (version != null) 'version': version,
    });
  }

  MaintenanceItemsCompanion copyWith({
    Value<int>? id,
    Value<int>? carsId,
    Value<String>? name,
    Value<bool>? isDefault,
    Value<bool>? enabled,
    Value<bool>? remindByMileage,
    Value<bool>? remindByTime,
    Value<int?>? mileageIntervalKm,
    Value<int?>? timeIntervalMonths,
    Value<double>? notOverdueUpperLimit,
    Value<double>? overdueUpperLimit,
    Value<int>? sortOrder,
    Value<String>? syncStatus,
    Value<String>? updatedAt,
    Value<int>? version,
  }) {
    return MaintenanceItemsCompanion(
      id: id ?? this.id,
      carsId: carsId ?? this.carsId,
      name: name ?? this.name,
      isDefault: isDefault ?? this.isDefault,
      enabled: enabled ?? this.enabled,
      remindByMileage: remindByMileage ?? this.remindByMileage,
      remindByTime: remindByTime ?? this.remindByTime,
      mileageIntervalKm: mileageIntervalKm ?? this.mileageIntervalKm,
      timeIntervalMonths: timeIntervalMonths ?? this.timeIntervalMonths,
      notOverdueUpperLimit: notOverdueUpperLimit ?? this.notOverdueUpperLimit,
      overdueUpperLimit: overdueUpperLimit ?? this.overdueUpperLimit,
      sortOrder: sortOrder ?? this.sortOrder,
      syncStatus: syncStatus ?? this.syncStatus,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (carsId.present) {
      map['cars_id'] = Variable<int>(carsId.value);
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
    if (notOverdueUpperLimit.present) {
      map['not_overdue_upper_limit'] = Variable<double>(
        notOverdueUpperLimit.value,
      );
    }
    if (overdueUpperLimit.present) {
      map['overdue_upper_limit'] = Variable<double>(overdueUpperLimit.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MaintenanceItemsCompanion(')
          ..write('id: $id, ')
          ..write('carsId: $carsId, ')
          ..write('name: $name, ')
          ..write('isDefault: $isDefault, ')
          ..write('enabled: $enabled, ')
          ..write('remindByMileage: $remindByMileage, ')
          ..write('remindByTime: $remindByTime, ')
          ..write('mileageIntervalKm: $mileageIntervalKm, ')
          ..write('timeIntervalMonths: $timeIntervalMonths, ')
          ..write('notOverdueUpperLimit: $notOverdueUpperLimit, ')
          ..write('overdueUpperLimit: $overdueUpperLimit, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('version: $version')
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
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _carIdMeta = const VerificationMeta('carId');
  @override
  late final GeneratedColumn<int> carId = GeneratedColumn<int>(
    'car_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
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
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
    mileageKm,
    costCents,
    note,
    syncStatus,
    updatedAt,
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
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {carId, date},
  ];
  @override
  MaintenanceRecordRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MaintenanceRecordRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      carId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}car_id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
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
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
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
  final int id;
  final int carId;
  final String date;
  final int mileageKm;
  final int costCents;
  final String? note;
  final String syncStatus;
  final String updatedAt;
  final int version;
  const MaintenanceRecordRow({
    required this.id,
    required this.carId,
    required this.date,
    required this.mileageKm,
    required this.costCents,
    this.note,
    required this.syncStatus,
    required this.updatedAt,
    required this.version,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['car_id'] = Variable<int>(carId);
    map['date'] = Variable<String>(date);
    map['mileage_km'] = Variable<int>(mileageKm);
    map['cost_cents'] = Variable<int>(costCents);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['sync_status'] = Variable<String>(syncStatus);
    map['updated_at'] = Variable<String>(updatedAt);
    map['version'] = Variable<int>(version);
    return map;
  }

  MaintenanceRecordsCompanion toCompanion(bool nullToAbsent) {
    return MaintenanceRecordsCompanion(
      id: Value(id),
      carId: Value(carId),
      date: Value(date),
      mileageKm: Value(mileageKm),
      costCents: Value(costCents),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      syncStatus: Value(syncStatus),
      updatedAt: Value(updatedAt),
      version: Value(version),
    );
  }

  factory MaintenanceRecordRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MaintenanceRecordRow(
      id: serializer.fromJson<int>(json['id']),
      carId: serializer.fromJson<int>(json['carId']),
      date: serializer.fromJson<String>(json['date']),
      mileageKm: serializer.fromJson<int>(json['mileageKm']),
      costCents: serializer.fromJson<int>(json['costCents']),
      note: serializer.fromJson<String?>(json['note']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
      version: serializer.fromJson<int>(json['version']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'carId': serializer.toJson<int>(carId),
      'date': serializer.toJson<String>(date),
      'mileageKm': serializer.toJson<int>(mileageKm),
      'costCents': serializer.toJson<int>(costCents),
      'note': serializer.toJson<String?>(note),
      'syncStatus': serializer.toJson<String>(syncStatus),
      'updatedAt': serializer.toJson<String>(updatedAt),
      'version': serializer.toJson<int>(version),
    };
  }

  MaintenanceRecordRow copyWith({
    int? id,
    int? carId,
    String? date,
    int? mileageKm,
    int? costCents,
    Value<String?> note = const Value.absent(),
    String? syncStatus,
    String? updatedAt,
    int? version,
  }) => MaintenanceRecordRow(
    id: id ?? this.id,
    carId: carId ?? this.carId,
    date: date ?? this.date,
    mileageKm: mileageKm ?? this.mileageKm,
    costCents: costCents ?? this.costCents,
    note: note.present ? note.value : this.note,
    syncStatus: syncStatus ?? this.syncStatus,
    updatedAt: updatedAt ?? this.updatedAt,
    version: version ?? this.version,
  );
  MaintenanceRecordRow copyWithCompanion(MaintenanceRecordsCompanion data) {
    return MaintenanceRecordRow(
      id: data.id.present ? data.id.value : this.id,
      carId: data.carId.present ? data.carId.value : this.carId,
      date: data.date.present ? data.date.value : this.date,
      mileageKm: data.mileageKm.present ? data.mileageKm.value : this.mileageKm,
      costCents: data.costCents.present ? data.costCents.value : this.costCents,
      note: data.note.present ? data.note.value : this.note,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      version: data.version.present ? data.version.value : this.version,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MaintenanceRecordRow(')
          ..write('id: $id, ')
          ..write('carId: $carId, ')
          ..write('date: $date, ')
          ..write('mileageKm: $mileageKm, ')
          ..write('costCents: $costCents, ')
          ..write('note: $note, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('version: $version')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    carId,
    date,
    mileageKm,
    costCents,
    note,
    syncStatus,
    updatedAt,
    version,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MaintenanceRecordRow &&
          other.id == this.id &&
          other.carId == this.carId &&
          other.date == this.date &&
          other.mileageKm == this.mileageKm &&
          other.costCents == this.costCents &&
          other.note == this.note &&
          other.syncStatus == this.syncStatus &&
          other.updatedAt == this.updatedAt &&
          other.version == this.version);
}

class MaintenanceRecordsCompanion
    extends UpdateCompanion<MaintenanceRecordRow> {
  final Value<int> id;
  final Value<int> carId;
  final Value<String> date;
  final Value<int> mileageKm;
  final Value<int> costCents;
  final Value<String?> note;
  final Value<String> syncStatus;
  final Value<String> updatedAt;
  final Value<int> version;
  const MaintenanceRecordsCompanion({
    this.id = const Value.absent(),
    this.carId = const Value.absent(),
    this.date = const Value.absent(),
    this.mileageKm = const Value.absent(),
    this.costCents = const Value.absent(),
    this.note = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.version = const Value.absent(),
  });
  MaintenanceRecordsCompanion.insert({
    this.id = const Value.absent(),
    required int carId,
    required String date,
    required int mileageKm,
    required int costCents,
    this.note = const Value.absent(),
    this.syncStatus = const Value.absent(),
    required String updatedAt,
    this.version = const Value.absent(),
  }) : carId = Value(carId),
       date = Value(date),
       mileageKm = Value(mileageKm),
       costCents = Value(costCents),
       updatedAt = Value(updatedAt);
  static Insertable<MaintenanceRecordRow> custom({
    Expression<int>? id,
    Expression<int>? carId,
    Expression<String>? date,
    Expression<int>? mileageKm,
    Expression<int>? costCents,
    Expression<String>? note,
    Expression<String>? syncStatus,
    Expression<String>? updatedAt,
    Expression<int>? version,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (carId != null) 'car_id': carId,
      if (date != null) 'date': date,
      if (mileageKm != null) 'mileage_km': mileageKm,
      if (costCents != null) 'cost_cents': costCents,
      if (note != null) 'note': note,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (version != null) 'version': version,
    });
  }

  MaintenanceRecordsCompanion copyWith({
    Value<int>? id,
    Value<int>? carId,
    Value<String>? date,
    Value<int>? mileageKm,
    Value<int>? costCents,
    Value<String?>? note,
    Value<String>? syncStatus,
    Value<String>? updatedAt,
    Value<int>? version,
  }) {
    return MaintenanceRecordsCompanion(
      id: id ?? this.id,
      carId: carId ?? this.carId,
      date: date ?? this.date,
      mileageKm: mileageKm ?? this.mileageKm,
      costCents: costCents ?? this.costCents,
      note: note ?? this.note,
      syncStatus: syncStatus ?? this.syncStatus,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (carId.present) {
      map['car_id'] = Variable<int>(carId.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
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
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MaintenanceRecordsCompanion(')
          ..write('id: $id, ')
          ..write('carId: $carId, ')
          ..write('date: $date, ')
          ..write('mileageKm: $mileageKm, ')
          ..write('costCents: $costCents, ')
          ..write('note: $note, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('version: $version')
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
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _maintenanceRecordIdMeta =
      const VerificationMeta('maintenanceRecordId');
  @override
  late final GeneratedColumn<int> maintenanceRecordId = GeneratedColumn<int>(
    'maintenance_record_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _carIdMeta = const VerificationMeta('carId');
  @override
  late final GeneratedColumn<int> carId = GeneratedColumn<int>(
    'car_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<int> itemId = GeneratedColumn<int>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
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
  @override
  List<GeneratedColumn> get $columns => [
    id,
    maintenanceRecordId,
    carId,
    itemId,
    date,
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
    }
    if (data.containsKey('maintenance_record_id')) {
      context.handle(
        _maintenanceRecordIdMeta,
        maintenanceRecordId.isAcceptableOrUnknown(
          data['maintenance_record_id']!,
          _maintenanceRecordIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_maintenanceRecordIdMeta);
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {carId, date, itemId},
  ];
  @override
  MaintenanceRecordItemRow map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MaintenanceRecordItemRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      maintenanceRecordId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}maintenance_record_id'],
      )!,
      carId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}car_id'],
      )!,
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}item_id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
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
  final int id;
  final int maintenanceRecordId;
  final int carId;
  final int itemId;
  final String date;
  const MaintenanceRecordItemRow({
    required this.id,
    required this.maintenanceRecordId,
    required this.carId,
    required this.itemId,
    required this.date,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['maintenance_record_id'] = Variable<int>(maintenanceRecordId);
    map['car_id'] = Variable<int>(carId);
    map['item_id'] = Variable<int>(itemId);
    map['date'] = Variable<String>(date);
    return map;
  }

  MaintenanceRecordItemsCompanion toCompanion(bool nullToAbsent) {
    return MaintenanceRecordItemsCompanion(
      id: Value(id),
      maintenanceRecordId: Value(maintenanceRecordId),
      carId: Value(carId),
      itemId: Value(itemId),
      date: Value(date),
    );
  }

  factory MaintenanceRecordItemRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MaintenanceRecordItemRow(
      id: serializer.fromJson<int>(json['id']),
      maintenanceRecordId: serializer.fromJson<int>(
        json['maintenanceRecordId'],
      ),
      carId: serializer.fromJson<int>(json['carId']),
      itemId: serializer.fromJson<int>(json['itemId']),
      date: serializer.fromJson<String>(json['date']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'maintenanceRecordId': serializer.toJson<int>(maintenanceRecordId),
      'carId': serializer.toJson<int>(carId),
      'itemId': serializer.toJson<int>(itemId),
      'date': serializer.toJson<String>(date),
    };
  }

  MaintenanceRecordItemRow copyWith({
    int? id,
    int? maintenanceRecordId,
    int? carId,
    int? itemId,
    String? date,
  }) => MaintenanceRecordItemRow(
    id: id ?? this.id,
    maintenanceRecordId: maintenanceRecordId ?? this.maintenanceRecordId,
    carId: carId ?? this.carId,
    itemId: itemId ?? this.itemId,
    date: date ?? this.date,
  );
  MaintenanceRecordItemRow copyWithCompanion(
    MaintenanceRecordItemsCompanion data,
  ) {
    return MaintenanceRecordItemRow(
      id: data.id.present ? data.id.value : this.id,
      maintenanceRecordId: data.maintenanceRecordId.present
          ? data.maintenanceRecordId.value
          : this.maintenanceRecordId,
      carId: data.carId.present ? data.carId.value : this.carId,
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      date: data.date.present ? data.date.value : this.date,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MaintenanceRecordItemRow(')
          ..write('id: $id, ')
          ..write('maintenanceRecordId: $maintenanceRecordId, ')
          ..write('carId: $carId, ')
          ..write('itemId: $itemId, ')
          ..write('date: $date')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, maintenanceRecordId, carId, itemId, date);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MaintenanceRecordItemRow &&
          other.id == this.id &&
          other.maintenanceRecordId == this.maintenanceRecordId &&
          other.carId == this.carId &&
          other.itemId == this.itemId &&
          other.date == this.date);
}

class MaintenanceRecordItemsCompanion
    extends UpdateCompanion<MaintenanceRecordItemRow> {
  final Value<int> id;
  final Value<int> maintenanceRecordId;
  final Value<int> carId;
  final Value<int> itemId;
  final Value<String> date;
  const MaintenanceRecordItemsCompanion({
    this.id = const Value.absent(),
    this.maintenanceRecordId = const Value.absent(),
    this.carId = const Value.absent(),
    this.itemId = const Value.absent(),
    this.date = const Value.absent(),
  });
  MaintenanceRecordItemsCompanion.insert({
    this.id = const Value.absent(),
    required int maintenanceRecordId,
    required int carId,
    required int itemId,
    required String date,
  }) : maintenanceRecordId = Value(maintenanceRecordId),
       carId = Value(carId),
       itemId = Value(itemId),
       date = Value(date);
  static Insertable<MaintenanceRecordItemRow> custom({
    Expression<int>? id,
    Expression<int>? maintenanceRecordId,
    Expression<int>? carId,
    Expression<int>? itemId,
    Expression<String>? date,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (maintenanceRecordId != null)
        'maintenance_record_id': maintenanceRecordId,
      if (carId != null) 'car_id': carId,
      if (itemId != null) 'item_id': itemId,
      if (date != null) 'date': date,
    });
  }

  MaintenanceRecordItemsCompanion copyWith({
    Value<int>? id,
    Value<int>? maintenanceRecordId,
    Value<int>? carId,
    Value<int>? itemId,
    Value<String>? date,
  }) {
    return MaintenanceRecordItemsCompanion(
      id: id ?? this.id,
      maintenanceRecordId: maintenanceRecordId ?? this.maintenanceRecordId,
      carId: carId ?? this.carId,
      itemId: itemId ?? this.itemId,
      date: date ?? this.date,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (maintenanceRecordId.present) {
      map['maintenance_record_id'] = Variable<int>(maintenanceRecordId.value);
    }
    if (carId.present) {
      map['car_id'] = Variable<int>(carId.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<int>(itemId.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MaintenanceRecordItemsCompanion(')
          ..write('id: $id, ')
          ..write('maintenanceRecordId: $maintenanceRecordId, ')
          ..write('carId: $carId, ')
          ..write('itemId: $itemId, ')
          ..write('date: $date')
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
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
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
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
    key,
    value,
    syncStatus,
    updatedAt,
    version,
  ];
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
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
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
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {key},
  ];
  @override
  AppPreferenceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppPreferenceRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      ),
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_status'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
    );
  }

  @override
  $AppPreferencesTable createAlias(String alias) {
    return $AppPreferencesTable(attachedDatabase, alias);
  }
}

class AppPreferenceRow extends DataClass
    implements Insertable<AppPreferenceRow> {
  final int id;
  final String key;
  final String? value;
  final String syncStatus;
  final String updatedAt;
  final int version;
  const AppPreferenceRow({
    required this.id,
    required this.key,
    this.value,
    required this.syncStatus,
    required this.updatedAt,
    required this.version,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['key'] = Variable<String>(key);
    if (!nullToAbsent || value != null) {
      map['value'] = Variable<String>(value);
    }
    map['sync_status'] = Variable<String>(syncStatus);
    map['updated_at'] = Variable<String>(updatedAt);
    map['version'] = Variable<int>(version);
    return map;
  }

  AppPreferencesCompanion toCompanion(bool nullToAbsent) {
    return AppPreferencesCompanion(
      id: Value(id),
      key: Value(key),
      value: value == null && nullToAbsent
          ? const Value.absent()
          : Value(value),
      syncStatus: Value(syncStatus),
      updatedAt: Value(updatedAt),
      version: Value(version),
    );
  }

  factory AppPreferenceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppPreferenceRow(
      id: serializer.fromJson<int>(json['id']),
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String?>(json['value']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
      version: serializer.fromJson<int>(json['version']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String?>(value),
      'syncStatus': serializer.toJson<String>(syncStatus),
      'updatedAt': serializer.toJson<String>(updatedAt),
      'version': serializer.toJson<int>(version),
    };
  }

  AppPreferenceRow copyWith({
    int? id,
    String? key,
    Value<String?> value = const Value.absent(),
    String? syncStatus,
    String? updatedAt,
    int? version,
  }) => AppPreferenceRow(
    id: id ?? this.id,
    key: key ?? this.key,
    value: value.present ? value.value : this.value,
    syncStatus: syncStatus ?? this.syncStatus,
    updatedAt: updatedAt ?? this.updatedAt,
    version: version ?? this.version,
  );
  AppPreferenceRow copyWithCompanion(AppPreferencesCompanion data) {
    return AppPreferenceRow(
      id: data.id.present ? data.id.value : this.id,
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      version: data.version.present ? data.version.value : this.version,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppPreferenceRow(')
          ..write('id: $id, ')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('version: $version')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, key, value, syncStatus, updatedAt, version);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppPreferenceRow &&
          other.id == this.id &&
          other.key == this.key &&
          other.value == this.value &&
          other.syncStatus == this.syncStatus &&
          other.updatedAt == this.updatedAt &&
          other.version == this.version);
}

class AppPreferencesCompanion extends UpdateCompanion<AppPreferenceRow> {
  final Value<int> id;
  final Value<String> key;
  final Value<String?> value;
  final Value<String> syncStatus;
  final Value<String> updatedAt;
  final Value<int> version;
  const AppPreferencesCompanion({
    this.id = const Value.absent(),
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.version = const Value.absent(),
  });
  AppPreferencesCompanion.insert({
    this.id = const Value.absent(),
    required String key,
    this.value = const Value.absent(),
    this.syncStatus = const Value.absent(),
    required String updatedAt,
    this.version = const Value.absent(),
  }) : key = Value(key),
       updatedAt = Value(updatedAt);
  static Insertable<AppPreferenceRow> custom({
    Expression<int>? id,
    Expression<String>? key,
    Expression<String>? value,
    Expression<String>? syncStatus,
    Expression<String>? updatedAt,
    Expression<int>? version,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (version != null) 'version': version,
    });
  }

  AppPreferencesCompanion copyWith({
    Value<int>? id,
    Value<String>? key,
    Value<String?>? value,
    Value<String>? syncStatus,
    Value<String>? updatedAt,
    Value<int>? version,
  }) {
    return AppPreferencesCompanion(
      id: id ?? this.id,
      key: key ?? this.key,
      value: value ?? this.value,
      syncStatus: syncStatus ?? this.syncStatus,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppPreferencesCompanion(')
          ..write('id: $id, ')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('version: $version')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CarsTable cars = $CarsTable(this);
  late final $VehicleDefaultMaintenanceItemsTable
  vehicleDefaultMaintenanceItems = $VehicleDefaultMaintenanceItemsTable(this);
  late final $VehicleModelsTable vehicleModels = $VehicleModelsTable(this);
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
    vehicleDefaultMaintenanceItems,
    vehicleModels,
    maintenanceItems,
    maintenanceRecords,
    maintenanceRecordItems,
    appPreferences,
  ];
}

typedef $$CarsTableCreateCompanionBuilder =
    CarsCompanion Function({
      Value<int> id,
      required String brand,
      required String model,
      required int currentMileageKm,
      required String roadDate,
      Value<String> syncStatus,
      required String updatedAt,
      Value<int> version,
    });
typedef $$CarsTableUpdateCompanionBuilder =
    CarsCompanion Function({
      Value<int> id,
      Value<String> brand,
      Value<String> model,
      Value<int> currentMileageKm,
      Value<String> roadDate,
      Value<String> syncStatus,
      Value<String> updatedAt,
      Value<int> version,
    });

class $$CarsTableFilterComposer extends Composer<_$AppDatabase, $CarsTable> {
  $$CarsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
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

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
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
  ColumnOrderings<int> get id => $composableBuilder(
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

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
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
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get brand =>
      $composableBuilder(column: $table.brand, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

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

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

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
                Value<int> id = const Value.absent(),
                Value<String> brand = const Value.absent(),
                Value<String> model = const Value.absent(),
                Value<int> currentMileageKm = const Value.absent(),
                Value<String> roadDate = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
              }) => CarsCompanion(
                id: id,
                brand: brand,
                model: model,
                currentMileageKm: currentMileageKm,
                roadDate: roadDate,
                syncStatus: syncStatus,
                updatedAt: updatedAt,
                version: version,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String brand,
                required String model,
                required int currentMileageKm,
                required String roadDate,
                Value<String> syncStatus = const Value.absent(),
                required String updatedAt,
                Value<int> version = const Value.absent(),
              }) => CarsCompanion.insert(
                id: id,
                brand: brand,
                model: model,
                currentMileageKm: currentMileageKm,
                roadDate: roadDate,
                syncStatus: syncStatus,
                updatedAt: updatedAt,
                version: version,
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
typedef $$VehicleDefaultMaintenanceItemsTableCreateCompanionBuilder =
    VehicleDefaultMaintenanceItemsCompanion Function({
      Value<int> id,
      required String vehicleBrand,
      required String vehicleModel,
      required String itemName,
      required bool remindByMileage,
      required bool remindByTime,
      Value<int?> mileageIntervalKm,
      Value<int?> timeIntervalMonths,
      Value<double> notOverdueUpperLimit,
      Value<double> overdueUpperLimit,
      required int sortOrder,
      Value<String> syncStatus,
      required String updatedAt,
      Value<int> version,
    });
typedef $$VehicleDefaultMaintenanceItemsTableUpdateCompanionBuilder =
    VehicleDefaultMaintenanceItemsCompanion Function({
      Value<int> id,
      Value<String> vehicleBrand,
      Value<String> vehicleModel,
      Value<String> itemName,
      Value<bool> remindByMileage,
      Value<bool> remindByTime,
      Value<int?> mileageIntervalKm,
      Value<int?> timeIntervalMonths,
      Value<double> notOverdueUpperLimit,
      Value<double> overdueUpperLimit,
      Value<int> sortOrder,
      Value<String> syncStatus,
      Value<String> updatedAt,
      Value<int> version,
    });

class $$VehicleDefaultMaintenanceItemsTableFilterComposer
    extends Composer<_$AppDatabase, $VehicleDefaultMaintenanceItemsTable> {
  $$VehicleDefaultMaintenanceItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get vehicleBrand => $composableBuilder(
    column: $table.vehicleBrand,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get vehicleModel => $composableBuilder(
    column: $table.vehicleModel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get itemName => $composableBuilder(
    column: $table.itemName,
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

  ColumnFilters<double> get notOverdueUpperLimit => $composableBuilder(
    column: $table.notOverdueUpperLimit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get overdueUpperLimit => $composableBuilder(
    column: $table.overdueUpperLimit,
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

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );
}

class $$VehicleDefaultMaintenanceItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $VehicleDefaultMaintenanceItemsTable> {
  $$VehicleDefaultMaintenanceItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get vehicleBrand => $composableBuilder(
    column: $table.vehicleBrand,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get vehicleModel => $composableBuilder(
    column: $table.vehicleModel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get itemName => $composableBuilder(
    column: $table.itemName,
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

  ColumnOrderings<double> get notOverdueUpperLimit => $composableBuilder(
    column: $table.notOverdueUpperLimit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get overdueUpperLimit => $composableBuilder(
    column: $table.overdueUpperLimit,
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

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VehicleDefaultMaintenanceItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $VehicleDefaultMaintenanceItemsTable> {
  $$VehicleDefaultMaintenanceItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get vehicleBrand => $composableBuilder(
    column: $table.vehicleBrand,
    builder: (column) => column,
  );

  GeneratedColumn<String> get vehicleModel => $composableBuilder(
    column: $table.vehicleModel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get itemName =>
      $composableBuilder(column: $table.itemName, builder: (column) => column);

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

  GeneratedColumn<double> get notOverdueUpperLimit => $composableBuilder(
    column: $table.notOverdueUpperLimit,
    builder: (column) => column,
  );

  GeneratedColumn<double> get overdueUpperLimit => $composableBuilder(
    column: $table.overdueUpperLimit,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);
}

class $$VehicleDefaultMaintenanceItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $VehicleDefaultMaintenanceItemsTable,
          VehicleDefaultMaintenanceItemRow,
          $$VehicleDefaultMaintenanceItemsTableFilterComposer,
          $$VehicleDefaultMaintenanceItemsTableOrderingComposer,
          $$VehicleDefaultMaintenanceItemsTableAnnotationComposer,
          $$VehicleDefaultMaintenanceItemsTableCreateCompanionBuilder,
          $$VehicleDefaultMaintenanceItemsTableUpdateCompanionBuilder,
          (
            VehicleDefaultMaintenanceItemRow,
            BaseReferences<
              _$AppDatabase,
              $VehicleDefaultMaintenanceItemsTable,
              VehicleDefaultMaintenanceItemRow
            >,
          ),
          VehicleDefaultMaintenanceItemRow,
          PrefetchHooks Function()
        > {
  $$VehicleDefaultMaintenanceItemsTableTableManager(
    _$AppDatabase db,
    $VehicleDefaultMaintenanceItemsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VehicleDefaultMaintenanceItemsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$VehicleDefaultMaintenanceItemsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$VehicleDefaultMaintenanceItemsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> vehicleBrand = const Value.absent(),
                Value<String> vehicleModel = const Value.absent(),
                Value<String> itemName = const Value.absent(),
                Value<bool> remindByMileage = const Value.absent(),
                Value<bool> remindByTime = const Value.absent(),
                Value<int?> mileageIntervalKm = const Value.absent(),
                Value<int?> timeIntervalMonths = const Value.absent(),
                Value<double> notOverdueUpperLimit = const Value.absent(),
                Value<double> overdueUpperLimit = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
              }) => VehicleDefaultMaintenanceItemsCompanion(
                id: id,
                vehicleBrand: vehicleBrand,
                vehicleModel: vehicleModel,
                itemName: itemName,
                remindByMileage: remindByMileage,
                remindByTime: remindByTime,
                mileageIntervalKm: mileageIntervalKm,
                timeIntervalMonths: timeIntervalMonths,
                notOverdueUpperLimit: notOverdueUpperLimit,
                overdueUpperLimit: overdueUpperLimit,
                sortOrder: sortOrder,
                syncStatus: syncStatus,
                updatedAt: updatedAt,
                version: version,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String vehicleBrand,
                required String vehicleModel,
                required String itemName,
                required bool remindByMileage,
                required bool remindByTime,
                Value<int?> mileageIntervalKm = const Value.absent(),
                Value<int?> timeIntervalMonths = const Value.absent(),
                Value<double> notOverdueUpperLimit = const Value.absent(),
                Value<double> overdueUpperLimit = const Value.absent(),
                required int sortOrder,
                Value<String> syncStatus = const Value.absent(),
                required String updatedAt,
                Value<int> version = const Value.absent(),
              }) => VehicleDefaultMaintenanceItemsCompanion.insert(
                id: id,
                vehicleBrand: vehicleBrand,
                vehicleModel: vehicleModel,
                itemName: itemName,
                remindByMileage: remindByMileage,
                remindByTime: remindByTime,
                mileageIntervalKm: mileageIntervalKm,
                timeIntervalMonths: timeIntervalMonths,
                notOverdueUpperLimit: notOverdueUpperLimit,
                overdueUpperLimit: overdueUpperLimit,
                sortOrder: sortOrder,
                syncStatus: syncStatus,
                updatedAt: updatedAt,
                version: version,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$VehicleDefaultMaintenanceItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $VehicleDefaultMaintenanceItemsTable,
      VehicleDefaultMaintenanceItemRow,
      $$VehicleDefaultMaintenanceItemsTableFilterComposer,
      $$VehicleDefaultMaintenanceItemsTableOrderingComposer,
      $$VehicleDefaultMaintenanceItemsTableAnnotationComposer,
      $$VehicleDefaultMaintenanceItemsTableCreateCompanionBuilder,
      $$VehicleDefaultMaintenanceItemsTableUpdateCompanionBuilder,
      (
        VehicleDefaultMaintenanceItemRow,
        BaseReferences<
          _$AppDatabase,
          $VehicleDefaultMaintenanceItemsTable,
          VehicleDefaultMaintenanceItemRow
        >,
      ),
      VehicleDefaultMaintenanceItemRow,
      PrefetchHooks Function()
    >;
typedef $$VehicleModelsTableCreateCompanionBuilder =
    VehicleModelsCompanion Function({
      Value<int> id,
      required String brand,
      required String model,
      required int sortOrder,
      Value<String> syncStatus,
      required String updatedAt,
      Value<int> version,
    });
typedef $$VehicleModelsTableUpdateCompanionBuilder =
    VehicleModelsCompanion Function({
      Value<int> id,
      Value<String> brand,
      Value<String> model,
      Value<int> sortOrder,
      Value<String> syncStatus,
      Value<String> updatedAt,
      Value<int> version,
    });

class $$VehicleModelsTableFilterComposer
    extends Composer<_$AppDatabase, $VehicleModelsTable> {
  $$VehicleModelsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
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

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );
}

class $$VehicleModelsTableOrderingComposer
    extends Composer<_$AppDatabase, $VehicleModelsTable> {
  $$VehicleModelsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
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

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VehicleModelsTableAnnotationComposer
    extends Composer<_$AppDatabase, $VehicleModelsTable> {
  $$VehicleModelsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get brand =>
      $composableBuilder(column: $table.brand, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);
}

class $$VehicleModelsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $VehicleModelsTable,
          VehicleModelRow,
          $$VehicleModelsTableFilterComposer,
          $$VehicleModelsTableOrderingComposer,
          $$VehicleModelsTableAnnotationComposer,
          $$VehicleModelsTableCreateCompanionBuilder,
          $$VehicleModelsTableUpdateCompanionBuilder,
          (
            VehicleModelRow,
            BaseReferences<_$AppDatabase, $VehicleModelsTable, VehicleModelRow>,
          ),
          VehicleModelRow,
          PrefetchHooks Function()
        > {
  $$VehicleModelsTableTableManager(_$AppDatabase db, $VehicleModelsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VehicleModelsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VehicleModelsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VehicleModelsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> brand = const Value.absent(),
                Value<String> model = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
              }) => VehicleModelsCompanion(
                id: id,
                brand: brand,
                model: model,
                sortOrder: sortOrder,
                syncStatus: syncStatus,
                updatedAt: updatedAt,
                version: version,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String brand,
                required String model,
                required int sortOrder,
                Value<String> syncStatus = const Value.absent(),
                required String updatedAt,
                Value<int> version = const Value.absent(),
              }) => VehicleModelsCompanion.insert(
                id: id,
                brand: brand,
                model: model,
                sortOrder: sortOrder,
                syncStatus: syncStatus,
                updatedAt: updatedAt,
                version: version,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$VehicleModelsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $VehicleModelsTable,
      VehicleModelRow,
      $$VehicleModelsTableFilterComposer,
      $$VehicleModelsTableOrderingComposer,
      $$VehicleModelsTableAnnotationComposer,
      $$VehicleModelsTableCreateCompanionBuilder,
      $$VehicleModelsTableUpdateCompanionBuilder,
      (
        VehicleModelRow,
        BaseReferences<_$AppDatabase, $VehicleModelsTable, VehicleModelRow>,
      ),
      VehicleModelRow,
      PrefetchHooks Function()
    >;
typedef $$MaintenanceItemsTableCreateCompanionBuilder =
    MaintenanceItemsCompanion Function({
      Value<int> id,
      required int carsId,
      required String name,
      required bool isDefault,
      Value<bool> enabled,
      required bool remindByMileage,
      required bool remindByTime,
      Value<int?> mileageIntervalKm,
      Value<int?> timeIntervalMonths,
      Value<double> notOverdueUpperLimit,
      Value<double> overdueUpperLimit,
      required int sortOrder,
      Value<String> syncStatus,
      required String updatedAt,
      Value<int> version,
    });
typedef $$MaintenanceItemsTableUpdateCompanionBuilder =
    MaintenanceItemsCompanion Function({
      Value<int> id,
      Value<int> carsId,
      Value<String> name,
      Value<bool> isDefault,
      Value<bool> enabled,
      Value<bool> remindByMileage,
      Value<bool> remindByTime,
      Value<int?> mileageIntervalKm,
      Value<int?> timeIntervalMonths,
      Value<double> notOverdueUpperLimit,
      Value<double> overdueUpperLimit,
      Value<int> sortOrder,
      Value<String> syncStatus,
      Value<String> updatedAt,
      Value<int> version,
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
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get carsId => $composableBuilder(
    column: $table.carsId,
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

  ColumnFilters<double> get notOverdueUpperLimit => $composableBuilder(
    column: $table.notOverdueUpperLimit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get overdueUpperLimit => $composableBuilder(
    column: $table.overdueUpperLimit,
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

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
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
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get carsId => $composableBuilder(
    column: $table.carsId,
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

  ColumnOrderings<double> get notOverdueUpperLimit => $composableBuilder(
    column: $table.notOverdueUpperLimit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get overdueUpperLimit => $composableBuilder(
    column: $table.overdueUpperLimit,
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

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
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
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get carsId =>
      $composableBuilder(column: $table.carsId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<bool> get isDefault =>
      $composableBuilder(column: $table.isDefault, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

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

  GeneratedColumn<double> get notOverdueUpperLimit => $composableBuilder(
    column: $table.notOverdueUpperLimit,
    builder: (column) => column,
  );

  GeneratedColumn<double> get overdueUpperLimit => $composableBuilder(
    column: $table.overdueUpperLimit,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

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
                Value<int> id = const Value.absent(),
                Value<int> carsId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<bool> isDefault = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<bool> remindByMileage = const Value.absent(),
                Value<bool> remindByTime = const Value.absent(),
                Value<int?> mileageIntervalKm = const Value.absent(),
                Value<int?> timeIntervalMonths = const Value.absent(),
                Value<double> notOverdueUpperLimit = const Value.absent(),
                Value<double> overdueUpperLimit = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
              }) => MaintenanceItemsCompanion(
                id: id,
                carsId: carsId,
                name: name,
                isDefault: isDefault,
                enabled: enabled,
                remindByMileage: remindByMileage,
                remindByTime: remindByTime,
                mileageIntervalKm: mileageIntervalKm,
                timeIntervalMonths: timeIntervalMonths,
                notOverdueUpperLimit: notOverdueUpperLimit,
                overdueUpperLimit: overdueUpperLimit,
                sortOrder: sortOrder,
                syncStatus: syncStatus,
                updatedAt: updatedAt,
                version: version,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int carsId,
                required String name,
                required bool isDefault,
                Value<bool> enabled = const Value.absent(),
                required bool remindByMileage,
                required bool remindByTime,
                Value<int?> mileageIntervalKm = const Value.absent(),
                Value<int?> timeIntervalMonths = const Value.absent(),
                Value<double> notOverdueUpperLimit = const Value.absent(),
                Value<double> overdueUpperLimit = const Value.absent(),
                required int sortOrder,
                Value<String> syncStatus = const Value.absent(),
                required String updatedAt,
                Value<int> version = const Value.absent(),
              }) => MaintenanceItemsCompanion.insert(
                id: id,
                carsId: carsId,
                name: name,
                isDefault: isDefault,
                enabled: enabled,
                remindByMileage: remindByMileage,
                remindByTime: remindByTime,
                mileageIntervalKm: mileageIntervalKm,
                timeIntervalMonths: timeIntervalMonths,
                notOverdueUpperLimit: notOverdueUpperLimit,
                overdueUpperLimit: overdueUpperLimit,
                sortOrder: sortOrder,
                syncStatus: syncStatus,
                updatedAt: updatedAt,
                version: version,
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
      Value<int> id,
      required int carId,
      required String date,
      required int mileageKm,
      required int costCents,
      Value<String?> note,
      Value<String> syncStatus,
      required String updatedAt,
      Value<int> version,
    });
typedef $$MaintenanceRecordsTableUpdateCompanionBuilder =
    MaintenanceRecordsCompanion Function({
      Value<int> id,
      Value<int> carId,
      Value<String> date,
      Value<int> mileageKm,
      Value<int> costCents,
      Value<String?> note,
      Value<String> syncStatus,
      Value<String> updatedAt,
      Value<int> version,
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
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get carId => $composableBuilder(
    column: $table.carId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
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

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
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
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get carId => $composableBuilder(
    column: $table.carId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
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

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
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
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get carId =>
      $composableBuilder(column: $table.carId, builder: (column) => column);

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

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

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

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
                Value<int> id = const Value.absent(),
                Value<int> carId = const Value.absent(),
                Value<String> date = const Value.absent(),
                Value<int> mileageKm = const Value.absent(),
                Value<int> costCents = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
              }) => MaintenanceRecordsCompanion(
                id: id,
                carId: carId,
                date: date,
                mileageKm: mileageKm,
                costCents: costCents,
                note: note,
                syncStatus: syncStatus,
                updatedAt: updatedAt,
                version: version,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int carId,
                required String date,
                required int mileageKm,
                required int costCents,
                Value<String?> note = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                required String updatedAt,
                Value<int> version = const Value.absent(),
              }) => MaintenanceRecordsCompanion.insert(
                id: id,
                carId: carId,
                date: date,
                mileageKm: mileageKm,
                costCents: costCents,
                note: note,
                syncStatus: syncStatus,
                updatedAt: updatedAt,
                version: version,
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
      Value<int> id,
      required int maintenanceRecordId,
      required int carId,
      required int itemId,
      required String date,
    });
typedef $$MaintenanceRecordItemsTableUpdateCompanionBuilder =
    MaintenanceRecordItemsCompanion Function({
      Value<int> id,
      Value<int> maintenanceRecordId,
      Value<int> carId,
      Value<int> itemId,
      Value<String> date,
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
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maintenanceRecordId => $composableBuilder(
    column: $table.maintenanceRecordId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get carId => $composableBuilder(
    column: $table.carId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
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
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maintenanceRecordId => $composableBuilder(
    column: $table.maintenanceRecordId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get carId => $composableBuilder(
    column: $table.carId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
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
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get maintenanceRecordId => $composableBuilder(
    column: $table.maintenanceRecordId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get carId =>
      $composableBuilder(column: $table.carId, builder: (column) => column);

  GeneratedColumn<int> get itemId =>
      $composableBuilder(column: $table.itemId, builder: (column) => column);

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);
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
                Value<int> id = const Value.absent(),
                Value<int> maintenanceRecordId = const Value.absent(),
                Value<int> carId = const Value.absent(),
                Value<int> itemId = const Value.absent(),
                Value<String> date = const Value.absent(),
              }) => MaintenanceRecordItemsCompanion(
                id: id,
                maintenanceRecordId: maintenanceRecordId,
                carId: carId,
                itemId: itemId,
                date: date,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int maintenanceRecordId,
                required int carId,
                required int itemId,
                required String date,
              }) => MaintenanceRecordItemsCompanion.insert(
                id: id,
                maintenanceRecordId: maintenanceRecordId,
                carId: carId,
                itemId: itemId,
                date: date,
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
      Value<int> id,
      required String key,
      Value<String?> value,
      Value<String> syncStatus,
      required String updatedAt,
      Value<int> version,
    });
typedef $$AppPreferencesTableUpdateCompanionBuilder =
    AppPreferencesCompanion Function({
      Value<int> id,
      Value<String> key,
      Value<String?> value,
      Value<String> syncStatus,
      Value<String> updatedAt,
      Value<int> version,
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
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
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
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
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
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);
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
                Value<int> id = const Value.absent(),
                Value<String> key = const Value.absent(),
                Value<String?> value = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
              }) => AppPreferencesCompanion(
                id: id,
                key: key,
                value: value,
                syncStatus: syncStatus,
                updatedAt: updatedAt,
                version: version,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String key,
                Value<String?> value = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                required String updatedAt,
                Value<int> version = const Value.absent(),
              }) => AppPreferencesCompanion.insert(
                id: id,
                key: key,
                value: value,
                syncStatus: syncStatus,
                updatedAt: updatedAt,
                version: version,
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
  $$VehicleDefaultMaintenanceItemsTableTableManager
  get vehicleDefaultMaintenanceItems =>
      $$VehicleDefaultMaintenanceItemsTableTableManager(
        _db,
        _db.vehicleDefaultMaintenanceItems,
      );
  $$VehicleModelsTableTableManager get vehicleModels =>
      $$VehicleModelsTableTableManager(_db, _db.vehicleModels);
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
