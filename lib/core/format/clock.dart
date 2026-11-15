// core 层时刻格式化（供通知服务与停车倒计时卡片共用）。
//
// 放在 core 的原因：通知服务（core/notifications）也要用它拼通知文案，
// 过去它反向 import features/shell/shared 的格式化集——core 依赖 features
// 属于方向反了的依赖（记录在案的取舍，本轮解掉）。
//
// HH:mm:ss 的 24 小时制时刻（停车倒计时卡片/表单与常驻通知共用）。
String formatClock(DateTime dateTime) {
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  final second = dateTime.second.toString().padLeft(2, '0');
  return '$hour:$minute:$second';
}

/// 读数时刻显示（2026-11-15，诊断页最后读数用）：今天显 HH:mm:ss（视
/// 觉不变），非今天显 M/d HH:mm:ss（跨天读数带日期，避免"只显时分秒"
/// 误导）。now 由调用方注入（页面传 DateTime.now()，测试注入固定时
/// 钟），保持纯函数可单测。
String formatReadingTime(DateTime at, {required DateTime now}) {
  final sameDay =
      at.year == now.year && at.month == now.month && at.day == now.day;
  final clock = formatClock(at);
  return sameDay ? clock : '${at.month}/${at.day} $clock';
}
