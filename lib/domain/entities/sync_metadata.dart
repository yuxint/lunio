// 云同步元数据：每张业务表都带的三个审计字段（为未来云同步预留）。
//
// 当前是纯本地 App：所有数据 status 恒为 synced，没有任何同步消费者；
// 但字段已在建表时落库，并随备份 JSON 一起导出导入（嵌套 "sync" 对象），
// 未来接云同步时可直接利用 pendingCreate/pendingUpdate/pendingDelete
// 做增量上传（≈ 常见的"脏标记 + 版本号"同步方案）。
enum SyncStatus { synced, pendingCreate, pendingUpdate, pendingDelete }

class SyncMetadata {
  const SyncMetadata({
    required this.status,
    required this.updatedAt,
    this.version = 1,
  });

  /// 同步状态标记。本地写入时全部记 synced。
  final SyncStatus status;

  /// 最后更新时间（时间戳，随备份导出）。
  final DateTime updatedAt;

  /// 乐观锁版本号，默认 1。当前无消费者。
  final int version;

  /// 序列化为备份 JSON 里的 "sync" 嵌套对象。
  Map<String, Object?> toJson() {
    return {
      'status': status.name,
      'updatedAt': updatedAt.toIso8601String(),
      'version': version,
    };
  }

  /// 从备份 JSON 还原。version 缺省时回退 1（兼容旧备份）。
  factory SyncMetadata.fromJson(Map<String, Object?> json) {
    return SyncMetadata(
      status: SyncStatus.values.byName(json['status'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      version: json['version'] as int? ?? 1,
    );
  }
}
