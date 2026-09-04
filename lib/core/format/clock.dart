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
