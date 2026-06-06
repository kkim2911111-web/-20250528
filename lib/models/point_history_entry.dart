import 'point_reservation_summary.dart';



/// 포인트 적립/차감 내역 (point_history)

class PointHistoryEntry {

  final String id;

  final int amount;

  final String? description;

  final String? type;

  final String? reservationId;

  final int? balanceAfter;

  final DateTime? createdAt;

  final DateTime? expiresAt;

  const PointHistoryEntry({
    required this.id,
    required this.amount,
    this.description,
    this.type,
    this.reservationId,
    this.balanceAfter,
    this.createdAt,
    this.expiresAt,
  });



  factory PointHistoryEntry.fromMap(Map<String, dynamic> map) {

    return PointHistoryEntry(

      id: map['id'].toString(),

      amount: _readAmount(map),

      description: (map['description'] ??

              map['reason'] ??

              map['memo'] ??

              map['title'])

          ?.toString(),

      type: map['type']?.toString(),

      reservationId: map['reservation_id']?.toString(),

      balanceAfter: (map['balance_after'] as num?)?.toInt(),

      createdAt: _parseDate(map['created_at']),
      expiresAt: _parseDate(
        map['expires_at'] ?? map['expired_at'] ?? map['valid_until'],
      ),
    );
  }



  static int _readAmount(Map<String, dynamic> map) {

    final amount = (map['amount'] as num?)?.toInt();

    final points = (map['points'] as num?)?.toInt();

    final delta = (map['delta'] as num?)?.toInt();

    final type = map['type']?.toString().toLowerCase().trim();
    final isUse = type == 'use' || type == 'debit' || type == 'spend';
    final isRestore = type == 'restore' || type == 'refund';

    if (isRestore) {
      final raw = amount ?? points ?? delta ?? 0;
      return raw < 0 ? raw.abs() : raw;
    }

    if (isUse) {

      if (amount != null && amount != 0) return amount < 0 ? amount : -amount.abs();

      if (points != null && points != 0) {

        return points < 0 ? points : -points.abs();

      }

      if (delta != null && delta != 0) {

        return delta < 0 ? delta : -delta.abs();

      }

      return amount ?? points ?? delta ?? 0;

    }



    if (amount != null && amount != 0) return amount;

    if (points != null && points != 0) return points;

    if (delta != null && delta != 0) return delta;

    return amount ?? points ?? delta ?? 0;

  }



  static DateTime? _parseDate(Object? value) {

    if (value == null) return null;

    if (value is DateTime) return value.toLocal();

    return DateTime.tryParse(value.toString())?.toLocal();

  }



  bool get isEarned => amount > 0;



  bool get isCancelled => type?.toLowerCase().trim() == 'cancel';



  bool get isUseType {
    final t = type?.toLowerCase().trim();
    return t == 'use' || t == 'debit' || t == 'spend';
  }

  bool get isRestoreType {
    final t = type?.toLowerCase().trim();
    return t == 'restore' || t == 'refund';
  }

  bool get isEarnRentalType => type?.toLowerCase().trim() == 'earn_rental';

  bool get isEarnSignupType => type?.toLowerCase().trim() == 'earn_signup';

  bool get isExpireType => type?.toLowerCase().trim() == 'expire';

  bool get showsPointExpiry => isEarnRentalType || isEarnSignupType;

  int? get daysUntilExpiry {
    final end = expiresAt;
    if (end == null) return null;
    final today = DateTime.now();
    final endDate = DateTime(end.year, end.month, end.day);
    final todayDate = DateTime(today.year, today.month, today.day);
    return endDate.difference(todayDate).inDays;
  }

  /// 차감(포인트 사용) — type=use 또는 음수 금액 (복구·취소·만료 제외)
  bool get isSpendEntry =>
      !isRestoreType &&
      !isCancelled &&
      !isExpireType &&
      (isUseType || amount < 0);



  /// description 끝의 예약 번호 (복합 문구 지원)

  String? get legacyReservationIdFromDescription {

    final parts = _descriptionParts;

    if (parts.isEmpty) return null;

    for (var i = parts.length - 1; i >= 0; i--) {

      if (RegExp(r'^\d+$').hasMatch(parts[i])) return parts[i];

    }

    final legacy = RegExp(

      r'(?:예약\s*결제\s*사용|포인트\s*사용)\s*·\s*(\d+)\s*$',

    ).firstMatch(description?.trim() ?? '');

    return legacy?.group(1);

  }



  List<String> get _descriptionParts {

    final d = description?.trim();

    if (d == null || d.isEmpty) return const [];

    return d.split('·').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  }



  String? get resolvedReservationId {

    if (reservationId != null && reservationId!.isNotEmpty) {

      return reservationId;

    }

    return legacyReservationIdFromDescription;

  }



  String? _spendDisplayTitle(Map<String, PointReservationSummary>? reservationMeta) {

    final rid = resolvedReservationId;

    if (rid != null && reservationMeta != null) {

      final meta = reservationMeta[rid];

      if (meta != null) {

        return '포인트 사용 · ${meta.vehicleName}';

      }

    }



    final parts = List<String>.from(_descriptionParts);

    while (parts.isNotEmpty && parts.first == '포인트 사용') {

      parts.removeAt(0);

    }

    if (parts.isEmpty) return '포인트 사용';



    final last = parts.last;

    if (RegExp(r'^\d+$').hasMatch(last)) {

      if (parts.length >= 2) {

        return '포인트 사용 · ${parts[parts.length - 2]}';

      }

      return '포인트 사용 · #$last';

    }

    return '포인트 사용 · ${parts.join(' · ')}';

  }



  /// 포인트 내역 카드 — 차량명(복구 항목은 「예약 취소」)
  String displayVehicleName(
    Map<String, PointReservationSummary>? reservationMeta,
  ) {
    if (isRestoreType) return '예약 취소';

    final rid = resolvedReservationId;
    if (rid != null && reservationMeta != null) {
      final meta = reservationMeta[rid];
      if (meta != null && meta.vehicleName.trim().isNotEmpty) {
        return meta.vehicleName.trim();
      }
    }

    const skipPrefixes = {
      '포인트 사용',
      '포인트 적립',
      '사용 포인트 복구',
      '예약 취소로 인한 포인트 복구',
      '예약 취소',
      '예약 결제 사용',
      '이용 적립',
      '가입 적립',
      '포인트 만료',
      '포인트 취소',
    };

    for (final part in _descriptionParts.reversed) {
      if (RegExp(r'^\d+$').hasMatch(part)) continue;
      if (skipPrefixes.contains(part)) continue;
      if (part.contains('시간')) continue;
      return part;
    }

    return '—';
  }

  /// 적립/사용/복구 뱃지 구분
  PointHistoryBadgeKind get badgeKind {
    if (isCancelled) return PointHistoryBadgeKind.cancelled;
    if (isRestoreType) return PointHistoryBadgeKind.restore;
    if (isSpendEntry || isUseType) return PointHistoryBadgeKind.use;
    if (isExpireType) return PointHistoryBadgeKind.expire;
    if (isEarned) return PointHistoryBadgeKind.earn;
    return PointHistoryBadgeKind.none;
  }

  /// 예약 메타 또는 description 기반 표시 문구

  String displayLabel(Map<String, PointReservationSummary>? reservationMeta) {
    if (isRestoreType) return '예약 취소';

    if (isSpendEntry) {
      return _spendDisplayTitle(reservationMeta) ?? '포인트 사용';
    }



    final rid = resolvedReservationId;

    if (rid != null && reservationMeta != null) {

      final meta = reservationMeta[rid];

      if (meta != null) return meta.lineLabel;

    }



    final d = description?.trim();

    if (d != null && d.isNotEmpty && !RegExp(r'^\d+$').hasMatch(d)) {

      return d;

    }



    return typeLabel;

  }



  String get typeLabel {

    if (isSpendEntry) return '포인트 사용';

    if (description != null && description!.trim().isNotEmpty) {

      final d = description!.trim();

      if (!RegExp(r'^\d+$').hasMatch(d)) return d;

    }

    final t = type?.toLowerCase().trim();

    switch (t) {

      case 'cancel':

        return '포인트 취소';

      case 'earn':

      case 'credit':

      case 'reward':

        return '포인트 적립';

      case 'use':
      case 'debit':
      case 'spend':
        return '포인트 사용';
      case 'restore':
      case 'refund':
        return '예약 취소';
      case 'expire':
        return '포인트 만료';
      case 'earn_signup':
        return '가입 적립';
      case 'earn_rental':
        return '이용 적립';
      default:
        return isEarned ? '포인트 적립' : '포인트 사용';
    }
  }
}

/// 적립 포인트 만료일 표시 (earn_rental · earn_signup)
class PointExpiryDisplay {
  final String text;
  final PointExpiryTone tone;

  const PointExpiryDisplay({required this.text, required this.tone});

  static PointExpiryDisplay? forEntry(PointHistoryEntry entry) {
    if (!entry.showsPointExpiry || entry.expiresAt == null) return null;
    final expires = entry.expiresAt!;
    final days = entry.daysUntilExpiry;
    final formatted = _formatDate(expires);

    if (days != null && days < 0) {
      return PointExpiryDisplay(
        text: '~$formatted 까지 (만료됨)',
        tone: PointExpiryTone.muted,
      );
    }
    if (days != null && days <= 7) {
      return PointExpiryDisplay(
        text: '~$formatted 까지',
        tone: PointExpiryTone.urgentRed,
      );
    }
    if (days != null && days <= 30) {
      return PointExpiryDisplay(
        text: '~$formatted 까지',
        tone: PointExpiryTone.urgentOrange,
      );
    }
    return PointExpiryDisplay(
      text: '~$formatted 까지',
      tone: PointExpiryTone.normal,
    );
  }

  static String _formatDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y.$m.$day';
  }
}

enum PointExpiryTone { normal, urgentOrange, urgentRed, muted }

enum PointHistoryBadgeKind { earn, use, restore, expire, cancelled, none }


