// 保养项目管理：添加车辆向导第二步 + 已保存车辆的项目管理 sheet +
// 项目表单/启停/删除动作。
//
// 两处使用场景：
//  1. AddCarMaintenanceItemsStep：向导草稿模式（纯内存列表，未落库，
//     编辑走 showDraftMaintenanceItemFormSheet，仅替换内存草稿）；
//  2. showMaintenanceItemsSheet：已保存车辆的项目 sheet（自管加载状态，
//     编辑/启停/删除直接写库后 invalidate + 内部重载）。
//
// 业务约束（UI 侧前置拦截，Repository 侧兜底）：
// 至少保留一个启用项目；有历史记录的项目不能删除。
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';
import '../../../domain/entities/car.dart';
import '../../../domain/entities/maintenance_item.dart';
import '../../../domain/entities/sync_metadata.dart';
import '../../../domain/entities/vehicle_default_maintenance_item.dart';
import '../shared/shell_shared.dart';

/// 向导第二步：车型 pill + 新增/恢复按钮 + 项目列表（限高滚动）+
/// 上一步/保存车辆。所有修改通过 onChanged 回调交给向导 State。
class AddCarMaintenanceItemsStep extends StatelessWidget {
  const AddCarMaintenanceItemsStep({
    required this.car,
    required this.items,
    required this.saving,
    required this.errorText,
    required this.onBack,
    required this.onChanged,
    required this.onAdd,
    required this.onRestoreDefaults,
    required this.onSubmit,
  });

  final Car car;
  final List<MaintenanceItem> items;
  final bool saving;
  final String? errorText;
  final VoidCallback? onBack;
  final ValueChanged<List<MaintenanceItem>> onChanged;
  final VoidCallback? onAdd;
  final VoidCallback? onRestoreDefaults;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final maxListHeight = MediaQuery.sizeOf(context).height * 0.42;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: ItemPills(labels: ['${car.brand} ${car.model}'])),
            const SizedBox(width: 12),
            SmallActionButton(label: '新增', onPressed: onAdd, primary: true),
            const SizedBox(width: 8),
            SmallActionButton(label: '恢复', onPressed: onRestoreDefaults),
          ],
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxListHeight),
          child: SingleChildScrollView(
            child: MaintenanceItemList(
              items: items,
              onEdit: saving ? (_) {} : (item) => _editItem(context, item),
              onToggle: saving ? (_) {} : _toggleItem,
              onDelete: saving ? (_) {} : _deleteItem,
            ),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 10),
          LunioInlineMessage(message: errorText!, tone: LunioStatusTone.danger),
        ],
        const SizedBox(height: 16),
        LunioFormActions(
          cancelLabel: '上一步',
          confirmLabel: '保存车辆',
          onCancel: onBack,
          onConfirm: onSubmit,
          saving: saving,
        ),
      ],
    );
  }

  /// 编辑草稿：弹草稿表单，按对象身份（identical）替换列表里的那一条。
  void _editItem(BuildContext context, MaintenanceItem item) {
    showDraftMaintenanceItemFormSheet(
      context,
      item: item,
      onSubmit: (nextItem) {
        onChanged([
          for (final current in items)
            if (identical(current, item)) nextItem else current,
        ]);
      },
    );
  }

  /// 启停草稿：停用最后一个启用项时静默拦截（按钮看起来没反应）。
  void _toggleItem(MaintenanceItem item) {
    final nextEnabled = !item.enabled;
    if (!nextEnabled &&
        items
            .where((current) => current.enabled && !identical(current, item))
            .isEmpty) {
      return;
    }
    onChanged([
      for (final current in items)
        if (identical(current, item))
          current.copyWith(enabled: nextEnabled)
        else
          current,
    ]);
  }

  /// 删除草稿：删完没有启用项时静默拦截。
  void _deleteItem(MaintenanceItem item) {
    final nextItems = items
        .where((current) => !identical(current, item))
        .toList();
    if (!nextItems.any((current) => current.enabled)) {
      return;
    }
    onChanged(nextItems);
  }
}

/// "恢复默认项目"sheet 入口：返回勾选的模板列表（取消/无选择返回 null）。
Future<List<VehicleDefaultMaintenanceItem>?> showRestoreDefaultItemsSheet(
  BuildContext context, {
  required List<VehicleDefaultMaintenanceItem> defaultItems,
  required List<MaintenanceItem> itemDrafts,
}) {
  return showLunioModalSheet<List<VehicleDefaultMaintenanceItem>>(
    context: context,
    builder: (context) {
      return PrototypeSheetFrame(
        title: '恢复默认项目',
        subtitle: '选择要补回的默认保养项目，保存车辆前只会更新当前页面配置',
        child: RestoreDefaultItemsSheet(
          defaultItems: defaultItems,
          itemDrafts: itemDrafts,
        ),
      );
    },
  );
}

/// 恢复默认 sheet 内容：全部默认项目可勾选，"草稿里已存在同名"的置灰
/// （同名不重复恢复，按 normalizeItemName 归一化比对）。
class RestoreDefaultItemsSheet extends StatefulWidget {
  const RestoreDefaultItemsSheet({
    required this.defaultItems,
    required this.itemDrafts,
  });

  final List<VehicleDefaultMaintenanceItem> defaultItems;
  final List<MaintenanceItem> itemDrafts;

  @override
  State<RestoreDefaultItemsSheet> createState() =>
      RestoreDefaultItemsSheetState();
}

class RestoreDefaultItemsSheetState extends State<RestoreDefaultItemsSheet> {
  late final Set<String> existingNames;
  late final Set<String> selectedNames;

  @override
  void initState() {
    super.initState();
    existingNames = widget.itemDrafts
        .map((item) => _normalizeItemName(item.name))
        .toSet();
    selectedNames = {
      for (final item in widget.defaultItems)
        if (!existingNames.contains(_normalizeItemName(item.itemName)))
          _normalizeItemName(item.itemName),
    };
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final recoverableCount = widget.defaultItems
        .where(
          (item) => !existingNames.contains(_normalizeItemName(item.itemName)),
        )
        .length;
    final maxListHeight = MediaQuery.sizeOf(context).height * 0.42;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxListHeight),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 下标循环：行距判断用 index 而非实体 ==（重复实体时
                // == 比较会让多个"最后一项"都丢行距，R24）。
                for (
                  var index = 0;
                  index < widget.defaultItems.length;
                  index++
                ) ...[
                  RestoreDefaultItemRow(
                    item: widget.defaultItems[index],
                    selected: selectedNames.contains(
                      _normalizeItemName(widget.defaultItems[index].itemName),
                    ),
                    enabled: !existingNames.contains(
                      _normalizeItemName(widget.defaultItems[index].itemName),
                    ),
                    onChanged: (selected) => setState(() {
                      final key = _normalizeItemName(
                        widget.defaultItems[index].itemName,
                      );
                      if (selected) {
                        selectedNames.add(key);
                      } else {
                        selectedNames.remove(key);
                      }
                    }),
                  ),
                  if (index != widget.defaultItems.length - 1)
                    const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
        if (recoverableCount == 0) ...[
          const SizedBox(height: 10),
          const LunioInlineMessage(message: '当前页面已包含全部默认项目'),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: LunioSecondaryButton(
                label: '取消',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LunioPrimaryButton(
                label: '恢复',
                onPressed: selectedNames.isEmpty
                    ? null
                    : () {
                        Navigator.of(context).pop([
                          for (final item in widget.defaultItems)
                            if (selectedNames.contains(
                              _normalizeItemName(item.itemName),
                            ))
                              item,
                        ]);
                      },
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '已存在的同名项目不会重复恢复',
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: tokens.subtle),
        ),
      ],
    );
  }
}

/// 恢复 sheet 的单行（checkbox + 项目名 + 规则文案 + "已存在"标记）。
class RestoreDefaultItemRow extends StatelessWidget {
  const RestoreDefaultItemRow({
    required this.item,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final VehicleDefaultMaintenanceItem item;
  final bool selected;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return InkWell(
      onTap: enabled ? () => onChanged(!selected) : null,
      borderRadius: BorderRadius.circular(tokens.radiusMedium),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: enabled ? tokens.surface2 : tokens.surface3,
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
          border: Border.all(color: tokens.line),
        ),
        child: Row(
          children: [
            Checkbox(
              value: enabled ? selected : false,
              onChanged: enabled ? (value) => onChanged(value ?? false) : null,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.itemName,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: enabled ? tokens.ink : tokens.muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _itemRuleText(
                      remindByMileage: item.remindByMileage,
                      remindByTime: item.remindByTime,
                      mileageIntervalKm: item.mileageIntervalKm,
                      timeIntervalMonths: item.timeIntervalMonths,
                    ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: enabled ? tokens.muted : tokens.subtle,
                    ),
                  ),
                ],
              ),
            ),
            if (!enabled)
              Text(
                '已存在',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tokens.subtle,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// ★ 项目管理 sheet 入口（车辆卡"项目"按钮）。car 为空时管当前应用车辆。
void showMaintenanceItemsSheet(
  BuildContext context,
  WidgetRef ref, {
  Car? car,
}) {
  showLunioModalSheet<void>(
    context: context,
    builder: (context) => MaintenanceItemsSheetRoute(car: car),
  );
}

/// sheet 路由壳：持有 refreshListenable（ValueNotifier≈可监听的信号量），
/// 内部子表单保存成功后 value+1 通知本层重载列表。
class MaintenanceItemsSheetRoute extends StatefulWidget {
  const MaintenanceItemsSheetRoute({required this.car});

  final Car? car;

  @override
  State<MaintenanceItemsSheetRoute> createState() =>
      MaintenanceItemsSheetRouteState();
}

class MaintenanceItemsSheetRouteState
    extends State<MaintenanceItemsSheetRoute> {
  final refreshListenable = ValueNotifier<int>(0);

  @override
  void dispose() {
    refreshListenable.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PrototypeSheetFrame(
      title: '保养项目',
      child: MaintenanceItemsSheetContent(
        initialCar: widget.car,
        refreshListenable: refreshListenable,
      ),
    );
  }
}

/// 项目 sheet 主体：自管 loading/error/items 状态（不走全局 provider，
/// 直接 Repository 读），带代数防乱序 + 外部刷新监听。
/// 与其他页面"provider + invalidate"模式不同，这里是手写局部状态机。
class MaintenanceItemsSheetContent extends ConsumerStatefulWidget {
  const MaintenanceItemsSheetContent({
    required this.initialCar,
    required this.refreshListenable,
  });

  final Car? initialCar;
  final ValueNotifier<int> refreshListenable;

  @override
  ConsumerState<MaintenanceItemsSheetContent> createState() =>
      MaintenanceItemsSheetContentState();
}

class MaintenanceItemsSheetContentState
    extends ConsumerState<MaintenanceItemsSheetContent> {
  final scrollController = ScrollController();
  List<MaintenanceItem>? items;
  bool itemsLoading = false;
  String? itemsError;
  int? loadedCarId;

  /// 加载代数：只接受最新一次加载的结果（防快速切换车辆时旧结果覆盖）。
  int loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    widget.refreshListenable.addListener(_handleExternalRefresh);
  }

  @override
  void didUpdateWidget(MaintenanceItemsSheetContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshListenable == widget.refreshListenable) {
      return;
    }
    oldWidget.refreshListenable.removeListener(_handleExternalRefresh);
    widget.refreshListenable.addListener(_handleExternalRefresh);
  }

  @override
  void dispose() {
    widget.refreshListenable.removeListener(_handleExternalRefresh);
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final targetCar =
        widget.initialCar ??
        ref
            .watch(appliedCarProvider)
            .maybeWhen(data: (value) => value, orElse: () => null);
    if (targetCar?.id == null) {
      return const LunioInlineMessage(message: '请先新增车辆');
    }
    _ensureItemsLoaded(targetCar!.id!);
    final maxListHeight = MediaQuery.sizeOf(context).height * 0.54;
    final currentItems = items;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ItemPills(
                labels: ['${targetCar.brand} ${targetCar.model}'],
              ),
            ),
            const SizedBox(width: 12),
            SmallActionButton(
              label: '新增',
              onPressed: () async {
                final saved = await showMaintenanceItemFormSheet(
                  context,
                  ref,
                  carId: targetCar.id!,
                );
                if (saved == true) {
                  widget.refreshListenable.value += 1;
                }
              },
              primary: true,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (itemsLoading && currentItems == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (itemsError != null && currentItems == null)
          Text('加载失败：$itemsError')
        else ...[
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxListHeight),
            child: SingleChildScrollView(
              controller: scrollController,
              child: MaintenanceItemList(
                items: currentItems ?? const [],
                onEdit: (item) async {
                  final saved = await showMaintenanceItemFormSheet(
                    context,
                    ref,
                    carId: item.carsId,
                    item: item,
                  );
                  if (saved == true) {
                    await _reload(targetCar.id!);
                  }
                },
                onToggle: (item) async {
                  await toggleMaintenanceItem(context, ref, item);
                  await _reload(targetCar.id!);
                },
                onDelete: (item) async {
                  await deleteMaintenanceItem(context, ref, item);
                  await _reload(targetCar.id!);
                },
              ),
            ),
          ),
          if (itemsError != null) ...[
            const SizedBox(height: 10),
            LunioInlineMessage(
              message: '刷新失败：$itemsError',
              tone: LunioStatusTone.danger,
            ),
          ],
        ],
      ],
    );
  }

  /// 首次加载守卫（build 里调用，同车且已加载/加载中则跳过）。
  void _ensureItemsLoaded(int carId) {
    if (loadedCarId == carId && (items != null || itemsLoading)) {
      return;
    }
    loadedCarId = carId;
    items = null;
    itemsError = null;
    itemsLoading = true;
    _loadItems(carId, resetScroll: true);
  }

  /// 操作后重载列表。
  Future<void> _reload(int carId) async {
    if (!mounted) {
      return;
    }
    setState(() {
      loadedCarId = carId;
      itemsError = null;
      itemsLoading = items == null;
    });
    await _loadItems(carId);
  }

  /// 外部刷新信号（子表单保存成功）→ 重载当前车项目。
  void _handleExternalRefresh() {
    final carId = loadedCarId;
    if (carId == null) {
      return;
    }
    unawaited(_reload(carId));
  }

  /// 拉取项目列表（代数 + mounted + 车辆一致性三重校验后 setState）。
  Future<void> _loadItems(int carId, {bool resetScroll = false}) async {
    final generation = ++loadGeneration;
    try {
      final nextItems = await ref
          .read(lunioRepositoryProvider)
          .listMaintenanceItemsForCar(carId);
      if (!mounted || generation != loadGeneration || loadedCarId != carId) {
        return;
      }
      setState(() {
        items = nextItems;
        itemsError = null;
        itemsLoading = false;
      });
      if (resetScroll && scrollController.hasClients) {
        scrollController.jumpTo(0);
      }
    } catch (error) {
      if (!mounted || generation != loadGeneration || loadedCarId != carId) {
        return;
      }
      setState(() {
        itemsError = friendlyError(error);
        itemsLoading = false;
      });
    }
  }
}

/// 项目列表（草稿模式和落库模式共用）。
class MaintenanceItemList extends StatelessWidget {
  const MaintenanceItemList({
    required this.items,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  final List<MaintenanceItem> items;
  final ValueChanged<MaintenanceItem> onEdit;
  final ValueChanged<MaintenanceItem> onToggle;
  final ValueChanged<MaintenanceItem> onDelete;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Text('暂无保养项目', style: Theme.of(context).textTheme.bodyMedium),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 下标循环：行距判断用 index 而非实体 ==（R24）。
        for (var index = 0; index < items.length; index++) ...[
          MaintenanceItemCard(
            item: items[index],
            onEdit: () => onEdit(items[index]),
            onToggle: () => onToggle(items[index]),
            onDelete: () => onDelete(items[index]),
          ),
          if (index != items.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// 单个项目卡：左侧名称 + 规则文案，右侧编辑/启停/删除按钮，同一行排布。
class MaintenanceItemCard extends StatelessWidget {
  const MaintenanceItemCard({
    required this.item,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  final MaintenanceItem item;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final actions = Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        SmallActionButton(label: '编辑', onPressed: onEdit, secondary: true),
        const SizedBox(width: 8),
        SmallActionButton(
          label: item.enabled ? '已启用' : '已禁用',
          onPressed: onToggle,
          primary: item.enabled,
          muted: !item.enabled,
        ),
        if (onDelete != null) ...[
          const SizedBox(width: 8),
          SmallActionButton(
            label: '删除',
            tooltip: '删除',
            onPressed: onDelete,
            danger: true,
          ),
        ],
      ],
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
        border: Border.all(color: tokens.line),
        boxShadow: [
          BoxShadow(
            color: tokens.ink.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 左侧：名称 + 规则文案，占满剩余宽度；超长时省略号截断，
          // 保证右侧按钮始终与名称同处一行。
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 5),
                Text(
                  _itemRuleText(
                    remindByMileage: item.remindByMileage,
                    remindByTime: item.remindByTime,
                    mileageIntervalKm: item.mileageIntervalKm,
                    timeIntervalMonths: item.timeIntervalMonths,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          actions,
        ],
      ),
    );
  }
}

/// 项目表单（新增/编辑/草稿三态复用）：名称 + 里程/时间两个开关行 +
/// 校验（名称非空、至少一种提醒、开启的间隔为正整数）。
class MaintenanceItemForm extends StatefulWidget {
  const MaintenanceItemForm({
    required this.carId,
    this.item,
    required this.onSubmit,
  });

  final int carId;
  final MaintenanceItem? item;
  final Future<void> Function(MaintenanceItem item) onSubmit;

  @override
  State<MaintenanceItemForm> createState() => MaintenanceItemFormState();
}

class MaintenanceItemFormState extends State<MaintenanceItemForm> {
  late final TextEditingController nameController;
  late final TextEditingController mileageController;
  late final TextEditingController monthsController;
  bool remindByMileage = true;
  bool remindByTime = true;
  bool enabled = true;
  bool saving = false;
  String? errorText;

  bool get isEditing => widget.item != null;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    nameController = TextEditingController(text: item?.name ?? '');
    mileageController = TextEditingController(
      text: item?.mileageIntervalKm?.toString() ?? '',
    );
    monthsController = TextEditingController(
      text: item?.timeIntervalMonths?.toString() ?? '',
    );
    remindByMileage = item?.remindByMileage ?? true;
    remindByTime = item?.remindByTime ?? true;
    enabled = item?.enabled ?? true;
  }

  @override
  void dispose() {
    nameController.dispose();
    mileageController.dispose();
    monthsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: nameController,
          enabled: !saving,
          decoration: const InputDecoration(labelText: '项目名称'),
        ),
        const SizedBox(height: 10),
        IntervalNumberInputRow(
          title: '按里程提醒',
          controller: mileageController,
          unit: 'km',
          switchValue: remindByMileage,
          onSwitchChanged: saving
              ? null
              : (value) => setState(() => remindByMileage = value),
        ),
        const SizedBox(height: 10),
        IntervalNumberInputRow(
          title: '按时间提醒',
          controller: monthsController,
          unit: '月',
          switchValue: remindByTime,
          onSwitchChanged: saving
              ? null
              : (value) => setState(() => remindByTime = value),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 10),
          LunioInlineMessage(message: errorText!, tone: LunioStatusTone.danger),
        ],
        const SizedBox(height: 16),
        LunioFormActions(
          confirmLabel: '保存项目',
          onCancel: () => Navigator.of(context).pop(),
          onConfirm: _submit,
          saving: saving,
        ),
      ],
    );
  }

  /// 提交校验 + 构造实体 → onSubmit → 失败表单内展示中文错误。
  /// 新项目 sortOrder 默认 999（排在默认项之后）。
  Future<void> _submit() async {
    final name = nameController.text.trim();
    final mileageInterval = int.tryParse(mileageController.text);
    final timeInterval = int.tryParse(monthsController.text);
    if (name.isEmpty) {
      setState(() => errorText = '项目名称不能为空');
      return;
    }
    if (!remindByMileage && !remindByTime) {
      setState(() => errorText = '至少选择一种提醒方式');
      return;
    }
    if (remindByMileage && (mileageInterval == null || mileageInterval <= 0)) {
      setState(() => errorText = '里程间隔必须填写正整数');
      return;
    }
    if (remindByTime && (timeInterval == null || timeInterval <= 0)) {
      setState(() => errorText = '时间间隔必须填写正整数');
      return;
    }
    setState(() {
      saving = true;
      errorText = null;
    });
    final item = widget.item;
    try {
      await widget.onSubmit(
        MaintenanceItem(
          id: item?.id,
          carsId: widget.carId,
          name: name,
          enabled: enabled,
          remindByMileage: remindByMileage,
          remindByTime: remindByTime,
          mileageIntervalKm: remindByMileage ? mileageInterval : null,
          timeIntervalMonths: remindByTime ? timeInterval : null,
          notOverdueUpperLimit: item?.notOverdueUpperLimit ?? 100,
          overdueUpperLimit: item?.overdueUpperLimit ?? 125,
          sortOrder: item?.sortOrder ?? 999,
          sync: SyncMetadata(
            status: isEditing
                ? SyncStatus.pendingUpdate
                : SyncStatus.pendingCreate,
            updatedAt: DateTime.now(),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        saving = false;
        errorText = friendlyError(error);
      });
    }
  }
}

/// ★ 落库版项目表单 sheet（项目 sheet / 记录表单行内新增用）：
/// 新增走 saveMaintenanceItem、编辑走 updateMaintenanceItem →
/// invalidate → pop(true)（true=已保存，调用方据此刷新）。
Future<bool?> showMaintenanceItemFormSheet(
  BuildContext context,
  WidgetRef ref, {
  required int carId,
  MaintenanceItem? item,
}) {
  return showLunioModalSheet<bool>(
    context: context,
    builder: (sheetContext) {
      return PrototypeSheetFrame(
        title: item == null ? '新增保养项目' : '编辑保养项目',
        bottomInset: MediaQuery.of(sheetContext).viewInsets.bottom,
        child: MaintenanceItemForm(
          carId: carId,
          item: item,
          onSubmit: (value) async {
            // 写库+失效收进动作层（ADR 0007），这里只留反馈薄壳。
            await saveMaintenanceItem(ref, value);
            if (sheetContext.mounted) {
              Navigator.of(sheetContext).pop(true);
            }
            // 落库版才提示保存成功；向导里的草稿版不落库，不提示。
            if (context.mounted) {
              showStatusOverlay(
                context,
                '保养项目已保存',
                StatusOverlayTone.success,
              );
            }
          },
        ),
      );
    },
  );
}

/// 草稿版项目表单 sheet（添加车辆向导内用）：不落库，确认后回调
/// onSubmit 把结果交还向导的内存草稿列表。
Future<bool?> showDraftMaintenanceItemFormSheet(
  BuildContext context, {
  required MaintenanceItem item,
  required ValueChanged<MaintenanceItem> onSubmit,
}) {
  return showLunioModalSheet<bool>(
    context: context,
    builder: (context) {
      return PrototypeSheetFrame(
        title: item.name.isEmpty ? '新增保养项目' : '编辑保养项目',
        bottomInset: MediaQuery.of(context).viewInsets.bottom,
        child: MaintenanceItemForm(
          carId: 0,
          item: item,
          onSubmit: (value) async {
            onSubmit(value);
            if (context.mounted) {
              Navigator.of(context).pop(true);
            }
          },
        ),
      );
    },
  );
}

/// 启停项目（项目卡按钮）：动作层写库+失效；失败（如停用最后一个
/// 启用项）toast 展示中文错误。
Future<void> toggleMaintenanceItem(
  BuildContext context,
  WidgetRef ref,
  MaintenanceItem item,
) async {
  try {
    await setMaintenanceItemEnabled(ref, item, !item.enabled);
  } catch (error) {
    if (context.mounted) {
      showStatusOverlay(context, friendlyError(error), StatusOverlayTone.error);
    }
  }
}

/// 删除项目（项目卡按钮）：确认框 → 动作层删除+失效（有历史记录会
/// 抛错）→ 失败 toast。
Future<void> deleteMaintenanceItem(
  BuildContext context,
  WidgetRef ref,
  MaintenanceItem item,
) async {
  final confirmed = await showConfirmDialog(
    context: context,
    title: '删除保养项目',
    message: '确定删除 ${item.name}？有历史记录的项目不能删除。',
    confirmLabel: '删除',
  );
  if (confirmed != true || item.id == null) {
    return;
  }
  try {
    await removeMaintenanceItem(ref, item.id!);
  } catch (error) {
    if (context.mounted) {
      showStatusOverlay(context, friendlyError(error), StatusOverlayTone.error);
    }
  }
}

// ---- 文件内私有格式化（§5.2 回收：仅本文件消费的函数不留公共面）----

/// 项目名规范化（去首尾空白）：表单保存与"恢复默认项目"的重复比对
/// 都走它。
String _normalizeItemName(String value) => value.trim();

/// 项目规则文案："提醒：5,000公里/6个月"（车辆级项目与默认模板共用，
/// 由调用方传字段——合并原 itemRuleText/defaultItemRuleText 双实现）。
String _itemRuleText({
  required bool remindByMileage,
  required bool remindByTime,
  required int? mileageIntervalKm,
  required int? timeIntervalMonths,
}) {
  final rules = <String>[];
  if (remindByMileage) {
    rules.add(_formatCompactMileageText(mileageIntervalKm ?? 0));
  }
  if (remindByTime) {
    rules.add(_formatCompactTimeText(timeIntervalMonths ?? 0));
  }
  return rules.isEmpty ? '提醒：未设置' : '提醒：${rules.join('/')}';
}

/// 紧凑里程文案：≥1万 显示"1.2万公里"。
String _formatCompactMileageText(int value) {
  if (value >= 10000) {
    final wan = value / 10000;
    final text = wan == wan.roundToDouble()
        ? wan.toStringAsFixed(0)
        : wan.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
    return '$text万公里';
  }
  return '${formatNumber(value)}公里';
}

/// 紧凑时长文案：18 → "18个月"、24 → "2年"、30 → "2.5年"。
String _formatCompactTimeText(int months) {
  if (months < 12) {
    return '$months个月';
  }
  if (months % 12 == 0) {
    return '${months ~/ 12}年';
  }
  final years = months / 12;
  final text = years.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
  return '$text年';
}
