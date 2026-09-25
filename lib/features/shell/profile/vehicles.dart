// 车辆管理：车辆列表/卡片、切换应用车辆、添加/编辑车辆 sheet 入口。
//
// 在 App 中的位置：profile 域，被我的页（列表/添加/编辑）和提醒页
// （切换车辆、空卡片新增）使用。职责分界：
//   - 添加车辆两步向导（第一步表单 + 草稿状态机控制器）在
//     add_car_wizard.dart，第二步的项目草稿列表组件在 maintenance_items.dart；
//   - 车型目录选择器在 vehicle_model_picker.dart；
//   - 本文件保留 sheet 入口（数据装载守卫 + 提交给动作层的接线）与
//     车辆展示组件（列表卡/自绘小汽车/空卡片/切换卡）。
//
// 编辑车辆（showEditCarSheet）：品牌车型与动力类型锁定（身份字段不可改），
// 只改里程、上路日期和油箱容积。⚠ 里程可任意改小，无回退校验（R36）。
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/date/local_date.dart';
import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';
import '../../../domain/entities/car.dart';
import '../../../domain/entities/sync_metadata.dart';
import '../../../domain/entities/vehicle_model.dart';
import '../shared/shell_shared.dart';
import 'add_car_wizard.dart';

/// 我的页车辆列表：空列表显示 EmptyVehicleCard；否则逐车渲染卡片
/// （当前应用车辆高亮 + "当前"徽章），操作按钮：应用/编辑/项目/删除。
class VehicleList extends StatelessWidget {
  const VehicleList({
    required this.cars,
    required this.appliedCarId,
    required this.today,
    required this.onAdd,
    required this.onEdit,
    required this.onManageItems,
    required this.onApply,
    required this.onDelete,
  });

  final List<Car> cars;
  final int? appliedCarId;
  final LocalDate today;
  final VoidCallback onAdd;
  final ValueChanged<Car> onEdit;
  final ValueChanged<Car> onManageItems;
  final ValueChanged<int> onApply;
  final ValueChanged<Car> onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    if (cars.isEmpty) {
      return EmptyVehicleCard(onAdd: onAdd);
    }
    return Column(
      children: [
        for (final car in cars) ...[
          Builder(
            builder: (context) {
              final selected = car.id == appliedCarId;
              return LunioCard(
                backgroundColor: selected ? tokens.primarySoft : null,
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${car.brand} ${car.model}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                  ),
                                  if (selected)
                                    const LunioStatusBadge(
                                      label: '当前',
                                      tone: LunioStatusTone.normal,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${formatMileageKm(car.currentMileageKm)} · ${car.roadDate} · ${formatCarAge(car.roadDate, today)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        CarVisual(selected: selected),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        SmallActionButton(
                          label: selected ? '已应用' : '应用',
                          onPressed: car.id == null
                              ? null
                              : selected
                              ? null
                              : () => onApply(car.id!),
                        ),
                        const SizedBox(width: 8),
                        SmallActionButton(
                          label: '编辑',
                          onPressed: () => onEdit(car),
                        ),
                        const SizedBox(width: 8),
                        SmallActionButton(
                          label: '项目',
                          onPressed: () => onManageItems(car),
                        ),
                        const SizedBox(width: 8),
                        SmallActionButton(
                          label: '删除',
                          danger: true,
                          onPressed: () => onDelete(car),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// 自绘小汽车插画（Canvas 画的车身/车窗/车轮）。
class CarVisual extends StatelessWidget {
  const CarVisual({this.selected = false});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return CustomPaint(
      size: const Size(70, 38),
      painter: CarVisualPainter(
        bodyStart: tokens.primary,
        bodyEnd: tokens.primaryStrong,
        windowColor: selected ? tokens.surface : tokens.primarySoft,
        wheelColor: tokens.ink,
      ),
    );
  }
}

/// 小汽车画笔（渐变车身 + 车窗 + 两个车轮）。
class CarVisualPainter extends CustomPainter {
  const CarVisualPainter({
    required this.bodyStart,
    required this.bodyEnd,
    required this.windowColor,
    required this.wheelColor,
  });

  final Color bodyStart;
  final Color bodyEnd;
  final Color windowColor;
  final Color wheelColor;

  @override
  void paint(Canvas canvas, Size size) {
    final bodyPaint = Paint()
      ..shader = LinearGradient(
        colors: [bodyStart, bodyEnd],
      ).createShader(Offset.zero & size);
    final windowPaint = Paint()..color = windowColor;
    final wheelPaint = Paint()..color = wheelColor;
    final body = RRect.fromRectAndCorners(
      Rect.fromLTWH(5, 12, 60, 18),
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(22),
      bottomLeft: const Radius.circular(10),
      bottomRight: const Radius.circular(10),
    );
    final window = RRect.fromRectAndCorners(
      Rect.fromLTWH(18, 7, 32, 18),
      topLeft: const Radius.circular(20),
      topRight: const Radius.circular(20),
      bottomLeft: const Radius.circular(6),
      bottomRight: const Radius.circular(6),
    );
    canvas
      ..drawRRect(body, bodyPaint)
      ..drawRRect(window, windowPaint)
      ..drawCircle(const Offset(18, 32), 5, wheelPaint)
      ..drawCircle(const Offset(57, 32), 5, wheelPaint);
  }

  @override
  bool shouldRepaint(CarVisualPainter oldDelegate) {
    return bodyStart != oldDelegate.bodyStart ||
        bodyEnd != oldDelegate.bodyEnd ||
        windowColor != oldDelegate.windowColor ||
        wheelColor != oldDelegate.wheelColor;
  }
}

/// 无车空卡片（"还没有车辆" + 新增按钮），提醒页和我的页共用。
class EmptyVehicleCard extends StatelessWidget {
  const EmptyVehicleCard({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return LunioCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('还没有车辆', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 14),
          Tooltip(
            message: '新增车辆',
            child: LunioPrimaryButton(label: '新增车辆', onPressed: onAdd),
          ),
        ],
      ),
    );
  }
}

/// ★ 添加车辆 sheet 入口（我的页"添加"/空卡片"新增车辆"/提醒页空卡片）。
/// 装载/守卫/头部/键盘 inset/pop/toast 时序归 showLunioFormSheet
/// （ADR 0016；原"sheet 先开、目录在 frame 内 watch"的装载改为统一
/// 预装载——目录是缓存 provider，等待很短）：装载车型目录与生效今天 →
/// 目录为空 toast 拦截 → 弹两步向导。
/// 两步换 sheet 标题经 handle.setFrame（onMaintenanceStepChanged 接线）；
/// 向导提交 → createCarWithMaintenanceItems（事务：车+项目+首车设应用
/// 车辆）→ invalidateVehicleProviders（动作层）。
void showAddCarSheet(BuildContext context, WidgetRef ref) {
  List<VehicleModel> vehicleModels = const [];
  LocalDate today = LocalDate.fromDateTime(DateTime.now());
  showLunioFormSheet<void>(
    context: context,
    title: '添加车辆',
    load: (handle) async {
      vehicleModels = await ref.read(vehicleModelsProvider.future);
      today = await ref.read(effectiveTodayProvider.future);
    },
    guard: () => vehicleModels.isEmpty ? '暂无可选车型' : null,
    builder: (sheetContext, handle) {
      return AddCarWizard(
        vehicleModels: vehicleModels,
        today: today,
        handle: handle,
        // 两步换 sheet 标题：离开第一步显示"保养项目"（ADR 0016 的
        // setFrame，替代原先 StatefulBuilder 手搓的标题切换）。
        onMaintenanceStepChanged: (onMaintenanceStep) {
          handle.setFrame(
            title: onMaintenanceStep ? '保养项目' : '添加车辆',
            subtitle: onMaintenanceStep
                ? '以下保养项目只做参考，具体以官方保养手册为准'
                : null,
          );
        },
        // 写库+失效收进动作层（ADR 0007）；关 sheet 与成功 toast 归
        // 表单运行时（ADR 0016）。
        onSubmit: (car, items) => createCar(ref, car, items),
      );
    },
    successMessage: '车辆已保存',
  );
}

/// ★ 编辑车辆 sheet：AddCarForm 编辑模式（品牌车型只读）→
/// updateCar（写里程/日期/容积）→ invalidate（动作层）。
/// 车型目录为空时兜底用当前车拼一个假选项（只是为了让表单不炸）。
void showEditCarSheet(BuildContext context, WidgetRef ref, Car car) {
  List<VehicleModel> vehicleModels = const [];
  LocalDate today = LocalDate.fromDateTime(DateTime.now());
  showLunioFormSheet<void>(
    context: context,
    title: '编辑车辆',
    subtitle: '品牌车型保持稳定，可更新当前里程、上路日期和油箱容积',
    load: (handle) async {
      vehicleModels = await ref.read(vehicleModelsProvider.future);
      today = await ref.read(effectiveTodayProvider.future);
    },
    builder: (sheetContext, handle) {
      return AddCarForm(
        vehicleModels: vehicleModels.isEmpty
            ? [
                // 目录为空时兜底用当前车拼一个假选项（表单不炸）；
                // 推荐动力类型用当前车自己的。
                VehicleModel(
                  brand: car.brand,
                  model: car.model,
                  template: car.powertrainType,
                  sortOrder: 0,
                  sync: SyncMetadata(
                    status: SyncStatus.synced,
                    updatedAt: DateTime.now(),
                  ),
                ),
              ]
            : vehicleModels,
        today: today,
        initialCar: car,
        handle: handle,
        closeOnSubmit: true,
        // 写库+失效收进动作层（ADR 0007）；关 sheet 与成功 toast 归
        // 表单运行时（ADR 0016）。
        onSubmit: (updatedCar) => updateCar(ref, updatedCar),
      );
    },
    successMessage: '车辆已保存',
  );
}

/// ★ 提醒页右上角"切换车辆"sheet：列出全部车，点非当前车 →
/// applyCar（写偏好 + invalidate）→ 关 sheet。
/// 切换应用车辆 sheet（提醒页右上角入口）。
/// 先 await 车辆列表与应用车辆（R23：loading 期 read 会拿到空列表，
/// 误报"请先新增车辆"）；加载失败 toast 返回；单辆车提示后返回。
/// 弹出后的选中卡片点击 → applyCar 写偏好 → 关 sheet。
Future<void> showVehicleSwitcher(BuildContext context, WidgetRef ref) async {
  final List<Car> cars;
  final int? appliedCarId;
  try {
    cars = await ref.read(carsProvider.future);
    appliedCarId = (await ref.read(appliedCarProvider.future))?.id;
  } catch (_) {
    if (context.mounted) {
      showStatusOverlay(context, '车辆加载失败', StatusOverlayTone.error);
    }
    return;
  }
  if (!context.mounted) {
    return;
  }
  if (cars.length <= 1) {
    showStatusOverlay(
      context,
      cars.isEmpty ? '请先新增车辆' : '当前只有一辆车',
      StatusOverlayTone.info,
    );
    return;
  }
  showLunioModalSheet<void>(
    context: context,
    builder: (sheetContext) {
      return PrototypeSheetFrame(
        title: '选择应用车辆',
        subtitle: '提醒、记录和新增保养记录会跟随当前车辆',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final car in cars) ...[
              SwitchCarCard(
                car: car,
                selected: car.id == appliedCarId,
                onTap: car.id == null
                    ? null
                    : () async {
                        await applyCar(ref, car.id!);
                        if (sheetContext.mounted) {
                          Navigator.of(sheetContext).pop();
                        }
                      },
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      );
    },
  );
}

/// 切换 sheet 里的单辆车卡片（当前车高亮不可点）。
class SwitchCarCard extends StatelessWidget {
  const SwitchCarCard({
    required this.car,
    required this.selected,
    required this.onTap,
  });

  final Car car;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Material(
      color: selected ? tokens.primarySoft : tokens.surface,
      borderRadius: BorderRadius.circular(tokens.radiusLarge),
      child: InkWell(
        onTap: selected ? null : onTap,
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(tokens.radiusLarge),
            border: Border.all(color: selected ? tokens.primary : tokens.line),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${car.brand} ${car.model}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${formatNumber(car.currentMileageKm)} km · ${car.roadDate} · ${selected ? "当前应用" : "点击切换"}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const CarVisual(),
            ],
          ),
        ),
      ),
    );
  }
}
