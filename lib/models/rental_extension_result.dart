import '../services/support_contacts_service.dart';

class RentalExtensionCheckResult {
  final bool eligible;
  final String? reason;
  final String? message;
  final String? reservationId;
  final int extensionHours;
  final DateTime? scheduledEndAt;
  final DateTime? newEndAt;
  final DateTime? extensionWindowStartAt;
  final int? addedPrice;
  final int? currentTotalPrice;
  final int? newTotalPrice;
  final int? extensionCount;
  final String? emergencyPhone;
  final bool showEmergencyConsultation;
  final String? blockingReservationId;

  const RentalExtensionCheckResult({
    required this.eligible,
    this.reason,
    this.message,
    this.reservationId,
    this.extensionHours = 1,
    this.scheduledEndAt,
    this.newEndAt,
    this.extensionWindowStartAt,
    this.addedPrice,
    this.currentTotalPrice,
    this.newTotalPrice,
    this.extensionCount,
    this.emergencyPhone,
    this.showEmergencyConsultation = false,
    this.blockingReservationId,
  });

  factory RentalExtensionCheckResult.fromMap(Map<String, dynamic> map) {
    return RentalExtensionCheckResult(
      eligible: map['eligible'] == true || map['eligible'] == 'true',
      reason: map['reason']?.toString(),
      message: map['message']?.toString(),
      reservationId: map['reservationId']?.toString(),
      extensionHours: (map['extensionHours'] as num?)?.toInt() ?? 1,
      scheduledEndAt: _parseDate(map['scheduledEndAt']),
      newEndAt: _parseDate(map['newEndAt'] ?? map['requestedNewEndAt']),
      extensionWindowStartAt: _parseDate(map['extensionWindowStartAt']),
      addedPrice: (map['addedPrice'] as num?)?.toInt(),
      currentTotalPrice: (map['currentTotalPrice'] as num?)?.toInt(),
      newTotalPrice: (map['newTotalPrice'] as num?)?.toInt(),
      extensionCount: (map['extensionCount'] as num?)?.toInt(),
      emergencyPhone: SupportContactsService.normalizePhone(
        map['emergencyPhone']?.toString(),
      ),
      showEmergencyConsultation: map['showEmergencyConsultation'] == true,
      blockingReservationId: map['blockingReservationId']?.toString(),
    );
  }

  Map<String, dynamic> toLogContext() {
    return {
      if (reason != null) 'reason': reason,
      if (message != null) 'message': message,
      if (scheduledEndAt != null)
        'scheduledEndAt': scheduledEndAt!.toUtc().toIso8601String(),
      if (newEndAt != null) 'newEndAt': newEndAt!.toUtc().toIso8601String(),
      if (blockingReservationId != null)
        'blockingReservationId': blockingReservationId,
      'extensionHours': extensionHours,
    };
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    return DateTime.tryParse(value.toString())?.toLocal();
  }
}

abstract final class RentalExtensionMessages {
  static const success = '대여 연장이 완료되었습니다.';
  static const confirmTitle = '대여 연장';
  static const emergencyTitle = '연장 불가';
  static const needInUse = '대여 중(in_use)인 예약만 연장할 수 있습니다.';
  static const tooEarly =
      '대여 종료 1시간 전부터 연장 신청이 가능합니다.';
  static const tooLate = '예약 종료 시각이 지나 연장할 수 없습니다.';
  static const applying = '연장 처리 중…';
  static const payingAndApplying = '결제 및 연장 처리 중…';
  static const checking = '연장 가능 여부 확인 중…';
}
