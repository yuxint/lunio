// 扫描清单协议（纯 Dart，零 Flutter / 零 flutter_blue_plus）：扫描条目的
// 数据模型 + 首见定序合并函数 + ≤1Hz 发射合并器。2026-11-15 从
// ble_obd_transport.dart 拆出（ADR 0020 修订节的行序决定是独立概念，
// 测试文件 test/features/ble_scan_entries_test.dart 早已按独立模块写）。
//
// ≈ Java 的合并函数 + 节流阀（coalescing valve）：输入旧有序链表与新高
// 频快照，输出新有序链表；发射节奏由合并器压到 ≤1Hz，稳定行序与刷新频
// 率是同一根因的两面，收在同一模块。
//
// 本文件不碰 BLE：条目由扫描器 adapter（ble_obd_link.dart）从平台结果
// 映射进来，测试替身经 [mergeScanEntries] 镜像同一契约。

/// 一台扫描到的 BLE 设备（扫描列表行数据）。
class BleObdScanEntry {
  const BleObdScanEntry({
    required this.id,
    required this.name,
    required this.rssi,
  });

  /// 平台设备标识（iOS = CBPeripheral identifier UUID；Android = MAC），
  /// 设备记忆偏好与定向扫描都用它。
  final String id;

  /// 广播名（合并函数已过滤空名，清单里的条目恒非空）。
  final String name;

  /// 信号强度 dBm（越大越近）。列表序不跟随它实时变化：行位置在首见
  /// 时定死，数字按 ≤1Hz 刷新（2026-11-15，ADR 0020 修订节）。
  final int rssi;
}

/// 扫描清单合并（纯函数，维护"首见定序"）：2026-11-15 拍板
/// （ADR 0020 修订节）——RSSI 每拍抖 ±3~10dBm，按当前值重排会让行序
/// 频繁乱跳，改为设备位置在首次发现时定死。
///
/// 规则：
/// 1. 广播名为空的设备不进清单（同日拍板反转 story 5「全部显示防误
///    伤」：无名条目是与 OBD 无关的周边蓝牙设备，留着只会淹没有效
///    目标；有自定义名的适配器不受影响）。
/// 2. 已在清单里的设备位置冻结，只更新信号强度/名称——后续拍摄不再
///    重排。
/// 3. 新设备按"当下展示的信号强度"插入：排在第一条比它弱的行之前；
///    同强度排已有行之后（首见先后即次序）；同拍多台新设备之间按信
///    号降序、同强度按设备标识排序（Dart List.sort 不保证稳定，显式
///    定序保证测试确定性）。
/// 4. 这一拍里没出现的老设备保留原行原值（FBP 全量清单偶发缺行/名瞬
///    时为空时不闪行——扫描 sheet 生命周期短，宁可留旧不闪）。
///
/// ≈ Java 的合并函数：输入旧有序链表 + 新快照，返回新有序链表，不修
/// 改入参。测试直接单测本函数（test/features/ble_scan_entries_test.
/// dart）。
List<BleObdScanEntry> mergeScanEntries(
  List<BleObdScanEntry> previous,
  List<BleObdScanEntry> latest,
) {
  final freshById = <String, BleObdScanEntry>{
    for (final entry in latest)
      if (entry.name.isNotEmpty) entry.id: entry,
  };
  final merged = <BleObdScanEntry>[];
  for (final old in previous) {
    final fresh = freshById.remove(old.id);
    merged.add(fresh ?? old);
  }
  final newcomers = freshById.values.toList()
    ..sort((a, b) {
      final byRssi = b.rssi.compareTo(a.rssi);
      return byRssi != 0 ? byRssi : a.id.compareTo(b.id);
    });
  for (final entry in newcomers) {
    var index = merged.length;
    for (var i = 0; i < merged.length; i++) {
      if (merged[i].rssi < entry.rssi) {
        index = i;
        break;
      }
    }
    merged.insert(index, entry);
  }
  return merged;
}

/// 扫描清单合并器：把高频原始扫描拍压成 ≤[interval] 的列表发射
/// （2026-11-15 拍板，ADR 0020 修订节）。排序稳定性（[mergeScanEntries]）
/// 与刷新节奏是同一根因的两面，都收在这里：
///
/// - 首拍立即发射：sheet 打开即见列表，不等整拍；
/// - 出现新设备立即发射：发现即可见（插入本身就是要的信息）；
/// - 只有信号数字变化时合并等待：距上次发射 ≥ [interval] 才发，
///   不足则记脏，由外部节拍器到点调 [flushIfDue] 补发尾拍。
///
/// 定序状态生命周期 = 一次扫描会话（[reset] 由 `BleObdScanner.start` 调
/// 用）：恢复扫描重新定序一次，失败是低频路径，接受这一下重排，不为此
/// 增加跨会话协议。时间经 [now] 注入，单测给固定时钟。
/// ≈ Java 的节流阀（coalescing valve）：窗口内的更新合并成一次。
class ScanEntryCoalescer {
  ScanEntryCoalescer({
    required this.emit,
    this.interval = defaultInterval,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// 默认合并窗口：1 秒（行序冻结后数字 1Hz 刷新足够）。
  static const defaultInterval = Duration(seconds: 1);

  /// 发射出口（真扫描器接结果流控制器；单测收进列表）。
  final void Function(List<BleObdScanEntry> entries) emit;

  /// 合并窗口。
  final Duration interval;

  final DateTime Function() _now;

  List<BleObdScanEntry> _entries = const [];
  DateTime? _lastEmitAt;
  bool _dirty = false;

  /// 当前合并后的清单（只读；测试断言用）。
  List<BleObdScanEntry> get entries => _entries;

  /// 清空定序与节流窗口（新扫描会话调用）。
  void reset() {
    _entries = const [];
    _lastEmitAt = null;
    _dirty = false;
  }

  /// 收一拍原始清单：合并后按"首拍/新设备/窗口到点立即发，否则记脏"
  /// 决定是否现在发射。
  void accept(List<BleObdScanEntry> latest) {
    final previousCount = _entries.length;
    _entries = mergeScanEntries(_entries, latest);
    final last = _lastEmitAt;
    final due = last == null || _now().difference(last) >= interval;
    if (_entries.length > previousCount || due) {
      _emit();
      return;
    }
    _dirty = true;
  }

  /// 节拍器到点补发（无待发更新不发）。
  void flushIfDue() {
    if (!_dirty) {
      return;
    }
    final last = _lastEmitAt;
    if (last == null || _now().difference(last) >= interval) {
      _emit();
    }
  }

  void _emit() {
    _lastEmitAt = _now();
    _dirty = false;
    emit(_entries);
  }
}
