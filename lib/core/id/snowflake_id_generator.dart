// 雪花 id 生成器（Twitter Snowflake 的 Dart 实现）。
//
// 64 位布局：时间戳(41bit) | 节点(10bit) | 序列(12bit)，
// 单机单调递增、趋势有序、int 可存 SQLite。Repository 所有表的
// 主键 id 都由它生成（static 单例，进程内唯一）。
//
// epoch 定在 2026-01-01 UTC，时间戳用"距 epoch 毫秒数"，
// 41bit 够用约 69 年。
typedef NowProvider = DateTime Function();

class SnowflakeIdGenerator {
  /// nodeId 0~1023（本单机 App 恒为 0）；now 可注入（测试时钟回拨）。
  SnowflakeIdGenerator({int nodeId = 0, NowProvider? now})
    : assert(nodeId >= 0 && nodeId <= _maxNodeId),
      _nodeId = nodeId,
      _now = now ?? DateTime.now;

  static final DateTime epoch = DateTime.utc(2026);
  static const int _nodeBits = 10;
  static const int _sequenceBits = 12;
  static const int _maxNodeId = (1 << _nodeBits) - 1;
  static const int _maxSequence = (1 << _sequenceBits) - 1;
  static const int _nodeShift = _sequenceBits;
  static const int _timestampShift = _nodeBits + _sequenceBits;

  final int _nodeId;
  final NowProvider _now;

  /// 上次发号的时间戳（防回拨）。
  int _lastTimestamp = -1;

  /// 同一毫秒内已用的序列号。
  int _sequence = 0;

  /// 生成下一个 id。
  ///
  /// 时钟回拨处理：直接沿用 lastTimestamp 继续发号（保证单调不重复，
  /// 代价是时间戳略超前）；同一毫秒序列用尽则自旋等下一毫秒。
  int next() {
    var timestamp = _currentTimestamp();
    if (timestamp < _lastTimestamp) {
      timestamp = _lastTimestamp;
    }
    if (timestamp == _lastTimestamp) {
      _sequence = (_sequence + 1) & _maxSequence;
      if (_sequence == 0) {
        timestamp = _waitNextMillis(_lastTimestamp);
      }
    } else {
      _sequence = 0;
    }
    _lastTimestamp = timestamp;
    return (timestamp << _timestampShift) | (_nodeId << _nodeShift) | _sequence;
  }

  int _currentTimestamp() {
    return _now().toUtc().difference(epoch).inMilliseconds;
  }

  /// 忙等直到时间超过 lastTimestamp（序列耗尽时使用）。
  int _waitNextMillis(int lastTimestamp) {
    var timestamp = _currentTimestamp();
    while (timestamp <= lastTimestamp) {
      timestamp = _currentTimestamp();
    }
    return timestamp;
  }
}
