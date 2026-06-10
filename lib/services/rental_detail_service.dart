import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/payment_order_status.dart';
import '../models/rental_detail.dart';
import '../models/staff_profile.dart';
import '../models/super_admin_models.dart';
import '../supabase_client.dart';
import '../utils/cancel_reason.dart';
import '../utils/sales_return_completed_at.dart';
import 'admin_service.dart';
import 'super_admin_service.dart';

class RentalDetailService {
  final AdminService? adminService;
  final SuperAdminService? superAdminService;

  const RentalDetailService({
    this.adminService,
    this.superAdminService,
  });

  Future<RentalDetailData> load({
    required String reservationId,
    required RentalDetailScope scope,
    RentalDetailPrefetch? prefetch,
  }) {
    final id = reservationId.trim();
    if (id.isEmpty) {
      throw const RentalDetailAccessException('예약번호가 없습니다.');
    }
    return switch (scope) {
      RentalDetailScope.staff => _loadStaff(id, prefetch),
      RentalDetailScope.superAdmin => _loadSuperAdmin(id, prefetch),
    };
  }

  Future<RentalDetailData> _loadStaff(
    String id,
    RentalDetailPrefetch? prefetch,
  ) async {
    const select = '''
id, reservation_number, user_id, status, total_price,
start_at, start_time, end_at, end_time,
rental_started_at, returned_at, actual_end_at, updated_at,
return_type, is_no_show, is_accident, accident_note,
rental_type, cancel_reason, cancelled_at,
payment_status, order_id,
pickup_photos, return_photos,
vehicles(model_name, car_number, complex_id, complexes(name))
''';

    Map<String, dynamic>? row;
    try {
      row = await supabase
          .from('reservations')
          .select(select)
          .eq('id', id)
          .maybeSingle();
    } on PostgrestException catch (e) {
      throw AdminException(mapAdminPostgrestError(e));
    }

    if (row == null) {
      throw const RentalDetailAccessException();
    }

    final map = Map<String, dynamic>.from(row);
    final userId = map['user_id']?.toString() ?? '';
    final profile = userId.isNotEmpty
        ? await _fetchStaffUserProfile(userId)
        : null;
    if (profile != null) {
      map['user_profiles'] = profile;
    }
    final adminRow = AdminReservationRow.fromMap(map);
    final complexName = _complexName(map['vehicles']);

    final usage = userId.isNotEmpty
        ? await _fetchStaffRenterUsageStats(userId)
        : SuperAdminRenterUsageStats.empty;

    final payment = await _fetchPaymentInfo(
      reservationId: id,
      userId: userId,
      totalPrice: adminRow.totalPrice,
      paymentStatus: map['payment_status']?.toString(),
      orderId: map['order_id']?.toString(),
    );

    return _buildDetail(
      adminRow: adminRow,
      renterPhone: profile?['phone']?.toString(),
      usageStats: usage,
      licenseVerified: profile?['license_verified'] == true,
      licenseStatusLabel: _licenseStatusLabel(profile),
      isBlacklisted: profile?['is_blacklisted'] == true,
      complexName: complexName ?? prefetch?.complexName,
      payment: payment,
      cancelReasonRaw: map['cancel_reason']?.toString(),
      prefetch: prefetch,
    );
  }

  Future<RentalDetailData> _loadSuperAdmin(
    String id,
    RentalDetailPrefetch? prefetch,
  ) async {
    final service = superAdminService;
    if (service == null) {
      throw const RentalDetailAccessException('최고관리자 서비스가 없습니다.');
    }

    final reservations = await service.fetchReservations();
    SuperAdminReservation? found;
    for (final r in reservations) {
      if (r.id == id) {
        found = r;
        break;
      }
    }
    if (found == null) {
      throw const RentalDetailAccessException();
    }

    final usage = await service.fetchRenterUsageStats(reservationId: id);

    String? cancelReason = prefetch?.cancelReason;
    int? paidAmount = prefetch?.paidAmount;
    int? refundAmount = prefetch?.refundAmount;

    if (found.status.trim().toLowerCase() == 'cancelled' &&
        cancelReason == null) {
      final resolved = await _resolveCancelFromSettlement(
        service: service,
        reservation: found,
      );
      cancelReason = resolved?.cancelReason ?? cancelReason;
      paidAmount = resolved?.paidAmount ?? paidAmount;
      refundAmount = resolved?.refundAmount ?? refundAmount;
    }

    final resident = await _findSuperAdminResidentByPhone(
      service: service,
      phone: found.renterPhone,
    );

    final adminRow = AdminReservationRow(
      id: found.id,
      reservationNumber: found.reservationNumber,
      status: found.status,
      totalPrice: found.totalPrice,
      startAt: found.startAt,
      endAt: found.endAt,
      rentalStartedAt: found.rentalStartedAt,
      actualEndAt: found.actualEndAt,
      returnedAt: found.returnedAt,
      updatedAt: null,
      vehicleName: found.vehicleName,
      carNumber: found.carNumber,
      isAccident: false,
      pickupPhotos: found.pickupPhotos,
      returnPhotos: found.returnPhotos,
      renterName: found.renterName,
      isNoShow: found.isNoShow,
      rentalType: found.rentalType,
    );

    return _buildDetail(
      adminRow: adminRow,
      renterPhone: found.renterPhone == '미등록' ? null : found.renterPhone,
      usageStats: usage,
      licenseVerified: resident?.licenseVerified ?? false,
      licenseStatusLabel: resident == null
          ? '미확인'
          : (resident.licenseVerified ? '승인' : '미승인'),
      isBlacklisted: resident?.isBlacklisted ?? false,
      complexName: found.complexName,
      payment: RentalPaymentInfo(
        totalPrice: found.totalPrice,
        paymentStatus: null,
      ),
      cancelReasonRaw: cancelReason,
      prefetch: prefetch,
      paidAmount: paidAmount,
      refundAmount: refundAmount,
    );
  }

  RentalDetailData _buildDetail({
    required AdminReservationRow adminRow,
    required SuperAdminRenterUsageStats usageStats,
    required RentalPaymentInfo payment,
    String? renterPhone,
    bool licenseVerified = false,
    String licenseStatusLabel = '미확인',
    bool isBlacklisted = false,
    String? complexName,
    String? cancelReasonRaw,
    RentalDetailPrefetch? prefetch,
    int? paidAmount,
    int? refundAmount,
  }) {
    final returnCompleted = resolveSalesReturnCompletedAt(
      returnedAt: adminRow.returnedAt,
      actualEndAt: adminRow.actualEndAt,
      scheduledEndAt: adminRow.endAt,
      isNoShow: adminRow.isNoShow,
      updatedAt: adminRow.updatedAt,
    );

    final isCompleted = adminRow.status.trim().toLowerCase() == 'completed';
    final isCancelled = adminRow.status.trim().toLowerCase() == 'cancelled';

    return RentalDetailData(
      id: adminRow.id,
      reservationNumber: adminRow.reservationNumber,
      vehicleName: adminRow.vehicleName,
      carNumber: adminRow.carNumber,
      status: adminRow.status,
      isNoShow: adminRow.isNoShow,
      rentalType: adminRow.rentalType,
      complexName: complexName,
      renterName: adminRow.renterDisplayName,
      renterPhone: renterPhone,
      usageStats: usageStats,
      licenseVerified: licenseVerified,
      licenseStatusLabel: licenseStatusLabel,
      isBlacklisted: isBlacklisted,
      startAt: adminRow.startAt,
      endAt: adminRow.endAt,
      rentalStartedAt: adminRow.rentalStartedAt,
      returnedAt: adminRow.returnedAt,
      actualEndAt: adminRow.actualEndAt,
      updatedAt: adminRow.updatedAt,
      payment: payment,
      paymentStatusLabel: _paymentStatusLabel(payment.paymentStatus),
      isAccident: adminRow.isAccident,
      accidentNote: adminRow.accidentNote,
      salesRecognitionMonth: isCompleted
          ? formatSalesRecognitionMonth(returnCompleted)
          : null,
      cancelReasonLabel: isCancelled
          ? cancelReasonDisplayLabel(
              cancelReasonRaw ?? prefetch?.cancelReason,
            )
          : null,
      paidAmount: paidAmount ?? prefetch?.paidAmount,
      refundAmount: refundAmount ?? prefetch?.refundAmount,
    );
  }

  Future<SuperAdminRenterUsageStats> _fetchStaffRenterUsageStats(
    String userId,
  ) async {
    try {
      final rows = await supabase
          .from('reservations')
          .select('status, is_no_show')
          .eq('user_id', userId);

      var usageCount = 0;
      var noShowCount = 0;
      for (final raw in rows as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        if (row['status']?.toString().trim().toLowerCase() == 'completed') {
          usageCount++;
        }
        if (row['is_no_show'] == true) {
          noShowCount++;
        }
      }
      return SuperAdminRenterUsageStats(
        usageCount: usageCount,
        noShowCount: noShowCount,
      );
    } catch (_) {
      return SuperAdminRenterUsageStats.empty;
    }
  }

  Future<RentalPaymentInfo> _fetchPaymentInfo({
    required String reservationId,
    required String userId,
    required int totalPrice,
    String? paymentStatus,
    String? orderId,
  }) async {
    Map<String, dynamic>? order;
    try {
      if (reservationId.isNotEmpty) {
        order = await supabase
            .from('payment_orders')
            .select(PaymentOrderColumns.selectPricing)
            .eq('reservation_id', reservationId)
            .maybeSingle();
      }
      order ??= orderId != null && orderId.isNotEmpty
          ? await supabase
              .from('payment_orders')
              .select(PaymentOrderColumns.selectPricing)
              .eq('order_id', orderId)
              .maybeSingle()
          : null;
    } catch (_) {}

    if (order == null) {
      return RentalPaymentInfo(
        totalPrice: totalPrice,
        paymentStatus: paymentStatus,
      );
    }

    final original = (order['original_price'] as num?)?.toInt();
    final paid = (order['total_price'] as num?)?.toInt() ?? totalPrice;
    final points = (order['points_used'] as num?)?.toInt();
    final couponId = order['user_coupon_id']?.toString();
    final couponDiscount =
        original != null && original > paid ? original - paid - (points ?? 0) : null;

    return RentalPaymentInfo(
      totalPrice: paid,
      originalPrice: original,
      pointsUsed: points,
      couponDiscount: couponId != null && couponId.isNotEmpty
          ? (couponDiscount != null && couponDiscount > 0 ? couponDiscount : null)
          : null,
      paymentStatus: order['status']?.toString() ?? paymentStatus,
    );
  }

  Future<SuperAdminSettlementCancelItem?> _resolveCancelFromSettlement({
    required SuperAdminService service,
    required SuperAdminReservation reservation,
  }) async {
    final cancelledAt = reservation.actualReturnAt ?? reservation.endAt;
    if (cancelledAt == null || reservation.complexId.isEmpty) return null;

    final local = cancelledAt.toLocal();
    try {
      final sheet = await service.fetchSettlementSheet(
        complexId: reservation.complexId,
        year: local.year,
        month: local.month,
      );
      for (final item in sheet.cancelItems) {
        if (item.reservationId == reservation.id) return item;
      }
    } catch (_) {}
    return null;
  }

  Future<_ResidentLicenseSnapshot?> _findSuperAdminResidentByPhone({
    required SuperAdminService service,
    required String phone,
  }) async {
    final trimmed = phone.trim();
    if (trimmed.isEmpty || trimmed == '미등록') return null;
    try {
      final residents = await service.fetchResidents();
      for (final r in residents) {
        if ((r.phone ?? '').trim() == trimmed) {
          return _ResidentLicenseSnapshot(
            licenseVerified: r.licenseVerified,
            isBlacklisted: r.isBlacklisted,
          );
        }
      }
    } catch (_) {}
    return null;
  }

  /// reservations ↔ user_profiles FK 없음 — user_id로 별도 조회 (RLS + RPC fallback)
  Future<Map<String, dynamic>?> _fetchStaffUserProfile(String userId) async {
    final trimmed = userId.trim();
    if (trimmed.isEmpty) return null;

    Map<String, dynamic>? profile;

    try {
      final row = await supabase
          .from('user_profiles')
          .select(
            'user_id, full_name, name, email, phone, license_verified, '
            'license_number, license_rejection_reason, license_submitted_at, '
            'is_blacklisted',
          )
          .eq('user_id', trimmed)
          .maybeSingle();
      if (row != null) {
        profile = Map<String, dynamic>.from(row);
      }
    } on PostgrestException {
      // RLS 등 — RPC로 이름·이메일 보강
    }

    try {
      final rpcRows = await supabase.rpc(
        'get_renter_profiles_for_staff',
        params: {'p_user_ids': [trimmed]},
      );
      if (rpcRows is List) {
        for (final row in rpcRows) {
          if (row is! Map) continue;
          final rpc = Map<String, dynamic>.from(row);
          if (rpc['user_id']?.toString() != trimmed) continue;
          profile ??= {'user_id': trimmed};
          profile['full_name'] ??= rpc['full_name']?.toString();
          profile['email'] ??= rpc['email']?.toString();
        }
      }
    } on PostgrestException {
      // RPC 미배포·권한 오류 시 직접 조회 결과만 사용
    }

    return profile;
  }

  static String? _complexName(Object? vehicleRaw) {
    if (vehicleRaw is! Map) return null;
    final vehicle = Map<String, dynamic>.from(vehicleRaw);
    final complexes = vehicle['complexes'];
    if (complexes is Map) {
      return complexes['name']?.toString();
    }
    return null;
  }

  static String _licenseStatusLabel(Map<String, dynamic>? profile) {
    if (profile == null) return '미확인';
    if (profile['license_verified'] == true) return '승인';
    final number = profile['license_number']?.toString().trim() ?? '';
    if (number.isNotEmpty) {
      final rejection = profile['license_rejection_reason']?.toString().trim();
      if (rejection != null && rejection.isNotEmpty) return '반려';
      return '검토 대기';
    }
    return '미제출';
  }

  static String _paymentStatusLabel(String? status) {
    final s = status?.trim().toLowerCase() ?? '';
    return switch (s) {
      'paid' || 'confirmed' => '결제완료',
      'pending' => '결제대기',
      'cancelled' => '결제취소',
      'failed' => '결제실패',
      '' => '-',
      _ => status ?? '-',
    };
  }
}

class _ResidentLicenseSnapshot {
  final bool licenseVerified;
  final bool isBlacklisted;

  const _ResidentLicenseSnapshot({
    required this.licenseVerified,
    required this.isBlacklisted,
  });
}
