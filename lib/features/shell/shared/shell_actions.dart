import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../domain/entities/car.dart';
import 'modal_feedback.dart';

int notificationSyncGeneration = 0;

Future<void> applyCar(BuildContext context, WidgetRef ref, int carId) async {
  await ref.read(lunioRepositoryProvider).setAppliedCarId(carId);
  invalidateVehicleProviders(ref);
}

Future<void> setThemeModePreference(
  BuildContext context,
  WidgetRef ref,
  ThemeMode mode,
) async {
  final value = switch (mode) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
  };
  await ref
      .read(lunioRepositoryProvider)
      .setPreferenceValue('themeMode', value);
  invalidatePreferenceProviders(ref);
}

Future<void> deleteCar(BuildContext context, WidgetRef ref, Car car) async {
  final confirmed = await showConfirmDialog(
    context: context,
    title: '删除车辆',
    message: '确定删除 ${car.brand} ${car.model}？相关项目和记录会同步删除。',
    confirmLabel: '删除',
  );
  if (confirmed != true || car.id == null) {
    return;
  }
  await ref.read(lunioRepositoryProvider).deleteCar(car.id!);
  invalidateVehicleProviders(ref);
}
