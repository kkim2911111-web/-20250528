import '../utils/rental_pricing.dart';
import '../utils/reservation_display.dart';
import 'super_admin_models.dart';

enum RentalDetailScope { staff, superAdmin }

/// 진입점에서 넘길 수 있는 보조 데이터 (정산·취소 목록 등)
class RentalDetailPrefetch {
  final String? cancelReason;
  final int? paidAmount;
  final int? refundAmount;
  final String? complexName;

  const RentalDetailPrefetch({
    this.cancelReason,
    this.paidAmount,
    this.refundAmount,
    this.complexName,
  });
}

class RentalPaymentInfo {
  final int totalPrice;
  final int? originalPrice;
  final int? pointsUsed;
  final int? couponDiscount;
  final String? paymentStatus;

  const RentalPaymentInfo({
    required this.totalPrice,
    this.originalPrice,
    this.pointsUsed,
    this.couponDiscount,
    this.paymentStatus,
  });
}

class RentalDetailData {
  final String id;
  final String? reservationNumber;
  final String vehicleName;
  final String? carNumber;
  final String status;
  final bool isNoShow;
  final RentalType? rentalType;

  final String? complexName;

  final String renterName;
  final String? renterPhone;
  final SuperAdminRenterUsageStats usageStats;
  final bool licenseVerified;
  final String licenseStatusLabel;
  final bool isBlacklisted;

  final DateTime? startAt;
  final DateTime? endAt;
  final DateTime? rentalStartedAt;
  final DateTime? returnedAt;
  final DateTime? actualEndAt;
  final DateTime? updatedAt;

  final RentalPaymentInfo payment;
  final String paymentStatusLabel;

  final bool isAccident;
  final String? accidentNote;

  final String? salesRecognitionMonth;
  final String? cancelReasonLabel;
  final int? refundAmount;
  final int? paidAmount;

  const RentalDetailData({
    required this.id,
    this.reservationNumber,
    required this.vehicleName,
    this.carNumber,
    required this.status,
    this.isNoShow = false,
    this.rentalType,
    this.complexName,
    required this.renterName,
    this.renterPhone,
    this.usageStats = SuperAdminRenterUsageStats.empty,
    this.licenseVerified = false,
    this.licenseStatusLabel = '미확인',
    this.isBlacklisted = false,
    this.startAt,
    this.endAt,
    this.rentalStartedAt,
    this.returnedAt,
    this.actualEndAt,
    this.updatedAt,
    required this.payment,
    this.paymentStatusLabel = '-',
    this.isAccident = false,
    this.accidentNote,
    this.salesRecognitionMonth,
    this.cancelReasonLabel,
    this.refundAmount,
    this.paidAmount,
  });

  String get reservationNumberLabel => resolveReservationNumberLabel(
        reservationNumber: reservationNumber,
        rawId: id,
      );

  bool get canShowForceReturnButton {
    if (isNoShow) return false;
    return status.trim().toLowerCase() == 'in_use';
  }

  bool get canShowPaymentCancelButton {
    if (isNoShow) return false;
    final s = status.trim().toLowerCase();
    return s == 'confirmed' || s == 'in_use';
  }

  bool get showForceActionButtons =>
      canShowForceReturnButton || canShowPaymentCancelButton;

  bool get showReturnInspectionSection {
    final s = status.trim().toLowerCase();
    return s == 'returned' || s == 'completed';
  }

  String get renterLine => usageStats.formatLine(renterName);
}

class RentalDetailAccessException implements Exception {
  final String message;
  const RentalDetailAccessException([
    this.message = '예약 정보를 조회할 수 없습니다.',
  ]);

  @override
  String toString() => message;
}
