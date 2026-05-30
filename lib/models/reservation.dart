import 'package:intl/intl.dart';

import 'vehicle.dart';

/// 예약 + 대여·반납 정보
class Reservation {
  final String id;
  final String userId;
  final String vehicleId;
  final DateTime? startAt;
  final DateTime? endAt;
  final int totalPrice;
  final String status;
  final String? paymentKey;
  final String? paymentStatus;
  final String? orderId;
  final DateTime? rentalStartedAt;
  final DateTime? returnedAt;
  final DateTime? actualEndAt;
  final String? returnType;
  final DateTime? earlyReturnConfirmedAt;
  final List<String> pickupPhotos;
  final List<String> returnPhotos;
  final int? mileageStart;
  final int? mileageEnd;
  final String? fuelLevelStart;
  final String? fuelLevelEnd;
  final bool isAccident;
  final String? accidentNote;
  final bool doorUnlocked;
  final Vehicle? vehicle;

  const Reservation({
    required this.id,
    required this.userId,
    required this.vehicleId,
    this.startAt,
    this.endAt,
    required this.totalPrice,
    required this.status,
    this.paymentKey,
    this.paymentStatus,
    this.orderId,
    this.rentalStartedAt,
    this.returnedAt,
    this.actualEndAt,
    this.returnType,
    this.earlyReturnConfirmedAt,
    this.pickupPhotos = const [],
    this.returnPhotos = const [],
    this.mileageStart,
    this.mileageEnd,
    this.fuelLevelStart,
    this.fuelLevelEnd,
    this.isAccident = false,
    this.accidentNote,
    this.doorUnlocked = false,
    this.vehicle,
  });

  factory Reservation.fromMap(Map<String, dynamic> map) {
    final vehicleRaw = map['vehicles'];
    Vehicle? vehicle;
    if (vehicleRaw is Map) {
      vehicle = Vehicle.fromMap(Map<String, dynamic>.from(vehicleRaw));
    }

    return Reservation(
      id: map['id'].toString(),
      userId: map['user_id']?.toString() ?? '',
      vehicleId: map['vehicle_id']?.toString() ?? '',
      startAt: _parseDate(map['start_at'] ?? map['start_time']),
      endAt: _parseDate(map['end_at'] ?? map['end_time']),
      totalPrice: (map['total_price'] as num?)?.toInt() ?? 0,
      status: map['status']?.toString() ?? 'pending',
      paymentKey: map['payment_key']?.toString(),
      paymentStatus: map['payment_status']?.toString(),
      orderId: map['order_id']?.toString(),
      rentalStartedAt: _parseDate(map['rental_started_at']),
      returnedAt: _parseDate(map['returned_at']),
      actualEndAt: _parseDate(map['actual_end_at']),
      returnType: map['return_type']?.toString(),
      earlyReturnConfirmedAt: _parseDate(map['early_return_confirmed_at']),
      pickupPhotos: _parseStringList(map['pickup_photos']),
      returnPhotos: _parseStringList(map['return_photos']),
      mileageStart: (map['mileage_start'] as num?)?.toInt(),
      mileageEnd: (map['mileage_end'] as num?)?.toInt(),
      fuelLevelStart: map['fuel_level_start']?.toString(),
      fuelLevelEnd: map['fuel_level_end']?.toString(),
      isAccident: map['is_accident'] == true,
      accidentNote: map['accident_note']?.toString(),
      doorUnlocked: map['door_unlocked'] == true,
      vehicle: vehicle,
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  static List<String> _parseStringList(Object? value) {
    if (value is List) {
      return value.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    }
    return const [];
  }

  bool get canStartRental =>
      (status == 'confirmed' || status == 'pending') &&
      !isEffectivelyFinished;

  bool get canUseVehicle => status == 'in_use';

  bool get canReturn => status == 'in_use';

  /// 예약 종료 시각 전 중도반납 가능
  bool get canEarlyReturn {
    if (status != 'in_use') return false;
    final end = _end;
    if (end == null) return false;
    return DateTime.now().isBefore(end);
  }

  bool get isEarlyReturnType => returnType == 'early';

  bool get isFinished => status == 'returned' || status == 'completed';

  bool get isCancelled => status == 'cancelled';

  bool get isPaid =>
      paymentStatus == 'paid' ||
      (paymentKey != null && paymentKey!.trim().isNotEmpty);

  bool get isCancellableStatus =>
      status == 'confirmed' || status == 'pending';

  /// 대여 시작 전인지
  bool get isBeforeRentalStart {
    final start = _start;
    if (start == null) return true;
    return DateTime.now().isBefore(start);
  }

  /// 취소 버튼 표시 — 이용 대기 중 결제/확정 예약
  bool get canShowCancelButton =>
      !isCancelled &&
      !isFinished &&
      status != 'in_use' &&
      isCancellableStatus &&
      isBeforeRentalStart;

  /// 예약 취소 가능 — 대여 시작 1시간(60분) 전까지만 (미결제 pending 은 시작 전이면 가능)
  bool get canCancel {
    if (!canShowCancelButton) return false;
    if (status == 'pending' && !isPaid) return true;
    final start = _start;
    if (start == null) return true;
    return DateTime.now().add(const Duration(hours: 1)).isBefore(start);
  }

  /// 대여 1시간(60분) 이내로 취소 불가
  bool get isCancelBlocked =>
      canShowCancelButton && !canCancel;

  DateTime? get _start => startAt;
  DateTime? get _end => endAt;

  /// 예약 이용 시간대 내 (start ~ end)
  bool get isWithinUsageWindow {
    final start = _start;
    final end = _end;
    if (start == null || end == null) return false;
    final now = DateTime.now();
    return !now.isBefore(start) && !now.isAfter(end);
  }

  /// 이용 시작 전 (시작 시각 없으면 대기로 분류)
  bool get isBeforeUsageWindow {
    final start = _start;
    if (start == null) return true;
    return DateTime.now().isBefore(start);
  }

  /// 이용 종료 시각 경과
  bool get isUsageTimeExpired {
    final end = _end;
    if (end == null) return false;
    return DateTime.now().isAfter(end);
  }

  bool get isActiveStatus =>
      status == 'confirmed' || status == 'in_use' || status == 'pending';

  /// DB completed/returned 또는 (in_use 제외) 이용시간 경과
  bool get isEffectivelyFinished =>
      isFinished ||
      isCancelled ||
      (isActiveStatus && status != 'in_use' && isUsageTimeExpired);

  /// 마이페이지 이용내역 — 취소·완료·시간 경과(미운행 확정 예약)
  bool get isInUsageHistory => isEffectivelyFinished;

  /// 운행 중 — in_use 또는 이용 시간대 내
  bool get isOperating =>
      status == 'in_use' ||
      (!isEffectivelyFinished &&
          isActiveStatus &&
          _start != null &&
          isWithinUsageWindow);

  /// 이용 대기 — 시작 전 (또는 시작 시각 미설정)
  bool get isWaiting =>
      !isEffectivelyFinished &&
      isActiveStatus &&
      !isOperating &&
      (_start == null || isBeforeUsageWindow);

  /// 예약 종료 시각이 지나지 않았는지
  bool get isNotExpired => !isUsageTimeExpired;

  /// 스마트키 — 대여 중·이용 대기·이용 시간대 내 활성 예약
  bool get isSmartKeyEligible =>
      !isEffectivelyFinished &&
      isActiveStatus &&
      (status == 'in_use' || isOperating || isWaiting);

  DateTime get sortByStart => startAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  /// 홈 이용 시간대 — 05/30 22:00 - 05/31 10:00 / 금일 09:00 - 18:00
  String? get usagePeriodLabel {
    final start = startAt;
    final end = endAt;
    if (start == null || end == null) return null;
    return formatUsagePeriod(start, end);
  }

  static String formatUsagePeriod(DateTime start, DateTime end) {
    final time = DateFormat('HH:mm');
    final date = DateFormat('MM/dd');
    final startDay = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (startDay != endDay) {
      return '${date.format(start)} ${time.format(start)} - '
          '${date.format(end)} ${time.format(end)}';
    }

    if (startDay == today) {
      return '금일 ${time.format(start)} - ${time.format(end)}';
    }

    return '${date.format(start)} ${time.format(start)} - ${time.format(end)}';
  }

  /// 홈·내 예약 — 대여 시작까지 남은 시간 문구
  String get timeUntilStartLabel {
    final start = startAt;
    if (start == null) return '예약 확정';
    final diff = start.difference(DateTime.now());
    if (diff.isNegative) return '이용 가능 시간';
    if (diff.inDays >= 1) return '${diff.inDays}일 후 시작';
    if (diff.inHours >= 1) return '${diff.inHours}시간 후 시작';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}분 후 시작';
    return '곧 시작';
  }

  String get displayStatusLabel {
    if (isCancelled) return '예약 취소';
    if (isEffectivelyFinished && !isFinished) return '이용 종료';
    if (isOperating) return '운행 중';
    if (isWaiting) return '이용 대기';
    if (isFinished) return '이용 완료';
    return statusLabel;
  }

  String get statusLabel {
    switch (status) {
      case 'pending':
        return '대기';
      case 'confirmed':
        return '예약 확정';
      case 'in_use':
        return '대여 중';
      case 'returned':
        return isEarlyReturnType ? '중도반납 완료' : '반납 완료';
      case 'completed':
        return '이용 완료';
      case 'cancelled':
        return '예약 취소';
      default:
        return status;
    }
  }
}

/// 중도반납 안내
abstract final class EarlyReturnMessages {
  static const confirmTitle = '중도반납';
  static const confirmBody =
      '중도반납 하시겠습니까?\n남은 시간에 대한 환불은 불가합니다.';
  static const needStartRental =
      '대여 시작 후 반납할 수 있습니다.\n차량 이용 화면에서 대여를 시작해주세요.';
  static const success = '중도반납이 완료되었습니다.';
}

/// 예약 취소 안내 문구
abstract final class ReservationCancelMessages {
  static const success = '예약취소가 완료되었습니다.';
  static const tooLate = '대여예약 1시간(60분)이전에는 예약취소가 불가능합니다';
  static const waitingGuide =
      '이용 시작 전까지「예약취소」를 누르면 결제 금액이 전액 환불됩니다. '
      '단, 대여예약 1시간(60분) 이내에는 예약취소가 불가능합니다.';
}
