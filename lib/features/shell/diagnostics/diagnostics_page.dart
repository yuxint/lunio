// 车辆诊断页（/diagnostics）：开发者模式工具页，经 BLE OBD 适配器
// 读取车辆实时数据（GLOSSARY「车辆诊断」词条，ADR 0020）。
//
// 当前是票 03 的占位页：只落路由挂载与 pushed 子页形态——默认转场
// builder、页面自供 Scaffold（pushed 子页不经过 AppShell，无底部导航，
// 页面底色要自己给）、返回键在 LunioTopBar 的 leading 位，对齐费用
// 统计页先例。三区内容（连接状态条/核心值卡/检测点列表）由票 05 替换。
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';

/// 车辆诊断页主组件（票 05 替换为完整三区实现）。
class DiagnosticsPage extends StatelessWidget {
  const DiagnosticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Scaffold(
      backgroundColor: tokens.background,
      body: LunioPage(
        title: '车辆诊断',
        leading: LunioIconButton(
          icon: Icons.arrow_back_ios_new,
          tooltip: '返回',
          onPressed: () => context.pop(),
        ),
        bottomPadding: 24,
        children: [
          const LunioEmptyCard('诊断功能开发中，连接与读取将在后续版本提供。'),
        ],
      ),
    );
  }
}
