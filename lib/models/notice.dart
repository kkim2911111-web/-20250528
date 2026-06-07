class Notice {
  final String id;
  final String? complexId;
  final String title;
  final String content;
  final bool isActive;
  final DateTime? createdAt;

  const Notice({
    required this.id,
    this.complexId,
    required this.title,
    required this.content,
    this.isActive = true,
    this.createdAt,
  });

  bool get isGlobal => complexId == null || complexId!.isEmpty;

  factory Notice.fromMap(Map<String, dynamic> map) {
    return Notice(
      id: map['id']?.toString() ?? '',
      complexId: map['complex_id']?.toString(),
      title: map['title']?.toString() ?? '',
      content: map['content']?.toString() ?? '',
      isActive: map['is_active'] == true,
      createdAt: _parseDate(map['created_at']),
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    return DateTime.tryParse(value.toString())?.toLocal();
  }
}
