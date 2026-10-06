// 定高吸附滚动窗口（scroll_window.dart）：shell 内「定行高视口 + 右侧
// 3dp 细滚动条（滑动时淡入、停稳淡出）+ 整行吸附 + 内容右缩进给拇指
// 让位」这套卡内滚动容器三明治的唯一实现（2026-10-01 收编，思路同
// LunioTappableCard 的整卡可点三明治）。收编前加满预估档位列表与加油
// 记录卡各自手拼同一套五层嵌套、靠注释互相点名保持一致——历史上滚动
// 条样式与「拇指不再常显」的调整都是两处同步改的；下一轮全局调滚动条
// 手感只改本文件一处。
//
// 与 scroll_snap.dart 是组合关系：本组件按 [rowExtent] 组装
// RowSnapScrollPhysics 实例（消费吸附物理，不复制弹道）；吸附纯在手势
// 层，不做任何持久化——「停在哪行要不要记账」是调用方自己的事（档位
// 列表在 ScrollEnd 通知里写库，加油记录卡不记）。
//
// 费用统计柱状图（横向滚动，axes_column_chart.dart）未接入本组件，原
// 因见该文件现场注释。
// Java 类比：一个定高定步长的复合滚动控件（JScrollPane 的固定行高
// 变体），行渲染交给调用方的 cell renderer。
// ignore_for_file: library_private_types_in_public_api

import 'package:flutter/material.dart';

import 'scroll_snap.dart';

/// 定高吸附滚动窗口：固定行高 × 固定可见行数的卡内滚动列表。
///
/// 收进组件内部、调用方不再手拼的约定：
///  - 视口高度恒等于 [visibleRows] × [rowExtent]（窗口高度 = 整数行，
///    每行走 [itemExtent] 定槽，不会出现半行）；
///  - 右侧 3dp 细滚动条（圆角 2），滑动时淡入、停稳淡出（不显式设
///    thumbVisibility，跟随平台默认——拇指不常显）；
///  - 内容右缩进 [thumbInset] 给拇指让位（右对齐的文字/金额不与拇指
///    重叠）；
///  - 滚动物理 = RowSnapScrollPhysics(rowExtent)，停稳吸附整行边界。
///
/// 调用方仍自己负责的两件事：
///  - [controller] 由调用方持有并传入（档位列表要向决策体
///    FuelTierListController 注入 offset/jumpTo 滚动真值，记录卡自持；
///    组件不创建、不 dispose）；
///  - 不滚动的表头要与行内容右缘对齐时，自行包
///    `Padding(padding: EdgeInsets.only(right: LunioSnapScrollWindow.thumbInset))`。
///
/// 当前调用点：加油页加满预估档位列表（tailRows = visibleRows - 1）、
/// 加油记录卡超量滚动窗口（tailRows = 0）。
class LunioSnapScrollWindow extends StatelessWidget {
  const LunioSnapScrollWindow({
    super.key,
    required this.controller,
    required this.rowExtent,
    required this.visibleRows,
    required this.itemCount,
    required this.itemBuilder,
    this.tailRows = 0,
  });

  /// 滚动控制器：调用方持有传入（初始定位 / 决策体注入真值 / 编程
  /// 滚动），组件只透传给滚动条与列表。
  final ScrollController controller;

  /// 单行固定高度：布局步长（itemExtent）与吸附步长共用同一份值。
  final double rowExtent;

  /// 窗口内可见行数（视口高度 = 该值 × [rowExtent]）。
  final int visibleRows;

  /// 行数。
  final int itemCount;

  /// 行构造器：只管一行内容，行高由 [rowExtent] 统一控制（类比 Java
  /// 列表的 cell renderer，不要自己包定高 SizedBox）。
  final IndexedWidgetBuilder itemBuilder;

  /// 底部让位行数（默认 0）：内容末尾垫 [tailRows] × [rowExtent] 的
  /// 空白，让最后一行能滚到窗口第一行。档位列表用（0% 那档也要能停在
  /// 第一行）；普通流水列表最后一行滚到窗口底部即可，不传。
  final int tailRows;

  /// 拇指让位缩进（右侧 12dp）：滚动内容侧组件内部用；调用方的不滚动
  /// 表头要右缘对齐时引用同一常量，「12」全库只在这一处取值。
  static const double thumbInset = 12;

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: controller,
      // 细滚动条样式收在这里：全局调滚动条手感只改本文件。
      thickness: 3,
      radius: const Radius.circular(2),
      child: SizedBox(
        height: visibleRows * rowExtent,
        child: ListView.builder(
          controller: controller,
          physics: RowSnapScrollPhysics(rowExtent: rowExtent),
          itemExtent: rowExtent,
          padding: EdgeInsets.only(
            right: thumbInset,
            bottom: tailRows * rowExtent,
          ),
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        ),
      ),
    );
  }
}
