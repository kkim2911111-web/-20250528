class HomeBanner {
  final int id;
  final String subTitle;
  final String mainTitle;
  final String description;
  final bool isActive;
  final DateTime? createdAt;

  const HomeBanner({
    required this.id,
    required this.subTitle,
    required this.mainTitle,
    required this.description,
    this.isActive = true,
    this.createdAt,
  });

  factory HomeBanner.fromMap(Map<String, dynamic> map) {
    return HomeBanner(
      id: (map['id'] as num).toInt(),
      subTitle: map['sub_title']?.toString() ?? '',
      mainTitle: map['main_title']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
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
