// 应用车辆回退规则（纯静态工具类 ≈ Java 的 final 工具类 + 私有构造）。
//
// "应用车辆"= 当前被提醒页/记录页展示的那辆车，存在偏好 key
// `appliedCarId` 里。本规则决定：当偏好值缺失/失效时该显示哪辆车。
//
// 调用点：Repository 的读路径（getAppliedCar 回退分支）与写路径
// （deleteCar 级联后的重指、_ensureAppliedCarInTransaction 恢复备份
// 收尾）——三处共用本规则，回退语义只在这一份代码里。
import '../entities/car.dart';

class AppliedCarRules {
  // 私有构造 + 纯静态方法：禁止实例化（Java 工具类的常见写法）。
  const AppliedCarRules._();

  /// 解析当前应用车辆 id。
  ///
  /// 规则（按优先级）：
  ///  1. 没有任何车 → null（提醒页显示"还没有车辆"空卡片）；
  ///  2. 偏好里存的 id 仍存在于车辆列表 → 保留用户上次选择；
  ///  3. 偏好缺失或指向已删除的车 → 回退第一辆车。
  ///
  /// 场景：删除当前应用车辆后，剩余车辆自动接管为应用车辆。
  static int? resolveAppliedCarId({
    required List<Car> cars,
    required int? storedCarId,
  }) {
    if (cars.isEmpty) {
      return null;
    }
    if (storedCarId != null && cars.any((car) => car.id == storedCarId)) {
      return storedCarId;
    }
    return cars.first.id;
  }
}
