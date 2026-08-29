// lib/models/monitoring_alert.dart

class MonitoringAlert {
  final String id;
  final String userId;
  final String? goalId;
  final String ruleCode; // W1_DAILY | W1_STREAK | W2 | W3 | W4 | W5
  final String title;
  final String body;
  final String deepLink;
  final String status; // 'pending' | 'sent' | 'failed'
  final Map<String, dynamic> meta;
  final DateTime? sentAt;
  final DateTime? clickedAt;
  final DateTime? readAt;
  final DateTime createdAt;

  const MonitoringAlert({
    required this.id,
    required this.userId,
    this.goalId,
    required this.ruleCode,
    required this.title,
    required this.body,
    required this.deepLink,
    required this.status,
    required this.meta,
    this.sentAt,
    this.clickedAt,
    this.readAt,
    required this.createdAt,
  });

  factory MonitoringAlert.fromMap(Map<String, dynamic> m) => MonitoringAlert(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        goalId: m['goal_id'] as String?,
        ruleCode: m['rule_code'] as String,
        title: m['title'] as String,
        body: m['body'] as String,
        deepLink: m['deep_link'] as String,
        status: m['status'] as String,
        meta: (m['meta'] as Map<String, dynamic>?) ?? const {},
        sentAt: m['sent_at'] != null ? DateTime.parse(m['sent_at'] as String) : null,
        clickedAt: m['clicked_at'] != null ? DateTime.parse(m['clicked_at'] as String) : null,
        readAt: m['read_at'] != null ? DateTime.parse(m['read_at'] as String) : null,
        createdAt: DateTime.parse(m['created_at'] as String),
      );

  bool get isUnread => readAt == null;

  /// Label singkat untuk ditampilkan di badge/kategori pada UI riwayat.
  String get ruleLabel {
    switch (ruleCode) {
      case 'W1_DAILY':
        return 'Pengingat harian';
      case 'W1_STREAK':
        return 'Tidak aktif 3 hari';
      case 'W2':
        return 'Deadline dekat';
      case 'W3':
        return 'Lewat deadline';
      case 'W4':
        return 'Frekuensi menurun';
      case 'W5':
        return 'Ketinggalan pace';
      default:
        return ruleCode;
    }
  }
}
