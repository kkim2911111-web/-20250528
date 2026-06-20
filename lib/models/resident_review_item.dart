class ResidentReviewItem {
  final String userId;
  final String fullName;
  final String? building;
  final String? unit;
  final DateTime? requestedAt;

  const ResidentReviewItem({
    required this.userId,
    required this.fullName,
    this.building,
    this.unit,
    this.requestedAt,
  });

  String get dongHoLabel {
    final parts = <String>[];
    if (building != null && building!.trim().isNotEmpty) {
      parts.add('${building!.trim()}동');
    }
    if (unit != null && unit!.trim().isNotEmpty) {
      parts.add('${unit!.trim()}호');
    }
    return parts.isEmpty ? '동·호 미등록' : parts.join(' ');
  }

  factory ResidentReviewItem.fromMap(Map<String, dynamic> map) {
    DateTime? requestedAt;
    final raw = map['requested_at'];
    if (raw != null) {
      requestedAt = DateTime.tryParse(raw.toString())?.toLocal();
    }

    return ResidentReviewItem(
      userId: map['user_id']?.toString() ?? '',
      fullName: map['full_name']?.toString().trim().isNotEmpty == true
          ? map['full_name']!.toString()
          : '이름 미등록',
      building: map['building']?.toString(),
      unit: map['unit']?.toString(),
      requestedAt: requestedAt,
    );
  }
}
