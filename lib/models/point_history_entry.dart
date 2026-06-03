/// 포인트 적립/차감 내역 (point_history)
class PointHistoryEntry {
  final String id;
  final int amount;
  final String? description;
  final String? type;
  final int? balanceAfter;
  final DateTime? createdAt;

  const PointHistoryEntry({
    required this.id,
    required this.amount,
    this.description,
    this.type,
    this.balanceAfter,
    this.createdAt,
  });

  factory PointHistoryEntry.fromMap(Map<String, dynamic> map) {
    return PointHistoryEntry(
      id: map['id'].toString(),
      amount: (map['amount'] as num?)?.toInt() ??
          (map['points'] as num?)?.toInt() ??
          (map['delta'] as num?)?.toInt() ??
          0,
      description: (map['description'] ??
              map['reason'] ??
              map['memo'] ??
              map['title'])
          ?.toString(),
      type: map['type']?.toString(),
      balanceAfter: (map['balance_after'] as num?)?.toInt(),
      createdAt: _parseDate(map['created_at']),
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  bool get isEarned => amount > 0;

  String get typeLabel {
    if (description != null && description!.trim().isNotEmpty) {
      return description!.trim();
    }
    final t = type?.toLowerCase();
    switch (t) {
      case 'earn':
      case 'credit':
      case 'reward':
        return '포인트 적립';
      case 'use':
      case 'debit':
      case 'spend':
        return '포인트 사용';
      default:
        return isEarned ? '포인트 적립' : '포인트 사용';
    }
  }
}
