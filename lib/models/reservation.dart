import 'package:intl/intl.dart';

import '../utils/cancel_reason.dart';
import '../utils/rental_pricing.dart';
import '../utils/reservation_display.dart';
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
  final DateTime? cancelledAt;
  final List<String> pickupPhotos;
  final List<String> returnPhotos;
  final int? mileageStart;
  final int? mileageEnd;
  final String? fuelLevelStart;
  final String? fuelLevelEnd;
  final bool isAccident;
  final String? accidentNote;
  final bool doorUnlocked;
  final bool photosUploaded;
  final bool licenseVerified;
  final Vehicle? vehicle;
  final String? contractContent;
  final String? secondDriverName;
  final String? secondDriverLicense;
  final bool isNoShow;
  final bool isOverdue;
  final int? overdueOverageAmount;
  final int? overdueOverageHours;
  final bool overdueOverageCharged;
  final int extensionPriceTotal;
  final String? reservationNumber;
  final RentalType? rentalType;
  final int refundAmount;
  final String? cancelReason;

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
    this.cancelledAt,
    this.pickupPhotos = const [],
    this.returnPhotos = const [],
    this.mileageStart,
    this.mileageEnd,
    this.fuelLevelStart,
    this.fuelLevelEnd,
    this.isAccident = false,
    this.accidentNote,
    this.doorUnlocked = false,
    this.photosUploaded = false,
    this.licenseVerified = false,
    this.vehicle,
    this.contractContent,
    this.secondDriverName,
    this.secondDriverLicense,
    this.isNoShow = false,
    this.isOverdue = false,
    this.overdueOverageAmount,
    this.overdueOverageHours,
    this.overdueOverageCharged = false,
    this.extensionPriceTotal = 0,
    this.reservationNumber,
    this.rentalType,
    this.refundAmount = 0,
    this.cancelReason,
  });

  Reservation copyWith({Vehicle? vehicle}) {
    return Reservation(
      id: id,
      userId: userId,
      vehicleId: vehicleId,
      startAt: startAt,
      endAt: endAt,
      totalPrice: totalPrice,
      status: status,
      paymentKey: paymentKey,
      paymentStatus: paymentStatus,
      orderId: orderId,
      rentalStartedAt: rentalStartedAt,
      returnedAt: returnedAt,
      actualEndAt: actualEndAt,
      cancelledAt: cancelledAt,
      pickupPhotos: pickupPhotos,
      returnPhotos: returnPhotos,
      mileageStart: mileageStart,
      mileageEnd: mileageEnd,
      fuelLevelStart: fuelLevelStart,
      fuelLevelEnd: fuelLevelEnd,
      isAccident: isAccident,
      accidentNote: accidentNote,
      doorUnlocked: doorUnlocked,
      photosUploaded: photosUploaded,
      licenseVerified: licenseVerified,
      vehicle: vehicle ?? this.vehicle,
      contractContent: contractContent,
      secondDriverName: secondDriverName,
      secondDriverLicense: secondDriverLicense,
      isNoShow: isNoShow,
      isOverdue: isOverdue,
      overdueOverageAmount: overdueOverageAmount,
      overdueOverageHours: overdueOverageHours,
      overdueOverageCharged: overdueOverageCharged,
      extensionPriceTotal: extensionPriceTotal,
      reservationNumber: reservationNumber,
      rentalType: rentalType,
      refundAmount: refundAmount,
      cancelReason: cancelReason,
    );
  }

  bool get hasSecondDriver {
    final name = secondDriverName?.trim();
    return name != null && name.isNotEmpty;
  }

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
      status: normalizeStatus(map['status']),
      paymentKey: map['payment_key']?.toString(),
      paymentStatus: map['payment_status']?.toString(),
      orderId: map['order_id']?.toString(),
      rentalStartedAt: _parseDate(map['rental_started_at']),
      returnedAt: _parseDate(map['returned_at']),
      actualEndAt: _parseDate(map['actual_end_at']),
      cancelledAt: _parseDate(map['cancelled_at'] ?? map['updated_at']),
      pickupPhotos: _parseStringList(map['pickup_photos']),
      returnPhotos: _parseStringList(map['return_photos']),
      mileageStart: (map['mileage_start'] as num?)?.toInt(),
      mileageEnd: (map['mileage_end'] as num?)?.toInt(),
      fuelLevelStart: map['fuel_level_start']?.toString(),
      fuelLevelEnd: map['fuel_level_end']?.toString(),
      isAccident: map['is_accident'] == true,
      accidentNote: map['accident_note']?.toString(),
      doorUnlocked: map['door_unlocked'] == true,
      photosUploaded: map['photos_uploaded'] == true,
      licenseVerified: map['license_verified'] == true,
      vehicle: vehicle,
      contractContent: map['contract_content']?.toString(),
      secondDriverName: map['second_driver_name']?.toString(),
      secondDriverLicense: map['second_driver_license']?.toString(),
      isNoShow: map['is_no_show'] == true,
      isOverdue: map['is_overdue'] == true,
      overdueOverageAmount: (map['overdue_overage_amount'] as num?)?.toInt(),
      overdueOverageHours: (map['overdue_overage_hours'] as num?)?.toInt(),
      overdueOverageCharged: map['overdue_overage_charged'] == true,
      extensionPriceTotal: (map['extension_price_total'] as num?)?.toInt() ?? 0,
      reservationNumber: map['reservation_number']?.toString(),
      rentalType: RentalType.fromDb(map['rental_type']?.toString()),
      refundAmount: (map['refund_amount'] as num?)?.toInt() ?? 0,
      cancelReason: map['cancel_reason']?.toString(),
    );
  }

  /// 환불 견적·정책 계산용 결제액 (서버는 payment_orders 우선).
  int get paidAmount => totalPrice;

  bool get hasContractContent {
    final c = contractContent?.trim();
    return c != null && c.isNotEmpty;
  }

  /// 계약서 보기 — 대여 중(in_use)·반납 처리(returned)·이용 완료(completed)
  bool get canViewContract =>
      status == 'in_use' || status == 'returned' || status == 'completed';

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

  /// DB/JSON status 정규화 (공백·대소문자·in-use 변형)
  static String normalizeStatus(Object? raw) {
    final s = raw?.toString().trim().toLowerCase() ?? '';
    if (s.isEmpty) return 'pending';
    if (s == 'in use' || s == 'in-use') return 'in_use';
    return s;
  }

  bool get isInUse => status == 'in_use';

  /// 연장 신청 가능 구간 — in_use 이고 종료 1시간 전 ~ 종료 시각 전
  bool get isWithinExtensionRequestWindow {
    if (!isInUse) return false;
    final end = endAt;
    if (end == null) return false;
    final now = DateTime.now();
    if (!now.isBefore(end)) return false;
    final windowStart = end.subtract(const Duration(hours: 1));
    return !now.isBefore(windowStart);
  }

  /// 대여 전 필수 사진(6장) 업로드 완료 여부
  static const minPickupPhotos = 6;

  bool get hasPickupPhotosComplete =>
      pickupPhotos.length >= minPickupPhotos;

  /// 사진·면허 플래그 + 실제 pickup_photos 일치
  bool get isRentalPhotosReady =>
      photosUploaded && hasPickupPhotosComplete;

  /// 운행시작 버튼 활성화 — 예약 시작 10분 전부터
  static const rentalStartLeadTime = Duration(minutes: 10);

  /// 예약 시작 10분 전 이전 (버튼 비활성)
  bool get isTooEarlyForRentalStart {
    final start = _start;
    if (start == null) return false;
    return DateTime.now().isBefore(start.subtract(rentalStartLeadTime));
  }

  /// 운행시작 가능 시간대 — 시작 10분 전 ~ 종료 시각
  bool get isRentalStartWindowOpen {
    if (isUsageTimeExpired) return false;
    return !isTooEarlyForRentalStart;
  }

  /// 운행시작 버튼 표시 (비활성 포함)
  bool get showRentalStartButton =>
      (status == 'confirmed' || status == 'pending') &&
      !isEffectivelyFinished &&
      !isUsageTimeExpired;

  bool get canStartRental => showRentalStartButton && isRentalStartWindowOpen;

  bool get canUseVehicle => isInUse;

  bool get canReturn => isInUse;

  bool get isFinished => status == 'returned' || status == 'completed';

  bool get isCancelled => status == 'cancelled';

  bool get isVehicleNotReturned =>
      isVehicleNotReturnedCancelReason(cancelReason);

  bool get isOverdueConflict =>
      isOverdueConflictCancelReason(cancelReason);

  bool get isConflictFullRefund =>
      isConflictFullRefundCancelReason(cancelReason);

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

  /// 예약 취소 가능 — 대여 시작 전이면 언제든 (환불율은 별도 정책)
  bool get canCancel => canShowCancelButton;

  /// 예약취소 버튼 표시 — 이용 대기(pending/confirmed), 대여 시작 전
  bool get shouldShowCancelButton => canShowCancelButton;

  DateTime? get _start => startAt;
  DateTime? get _end => endAt;

  /// UI — 실제 대여/반납 시각 우선
  DateTime? get displayRentalStartAt => resolveRentalStartDisplay(
        rentalStartedAt: rentalStartedAt,
        scheduledStartAt: startAt,
      );

  DateTime? get displayRentalEndAt => resolveRentalEndDisplay(
        returnedAt: returnedAt,
        actualEndAt: actualEndAt,
        scheduledEndAt: endAt,
      );

  String get reservationNumberLabel => resolveReservationNumberLabel(
        reservationNumber: reservationNumber,
        rawId: id,
        orderId: orderId,
      );

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

  /// DB completed/returned/cancelled 또는 미운행 예약의 종료 시각 경과
  /// (in_use는 status·is_overdue로 별도 처리 — end_at만으로 종료 처리하지 않음)
  bool get isEffectivelyFinished =>
      isFinished ||
      isCancelled ||
      ((status == 'confirmed' || status == 'pending') && isUsageTimeExpired);

  /// 마이페이지 이용내역 — 취소·완료·미운행 시간 경과
  bool get isInUsageHistory => isEffectivelyFinished;

  /// 이용내역 화면 전용 — 반납 지연(in_use + is_overdue) 포함
  bool get appearsInUsageHistoryScreen =>
      isInUsageHistory || isReturnOverdue;

  /// 이용내역 — 이용완료 탭 (취소·반납 지연 제외, DB 완료만)
  bool get isUsageHistoryCompleted =>
      !isCancelled &&
      !isReturnOverdue &&
      (status == 'completed' || status == 'returned');

  /// 운행 중 — in_use 또는 이용 시간대 내
  bool get isOperating =>
      isInUse ||
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

  /// 스마트키 문열림 — 예약 시작 10분 전부터
  bool get canUnlockDoor => !isTooEarlyForRentalStart;

  /// 스마트키 — 대여 중(in_use)만
  bool get isSmartKeyEligible => isInUse && !isEffectivelyFinished;

  DateTime get sortByStart => startAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  /// 홈 이용 시간대 — 05/30 22:00 - 05/31 10:00 / 금일 09:00 - 18:00
  String? get usagePeriodLabel {
    final start = displayRentalStartAt;
    final end = displayRentalEndAt;
    if (start == null || end == null) return null;
    return formatUsagePeriod(start, end);
  }

  /// 예약·대여 기간 라벨 (30/35/38일 → 1개월·1개월 5일 등)
  String? get rentalDurationLabel {
    final start = startAt;
    final end = endAt;
    if (start == null || end == null || !end.isAfter(start)) return null;
    return RentalPricing.formatDurationLabelFromInterval(start: start, end: end);
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
    if (diff.inHours >= 1) {
      final hours = diff.inHours;
      final minutes = diff.inMinutes % 60;
      if (minutes == 0) return '${hours}시간 후 시작';
      return '${hours}시간 ${minutes}분 후 시작';
    }
    if (diff.inMinutes >= 1) return '${diff.inMinutes}분 후 시작';
    return '곧 시작';
  }

  String get displayStatusLabel {
    if (isConflictFullRefund) return vehicleNotReturnedStatusBadgeLabel;
    if (isNoShow) return '노쇼완료';
    if (isCancelled) return '예약 취소';
    if (isReturnOverdue) return '반납지연중';
    if (!isFinished &&
        !isInUse &&
        (status == 'confirmed' || status == 'pending') &&
        isUsageTimeExpired) {
      return '이용 종료';
    }
    if (isOperating) return '대여 중';
    if (isWaiting) return '이용 대기';
    if (status == 'returned') return '반납 처리됨';
    if (status == 'completed') return '이용 완료';
    return statusLabel;
  }

  /// 반납 지연 중 — in_use + (is_overdue 또는 미반납·종료시각 경과)
  bool get isReturnOverdue =>
      isInUse &&
      (isOverdue || (returnedAt == null && isUsageTimeExpired));

  /// 예약 기본요금 — total_price에서 연장 합계 제외
  int get baseRentalPrice {
    if (extensionPriceTotal <= 0) return totalPrice;
    return (totalPrice - extensionPriceTotal).clamp(0, totalPrice);
  }

  /// 반납 지연 초과요금 — 청구 완료분만
  int get chargedOverdueOverage =>
      overdueOverageCharged && (overdueOverageAmount ?? 0) > 0
          ? overdueOverageAmount!
          : 0;

  /// 이용내역 실제 결제 합계 (연장은 total_price 포함, 초과요금 별도 합산)
  int get historyPaidTotal => totalPrice + chargedOverdueOverage;

  /// 이용내역 — 기본/연장/초과요금 분해 표시
  bool get showHistoryPriceBreakdown =>
      chargedOverdueOverage > 0 || extensionPriceTotal > 0;

  /// 예약 기간 기본요금 청구 시간 (end_at − start_at, 1시간 올림)
  int? get scheduledBaseBillingHours {
    final start = startAt;
    final end = endAt;
    if (start == null || end == null || !end.isAfter(start)) return null;
    final minutes = end.difference(start).inMinutes;
    if (minutes <= 0) return null;
    return (minutes / 60).ceil();
  }

  /// 이용내역 금액 분해 라벨
  List<({String label, int amount, int? hours})> get historyPriceParts {
    final parts = <({String label, int amount, int? hours})>[];
    final base = baseRentalPrice;
    if (base > 0) {
      parts.add((
        label: '기본요금',
        amount: base,
        hours: scheduledBaseBillingHours,
      ));
    }
    if (extensionPriceTotal > 0) {
      parts.add((
        label: '연장요금',
        amount: extensionPriceTotal,
        hours: null,
      ));
    }
    final overageHours = overdueOverageHours;
    if (chargedOverdueOverage > 0 &&
        overageHours != null &&
        overageHours > 0) {
      parts.add((
        label: '초과요금',
        amount: chargedOverdueOverage,
        hours: overageHours,
      ));
    }
    return parts;
  }

  /// 초과 이용 요금 안내 문구 (반납 후)
  String? get overdueOverageChargeLabel {
    final amount = overdueOverageAmount;
    if (amount == null || amount <= 0) return null;
    final formatted = NumberFormat('#,###', 'ko_KR').format(amount);
    if (overdueOverageCharged) {
      return '초과 이용 요금 ₩$formatted 자동결제됨';
    }
    return '초과 이용 요금 자동결제 예정';
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
        return '반납 처리됨';
      case 'completed':
        return '이용 완료';
      case 'cancelled':
        return '예약 취소';
      default:
        return status;
    }
  }
}

/// 대여 시작 전 필수 사진 안내
abstract final class RentalPhotoMessages {
  static const minRequired = 6;
  static const maxAllowed = 10;

  static const startGuide =
      '앞·뒤·좌·우·실내·계기판을 포함하여 최소 6장 이상 등록해 주세요.';

  static const dashboardRequiredNote =
      '※ 주행 거리 및 주유(충전) 상태 확인을 위해 \'계기판 사진\'은 반드시 포함되어야 합니다.';

  static const slotLabels = ['앞', '뒤', '좌', '우', '실내', '계기판'];

  static const dashboardSlotIndex = 5;

  static String get maxReachedMessage =>
      '사진은 최대 $maxAllowed장까지 등록할 수 있습니다.';
}

/// 운행시작 안내
abstract final class RentalStartMessages {
  static const tooEarly = '대여 시작 가능 시간이 아닙니다. (예약 시작 10분 전부터 가능)';
  static const subtitleWhenTooEarly = '예약 시작 10분 전부터 이용 가능';
  static const subtitleReady = '사진 등록 후 출발하세요';
  static const startButtonActivationHint = '(10분전 활성화됩니다)';
}

/// 예약 취소 안내 문구
abstract final class ReservationCancelMessages {
  static const success = '예약취소가 완료되었습니다.';
  static const alreadyCancelled = '이미 취소된 예약입니다.';
  static const waitingGuide =
      '카셰어링(시간): 출고 1시간 전까지 전액 환불 · '
      '일·월 렌트: 출고 72시간 전 전액, 72~24시간 50%, 24시간 이내 환불 없음. '
      '모든 구간에서 취소 가능하며, 전액 환불 시 쿠폰·포인트가 복구됩니다.';
}

/// DB에서 이미 삭제·취소된 예약에 재요청할 때
bool isReservationAlreadyGoneError(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('예약을 찾을 수 없') ||
      text.contains('예약 정보를 찾을 수 없') ||
      text.contains('reservation_not_found') ||
      (text.contains('not found') &&
          (text.contains('reservation') || text.contains('예약')));
}
