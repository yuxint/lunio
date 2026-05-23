enum SyncStatus { synced, pendingCreate, pendingUpdate, pendingDelete }

class SyncMetadata {
  const SyncMetadata({
    required this.status,
    required this.updatedAt,
    this.version = 1,
  });

  final SyncStatus status;
  final DateTime updatedAt;
  final int version;

  Map<String, Object?> toJson() {
    return {
      'status': status.name,
      'updatedAt': updatedAt.toIso8601String(),
      'version': version,
    };
  }

  factory SyncMetadata.fromJson(Map<String, Object?> json) {
    return SyncMetadata(
      status: SyncStatus.values.byName(json['status'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      version: json['version'] as int? ?? 1,
    );
  }
}
