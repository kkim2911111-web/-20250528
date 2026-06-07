class InboxNotification {
  final String id;
  final String title;
  final String body;
  final String type;
  final String? reservationId;
  final bool isRead;
  final DateTime? createdAt;

  const InboxNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    this.reservationId,
    this.isRead = false,
    this.createdAt,
  });

  factory InboxNotification.fromMap(Map<String, dynamic> map) {
    return InboxNotification(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      body: map['body']?.toString() ?? '',
      type: map['type']?.toString() ?? '',
      reservationId: map['reservation_id']?.toString(),
      isRead: map['is_read'] == true,
      createdAt: _parseDate(map['created_at']),
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    return DateTime.tryParse(value.toString())?.toLocal();
  }
}
