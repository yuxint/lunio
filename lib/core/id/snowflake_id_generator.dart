typedef NowProvider = DateTime Function();

class SnowflakeIdGenerator {
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
  int _lastTimestamp = -1;
  int _sequence = 0;

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

  int _waitNextMillis(int lastTimestamp) {
    var timestamp = _currentTimestamp();
    while (timestamp <= lastTimestamp) {
      timestamp = _currentTimestamp();
    }
    return timestamp;
  }
}
