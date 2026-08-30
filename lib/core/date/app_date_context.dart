// 应用日期上下文：统一"今天是几号"的取值入口。
//
// 双轨设计：
//  - readSystemNow：系统真实时钟（停车倒计时、系统通知调度时刻用）；
//  - manualDate：开发者模式的手动覆盖日期（业务日期计算用）。
// today() = manualDate ?? 系统今天。
//
// typedef ≈ Java 的函数式接口（Supplier<DateTime>），
// 把"怎么取当前时间"做成可注入的，测试可以传固定时间。
//
// ⚠ 生产环境 appDateContextProvider 只用 system()（manualDate 恒为 null）；
// 手动日期实际走 manualDatePreferenceProvider → effectiveTodayProvider
// （providers.dart），本类的 manualDate 字段目前是预留位（R30）。
import 'local_date.dart';

typedef DateTimeReader = DateTime Function();

class AppDateContext {
  const AppDateContext({required this.readSystemNow, this.manualDate});

  /// 生产工厂：直接用系统时钟。
  factory AppDateContext.system() {
    return AppDateContext(readSystemNow: DateTime.now);
  }

  final DateTimeReader readSystemNow;

  /// 手动覆盖日期（null = 未启用）。
  final LocalDate? manualDate;

  /// 当前业务"今天"：手动日期优先，否则由系统时间转 LocalDate。
  LocalDate today() {
    return manualDate ?? LocalDate.fromDateTime(readSystemNow());
  }

  /// 返回带手动日期的副本（测试/预留用）。
  AppDateContext withManualDate(LocalDate date) {
    return AppDateContext(readSystemNow: readSystemNow, manualDate: date);
  }

  /// 返回去掉手动日期的副本。
  AppDateContext withoutManualDate() {
    return AppDateContext(readSystemNow: readSystemNow);
  }
}
