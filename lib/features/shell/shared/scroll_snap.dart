// 整行/整柱吸附滚动物理（scroll_snap.dart）：滚动停稳后把偏移对齐到
// 固定步长的边界上，供 shell 内三处滚动位共用——加满预估档位列表（整
// 行吸附 + 停稳写库，ADR 0002）、加油记录卡卡内列表（整行吸附）、费用
// 统计坐标系柱状图（整柱吸附，横向）。
//
// 使用方只要三件事成立：内容按 [rowExtent] 定步长排布、滚动范围交给
// 常规 Scrollable（ListView/SingleChildScrollView 均可）、physics 传本
// 类实例。吸附纯在手势层，不做任何持久化——"停在哪格要不要记账"是
// 使用方自己的事（档位列表在 ScrollEnd 通知里写库，图表与记录卡不记）。
// Java 类比：一个可插拔的滚动策略对象（策略模式），按构造参数步长工作。
// ignore_for_file: library_private_types_in_public_api

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// 整行吸附物理：滚动停稳后把偏移落在 [rowExtent] 的整数倍边界上。
///
/// 吸附要"跟手"，甩动惯性不能扔（朴素实现只吸附到松手位置最近的整行，
/// 快速一划列表最多挪半行多，手感像跟不上手指）。做法照搬官方
/// FixedExtentScrollPhysics 的弹道投射（list_wheel_scroll_view.dart）：
///  1. 已越界且继续朝界外走 → 交给父物理（平台默认）拉回边界；
///  2. 用父物理的自然摩擦弹道算出"不吸附时会停在哪"，取最近整行作目标
///    （越界停点夹回边界格）；
///  3. 速度太小翻不过半行 → 弹簧弹回目标行；否则用
///     FrictionSimulation.through 精确滑到目标行（惯性手感保留）。
/// 无论走哪条路径，弹道终点都严格对齐整行边界——ScrollEnd 时偏移必已
/// 对齐，使用方可在 ScrollEnd 通知里直接消费位置（不能在 ScrollEnd 通
/// 知里再 animateTo——滚动活动收尾期间改活动会被滚动位置静默忽略）。
class RowSnapScrollPhysics extends ScrollPhysics {
  const RowSnapScrollPhysics({required this.rowExtent, super.parent});

  /// 吸附步长（一行/一柱的定宽高），与内容排布共用同一份常量。
  final double rowExtent;

  @override
  RowSnapScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      RowSnapScrollPhysics(rowExtent: rowExtent, parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    // 情形 1：越界还朝界外走，边界回弹交给父物理。
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    // 情形 2：父物理自然弹道的停点 → 最近整行（越界停点夹回边界档）。
    final naturalSimulation = super.createBallisticSimulation(
      position,
      velocity,
    );
    final naturalStop =
        naturalSimulation?.x(double.infinity) ?? position.pixels;
    final maxIndex = (position.maxScrollExtent / rowExtent).floor();
    final targetIndex = (naturalStop / rowExtent).round().clamp(0, maxIndex);
    final target = targetIndex * rowExtent;
    final tolerance = toleranceFor(position);
    // 情形 3：没速度且已在目标行上，不再模拟。
    if (velocity.abs() < tolerance.velocity &&
        (target - position.pixels).abs() < tolerance.distance) {
      return null;
    }
    final currentIndex = (position.pixels / rowExtent).round();
    // 情形 4：速度太小翻不过当前行的半程，弹簧弹回目标行。
    if (targetIndex == currentIndex) {
      return SpringSimulation(
        spring,
        position.pixels,
        target,
        velocity,
        tolerance: tolerance,
      );
    }
    // 情形 5：调摩擦系数让自然弹道恰好停在目标整行上（保留惯性）。
    return FrictionSimulation.through(
      position.pixels,
      target,
      velocity,
      tolerance.velocity * velocity.sign,
    );
  }
}
