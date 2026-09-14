// 车型目录选择器：品牌车型 tile + 选择 sheet（搜索 + 品牌/车型双列 +
// 列表外自定义输入弹窗）。
//
// 在 App 中的位置：profile 域，只被添加车辆向导第一步（add_car_wizard.dart
// 的 AddCarForm）使用；目录数据以懂车帝原始车系名为准（ADR 0003），
// 覆盖不到的老车走"自定义输入"兜底。
// 搜索过滤/品牌派生/生效品牌回退收成三个纯函数（可直接单测，见
// test/features/vehicle_model_picker_test.dart），sheet 的 State 只做
// 渲染与输入态——此前派生逻辑内联在 build 里，还在 build 里改过字段
// （副作用，已修的 bug 现场）。
//
// ≈ Java Web 里抽出来的选择器组件 + 静态工具方法。
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'package:flutter/material.dart';

import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';
import '../../../domain/entities/vehicle_model.dart';
import '../shared/shell_shared.dart';

/// 搜索过滤：品牌+车型名拼接后做包含匹配；空关键词（含纯空白）返回
/// 全量的新列表。
List<VehicleModel> filterVehicleModels(
  List<VehicleModel> models,
  String keyword,
) {
  final trimmed = keyword.trim();
  if (trimmed.isEmpty) {
    return List.of(models);
  }
  return models
      .where((model) => '${model.brand}${model.model}'.contains(trimmed))
      .toList();
}

/// 品牌派生：过滤结果里的品牌按出现顺序去重（左列数据源）。
List<String> deriveBrands(List<VehicleModel> filteredModels) {
  final brands = <String>[];
  for (final model in filteredModels) {
    if (!brands.contains(model.brand)) {
      brands.add(model.brand);
    }
  }
  return brands;
}

/// 生效品牌：选中品牌不在过滤结果里时回退第一个。只影响本次布局的
/// 品牌高亮与车型列，不回写字段；品牌列表为空时维持原选中值。
String effectiveBrand(List<String> brands, String selected) {
  if (brands.contains(selected)) {
    return selected;
  }
  return brands.isNotEmpty ? brands.first : selected;
}

/// 品牌车型选择 tile（点击弹出选择 sheet，返回 (brand, model) 元组）。
class VehicleModelPicker extends StatelessWidget {
  const VehicleModelPicker({
    required this.vehicleModels,
    required this.selectedBrand,
    required this.selectedModel,
    required this.enabled,
    required this.onSelected,
  });

  final List<VehicleModel> vehicleModels;
  final String selectedBrand;
  final String selectedModel;
  final bool enabled;
  final void Function(String brand, String model) onSelected;

  @override
  Widget build(BuildContext context) {
    return LunioPickerTile(
      label: '品牌车型',
      value: '$selectedBrand $selectedModel',
      enabled: enabled,
      onTap: () async {
        final value = await _showVehicleModelPickerSheet(
          context,
          vehicleModels: vehicleModels,
          selectedBrand: selectedBrand,
          selectedModel: selectedModel,
        );
        if (value != null) {
          onSelected(value.$1, value.$2);
        }
      },
    );
  }
}

Future<(String, String)?> _showVehicleModelPickerSheet(
  BuildContext context, {
  required List<VehicleModel> vehicleModels,
  required String selectedBrand,
  required String selectedModel,
}) {
  return showLunioModalSheet<(String, String)>(
    context: context,
    builder: (context) => PrototypeSheetFrame(
      title: '选择车型',
      subtitle: '选择车辆品牌和车型，列表外的车型可自定义输入',
      bottomInset: MediaQuery.of(context).viewInsets.bottom,
      child: VehicleModelPickerSheet(
        vehicleModels: vehicleModels,
        selectedBrand: selectedBrand,
        selectedModel: selectedModel,
      ),
    ),
  );
}

/// 车型选择 sheet：搜索框（品牌+车型名包含匹配）+ 左品牌右车型双列。
/// 点车型行即确认返回。
class VehicleModelPickerSheet extends StatefulWidget {
  const VehicleModelPickerSheet({
    required this.vehicleModels,
    required this.selectedBrand,
    required this.selectedModel,
  });

  final List<VehicleModel> vehicleModels;
  final String selectedBrand;
  final String selectedModel;

  @override
  State<VehicleModelPickerSheet> createState() =>
      VehicleModelPickerSheetState();
}

class VehicleModelPickerSheetState extends State<VehicleModelPickerSheet> {
  final searchController = TextEditingController();
  late String selectedBrand;

  @override
  void initState() {
    super.initState();
    selectedBrand = widget.selectedBrand;
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final filteredModels = filterVehicleModels(
      widget.vehicleModels,
      searchController.text,
    );
    final brands = deriveBrands(filteredModels);
    final activeBrand = effectiveBrand(brands, selectedBrand);
    final models = filteredModels
        .where((model) => model.brand == activeBrand)
        .toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: searchController,
          decoration: const InputDecoration(
            labelText: '搜索品牌或车型',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.48,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: tokens.surface2,
              borderRadius: BorderRadius.circular(tokens.radiusLarge),
              border: Border.all(color: tokens.line),
            ),
            child: brands.isEmpty
                ? Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          '没有匹配车型',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      // 无匹配时自定义入口也要可用（目录外老车的主要入口）。
                      PickerOption(
                        label: '＋ 自定义输入…',
                        selected: false,
                        enabled: true,
                        onTap: () async {
                          final value = await _showCustomModelDialog(context);
                          if (value != null && context.mounted) {
                            Navigator.of(context).pop(value);
                          }
                        },
                      ),
                    ],
                  )
                : Row(
                    children: [
                      SizedBox(
                        width: 124,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: brands.length,
                          itemBuilder: (context, index) {
                            final brand = brands[index];
                            return PickerOption(
                              label: brand,
                              selected: brand == activeBrand,
                              enabled: true,
                              onTap: () => setState(() {
                                selectedBrand = brand;
                              }),
                            );
                          },
                        ),
                      ),
                      Container(width: 1, color: tokens.line),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.all(8),
                          // +1：末尾固定一行"自定义输入"入口——目录以懂车帝
                          // 为准（ADR 0003），覆盖不到的老车从这里手输。
                          itemCount: models.length + 1,
                          itemBuilder: (context, index) {
                            if (index == models.length) {
                              return PickerOption(
                                label: '＋ 自定义输入…',
                                selected: false,
                                enabled: true,
                                onTap: () async {
                                  final value = await _showCustomModelDialog(
                                    context,
                                  );
                                  if (value != null && context.mounted) {
                                    Navigator.of(context).pop(value);
                                  }
                                },
                              );
                            }
                            final model = models[index];
                            final selected =
                                model.brand == widget.selectedBrand &&
                                model.model == widget.selectedModel;
                            return PickerOption(
                              label: model.model,
                              selected: selected,
                              enabled: true,
                              onTap: () => Navigator.of(
                                context,
                              ).pop((model.brand, model.model)),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

/// 双列选择器的单行选项。
class PickerOption extends StatelessWidget {
  const PickerOption({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(tokens.radiusSmall),
      child: Container(
        height: 42,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: selected ? tokens.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(tokens.radiusSmall),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected ? tokens.primary : tokens.muted,
          ),
        ),
      ),
    );
  }
}

/// 自定义车型弹窗：品牌/车型两个必填输入框，确认返回 (brand, model)。
/// 目录（懂车帝命名）覆盖不到的车型从这里手输；取消/校验失败返回 null。
/// 走 showLunioDialog seam（毛玻璃底/动画/收键盘与全局弹层一致），
/// 卡片样式与其余弹窗同族（surface + radiusLarge + line）。
Future<(String, String)?> _showCustomModelDialog(BuildContext context) {
  final brandController = TextEditingController();
  final modelController = TextEditingController();
  return showLunioDialog<(String, String)>(
    context: context,
    builder: (dialogContext) {
      String? errorText;
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          void submit() {
            final brand = brandController.text.trim();
            final model = modelController.text.trim();
            if (brand.isEmpty || model.isEmpty) {
              setDialogState(() => errorText = '品牌和车型都要填写');
              return;
            }
            Navigator.of(dialogContext).pop((brand, model));
          }

          final tokens = Theme.of(dialogContext).extension<LunioTokens>()!;
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 24),
            backgroundColor: Colors.transparent,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: BorderRadius.circular(tokens.radiusLarge),
                border: Border.all(color: tokens.line),
                boxShadow: [
                  BoxShadow(
                    color: tokens.ink.withValues(alpha: 0.16),
                    blurRadius: 36,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('自定义车型',
                      style: Theme.of(dialogContext).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextField(
                    controller: brandController,
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: '品牌'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: modelController,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => submit(),
                    decoration: const InputDecoration(labelText: '车型'),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      errorText!,
                      style: Theme.of(dialogContext)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: tokens.danger),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: LunioSecondaryButton(
                          label: '取消',
                          onPressed: () => Navigator.of(dialogContext).pop(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: submit,
                          child: const Text('确定'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
