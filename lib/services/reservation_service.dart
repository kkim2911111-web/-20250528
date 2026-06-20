import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/booking_contract_consent.dart';
import '../models/reservation.dart';
import '../models/reservation_payment_pricing.dart';
import '../supabase_client.dart';
import '../utils/vehicle_insurance_status.dart';
import '../utils/reservation_overlap.dart';
import '../constants/payment_order_status.dart';
import '../utils/booking_eligibility.dart';
import '../utils/maintenance_error.dart';
import 'app_maintenance_service.dart';
import '../utils/rental_pricing.dart';
import 'my_page_service.dart';
import 'push_notification_service.dart';
import 'rental_service.dart';

class ReservationOverlapException implements Exception {
  final String message;
  const ReservationOverlapException([this.message = '이미 예약된 시간입니다']);
  @override
  String toString() => message;
}

/// 예약 화면 — 차량 선택 불가 사유
enum VehicleBookingBlockReason {
  inUse,
  underMaintenance,
  unpublished,
  insuranceExpired,
  timeOverlap,
}

class ReservationPermissionException implements Exception {
  final String message;
  const ReservationPermissionException(this.message);
  @override
  String toString() => message;
}

class ReservationChangeException implements Exception {
  final String message;
  const ReservationChangeException(this.message);
  @override
  String toString() => message;
}

enum _ReservationOverlapKind { none, inUse, time }

class ReservationService {
  Future<Map<String, dynamic>?> _fetchMyResident() async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;
    return supabase
        .from('residents')
        .select('complex_id, approved, complexes(name, invite_code)')
        .eq('user_id', user.id)
        .maybeSingle();
  }

  Future<void> _validateBookingPermission(String vehicleId) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw const AuthException('로그인이 필요합니다.');
    }

    final resident = await _fetchMyResident();
    if (resident == null) {
      throw const ReservationPermissionException(
        '입주민 등록이 없습니다. 초대코드·동/호 인증을 먼저 완료해주세요.',
      );
    }
    if (resident['approved'] != true) {
      throw const ReservationPermissionException(
        '입주민 승인 대기 중입니다. Supabase에서 approved = true 로 승인해주세요.',
      );
    }

    final myComplexId = resident['complex_id']?.toString();
    if (myComplexId == null || myComplexId.isEmpty) {
      throw const ReservationPermissionException(
        '단지(complex_id) 연결 정보가 없습니다.',
      );
    }

    final vehicle = await supabase
        .from('vehicles')
        .select('id, complex_id, model_name, is_under_maintenance')
        .eq('id', vehicleId)
        .maybeSingle();

    if (vehicle == null) {
      throw const ReservationPermissionException(
        '차량 정보를 불러올 수 없습니다. 차량이 내 단지에 등록되어 있는지 확인해주세요.',
      );
    }

    if (vehicle['is_under_maintenance'] == true) {
      throw const ReservationPermissionException(
        '점검 중인 차량입니다. 예약할 수 없습니다.',
      );
    }

    final vehicleComplexId = vehicle['complex_id']?.toString();
    if (vehicleComplexId != myComplexId) {
      final complexRaw = resident['complexes'];
      final complexMap =
          complexRaw is Map ? Map<String, dynamic>.from(complexRaw) : null;
      final name = complexMap?['name']?.toString() ?? '내 단지';
      throw ReservationPermissionException(
        '선택한 차량이 $name에 속하지 않습니다.\n'
        '입주민 complex_id와 차량 complex_id가 일치해야 예약할 수 있습니다.',
      );
    }

    final profile = await MyPageService().fetchProfile();
    final block = BookingEligibility.blockReason(profile);
    if (block != null) {
      throw ReservationPermissionException(block);
    }
  }

  /// 예약 불가 사유 — null이면 해당 시간대 예약 가능
  Future<VehicleBookingBlockReason?> getVehicleBookingBlockReason({
    required String vehicleId,
    required DateTime startAt,
    required DateTime endAt,
    bool? isUnderMaintenance,
  }) async {
    if (isUnderMaintenance == true) {
      return VehicleBookingBlockReason.underMaintenance;
    }

    final row = await supabase
        .from('vehicles')
        .select(
          'is_under_maintenance, is_published, insurance_expires_at',
        )
        .eq('id', vehicleId)
        .maybeSingle();

    if (isUnderMaintenance != false && row?['is_under_maintenance'] == true) {
      return VehicleBookingBlockReason.underMaintenance;
    }

    if (row?['is_published'] != true) {
      return VehicleBookingBlockReason.unpublished;
    }

    final expiresRaw = row?['insurance_expires_at'];
    final expiresAt = expiresRaw == null
        ? null
        : DateTime.tryParse(expiresRaw.toString());
    if (VehicleInsuranceStatus.isExpired(expiresAt)) {
      return VehicleBookingBlockReason.insuranceExpired;
    }

    final overlaps = await _hasActiveReservationOverlap(
      vehicleId: vehicleId,
      startAt: startAt,
      endAt: endAt,
    );
    if (overlaps == _ReservationOverlapKind.inUse) {
      return VehicleBookingBlockReason.inUse;
    }
    if (overlaps == _ReservationOverlapKind.time) {
      return VehicleBookingBlockReason.timeOverlap;
    }
    return null;
  }

  /// 예약 불가 여부 — true면 해당 시간대에 예약할 수 없음
  Future<bool> hasOverlappingReservation({
    required String vehicleId,
    required DateTime startAt,
    required DateTime endAt,
  }) async {
    return (await getVehicleBookingBlockReason(
          vehicleId: vehicleId,
          startAt: startAt,
          endAt: endAt,
        )) !=
        null;
  }

  Future<_ReservationOverlapKind> _hasActiveReservationOverlap({
    required String vehicleId,
    required DateTime startAt,
    required DateTime endAt,
  }) async {
    final startUtc = startAt.toUtc();
    final endUtc = endAt.toUtc();
    final vid = _vehicleIdForQuery(vehicleId);

    const selectCols =
        'id, status, start_at, start_time, end_at, end_time, actual_end_at, returned_at';

    try {
      final rows = await supabase
          .from('reservations')
          .select(selectCols)
          .eq('vehicle_id', vid)
          .inFilter('status', ['pending', 'confirmed', 'in_use'])
          .limit(50);

      var sawInUse = false;
      var sawTime = false;
      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw as Map);
        final status = row['status']?.toString() ?? '';
        final otherStartRaw = row['start_at'] ?? row['start_time'];
        final otherEndRaw = row['end_at'] ?? row['end_time'];
        final otherStart =
            DateTime.tryParse(otherStartRaw?.toString() ?? '');
        final otherEnd = DateTime.tryParse(otherEndRaw?.toString() ?? '');
        if (otherStart == null) continue;

        final actualEndRaw = row['actual_end_at'];
        final returnedRaw = row['returned_at'];
        final actualEnd = actualEndRaw == null
            ? null
            : DateTime.tryParse(actualEndRaw.toString());
        final returnedAt = returnedRaw == null
            ? null
            : DateTime.tryParse(returnedRaw.toString());

        if (!ReservationOverlapLogic.overlaps(
          otherStart: otherStart.toUtc(),
          otherStatus: status,
          otherScheduledEnd: otherEnd?.toUtc(),
          otherActualEndAt: actualEnd?.toUtc(),
          otherReturnedAt: returnedAt?.toUtc(),
          requestStart: startUtc,
          requestEnd: endUtc,
        )) {
          continue;
        }

        if (status == 'in_use') {
          sawInUse = true;
        } else {
          sawTime = true;
        }
      }
      if (sawInUse) return _ReservationOverlapKind.inUse;
      if (sawTime) return _ReservationOverlapKind.time;
      return _ReservationOverlapKind.none;
    } on PostgrestException catch (e) {
      if (e.code == '42703') {
        return _ReservationOverlapKind.none;
      }
      rethrow;
    }
  }

  dynamic _vehicleIdForQuery(String vehicleId) {
    final parsed = int.tryParse(vehicleId.trim());
    return parsed ?? vehicleId;
  }

  Future<String?> _insertReservation(Map<String, dynamic> payload) async {
    final variants = <Map<String, dynamic>>[
      payload,
      {
        'user_id': payload['user_id'],
        'vehicle_id': payload['vehicle_id'],
        'start_time': payload['start_time'],
        'end_time': payload['end_time'],
        'total_price': payload['total_price'],
        'status': payload['status'],
      },
      {
        'user_id': payload['user_id'],
        'vehicle_id': payload['vehicle_id'],
        'start_at': payload['start_at'],
        'end_at': payload['end_at'],
        'status': payload['status'],
      },
    ];

    PostgrestException? lastError;
    for (final data in variants) {
      try {
        final row = await supabase
            .from('reservations')
            .insert(data)
            .select('id')
            .maybeSingle();
        return row?['id']?.toString();
      } on PostgrestException catch (e) {
        lastError = e;
        if (e.code == '42703' || e.code == '23502') continue;
        rethrow;
      }
    }
    if (lastError != null) throw lastError;
    return null;
  }

  String? _parseCreatedReservationId(dynamic data) {
    if (data is Map) {
      return data['id']?.toString();
    }
    return null;
  }

  /// 예약 확정 FCM — 고객·관리자 (non-fatal)
  Future<void> notifyReservationCreated({
    required String reservationId,
    required String vehicleId,
    required DateTime startAt,
    required String userId,
  }) async {
    final vehicleRow = await supabase
        .from('vehicles')
        .select('model_name, complex_id')
        .eq('id', _vehicleIdForQuery(vehicleId))
        .maybeSingle();
    if (vehicleRow == null) return;

    final vehicleName = vehicleRow['model_name']?.toString().trim().isNotEmpty ==
            true
        ? vehicleRow['model_name']!.toString()
        : '차량';
    final complexId = vehicleRow['complex_id']?.toString() ?? '';
    if (complexId.isEmpty) return;

    final push = PushNotificationService.instance;
    await push.customerReservationConfirmed(
      userId: userId,
      reservationId: reservationId,
      vehicleName: vehicleName,
      startAt: startAt.toUtc().toIso8601String(),
    );
    await push.staffNewReservation(
      complexId: complexId,
      reservationId: reservationId,
      vehicleName: vehicleName,
      startAt: startAt.toUtc().toIso8601String(),
      userId: userId,
    );
  }

  /// 결제 확정 등 — reservationId만으로 vehicle·시작시각 조회 후 푸시 발송
  Future<void> notifyReservationCreatedForReservation({
    required String reservationId,
    String? userId,
  }) async {
    final uid = userId ?? supabase.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return;

    Map<String, dynamic>? row;
    try {
      row = await supabase
          .from('reservations')
          .select('vehicle_id, start_at, start_time')
          .eq('id', reservationId)
          .eq('user_id', uid)
          .maybeSingle();
    } on PostgrestException catch (e) {
      if (e.code == '42703' || e.code == 'PGRST204') {
        row = await supabase
            .from('reservations')
            .select('vehicle_id, start_time')
            .eq('id', reservationId)
            .eq('user_id', uid)
            .maybeSingle();
      } else {
        rethrow;
      }
    }

    if (row == null) return;

    final vehicleId = row['vehicle_id']?.toString();
    final startAt = DateTime.tryParse(
      (row['start_at'] ?? row['start_time'])?.toString() ?? '',
    );
    if (vehicleId == null || vehicleId.isEmpty || startAt == null) return;

    await notifyReservationCreated(
      reservationId: reservationId,
      vehicleId: vehicleId,
      startAt: startAt.toLocal(),
      userId: uid,
    );
  }

  Future<void> validateBookingForPayment({
    required String vehicleId,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    if (!endTime.isAfter(startTime)) {
      throw ArgumentError('종료 시간은 시작 시간보다 뒤여야 합니다.');
    }
    if (endTime.difference(startTime).inMinutes < 60) {
      throw ArgumentError('최소 1시간 이상 예약해야 합니다.');
    }

    await _validateBookingPermission(vehicleId);

    final overlaps = await hasOverlappingReservation(
      vehicleId: vehicleId,
      startAt: startTime,
      endAt: endTime,
    );
    if (overlaps) {
      throw const ReservationOverlapException();
    }
  }

  Future<void> createBooking({
    required String vehicleId,
    required DateTime startTime,
    required DateTime endTime,
    required int totalPrice,
    RentalType rentalType = RentalType.hourly,
  }) async {
    if (!endTime.isAfter(startTime)) {
      throw ArgumentError('종료 시간은 시작 시간보다 뒤여야 합니다.');
    }
    if (endTime.difference(startTime).inMinutes < 60) {
      throw ArgumentError('최소 1시간 이상 예약해야 합니다.');
    }

    await _validateBookingPermission(vehicleId);

    final overlaps = await hasOverlappingReservation(
      vehicleId: vehicleId,
      startAt: startTime,
      endAt: endTime,
    );
    if (overlaps) {
      throw const ReservationOverlapException();
    }

    final user = supabase.auth.currentUser!;
    final startUtc = startTime.toUtc();
    final endUtc = endTime.toUtc();

    try {
      final data = await supabase.rpc('create_reservation_for_me', params: {
        'p_vehicle_id': vehicleId,
        'p_start_time': startUtc.toIso8601String(),
        'p_end_time': endUtc.toIso8601String(),
        'p_total_price': totalPrice,
        'p_rental_type': rentalType.dbValue,
      });
      final reservationId = _parseCreatedReservationId(data);
      if (reservationId != null) {
        await notifyReservationCreated(
          reservationId: reservationId,
          vehicleId: vehicleId,
          startAt: startTime,
          userId: user.id,
        );
      }
      return;
    } on PostgrestException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('not_approved')) {
        throw const ReservationPermissionException(
          '입주민 승인이 필요합니다. Supabase에서 approved = true 확인.',
        );
      }
      if (msg.contains('license_not_verified')) {
        throw const ReservationPermissionException(
          '면허 심사 승인 후 예약할 수 있습니다.\n마이페이지에서 면허 등록·심사 상태를 확인해주세요.',
        );
      }
      if (msg.contains('vehicle_not_in_complex')) {
        throw const ReservationPermissionException(
          '이 차량은 내 단지 차량이 아닙니다. complex_id를 확인해주세요.',
        );
      }
      if (msg.contains('time_overlap')) {
        throw const ReservationOverlapException();
      }
      if (msg.contains('price_mismatch')) {
        throw const ReservationPermissionException(
          '요금 정보가 올바르지 않습니다. 다시 시도해주세요.',
        );
      }
      if (msg.contains('could not find the function') ||
          msg.contains('create_reservation_for_me')) {
        // RPC 미설치 → direct insert fallback
      } else {
        rethrow;
      }
    }

    final reservationId = await _insertReservation({
      'user_id': user.id,
      'vehicle_id': vehicleId,
      'start_time': startUtc.toIso8601String(),
      'end_time': endUtc.toIso8601String(),
      'start_at': startUtc.toIso8601String(),
      'end_at': endUtc.toIso8601String(),
      'total_price': totalPrice,
      'rental_type': rentalType.dbValue,
      'status': 'pending',
    });
    if (reservationId != null) {
      await notifyReservationCreated(
        reservationId: reservationId,
        vehicleId: vehicleId,
        startAt: startTime,
        userId: user.id,
      );
    }
  }

  Future<void> createReservation({
    required String vehicleId,
    required DateTime startAt,
    required DateTime endAt,
    int totalPrice = 0,
    RentalType rentalType = RentalType.hourly,
  }) async {
    await createBooking(
      vehicleId: vehicleId,
      startTime: startAt,
      endTime: endAt,
      totalPrice: totalPrice,
      rentalType: rentalType,
    );
  }

  /// 예약 변경 — update_reservation_for_me RPC
  Future<Map<String, dynamic>> updateReservationForMe({
    required String reservationId,
    required DateTime startAt,
    required DateTime endAt,
    int? totalPrice,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw const AuthException('로그인이 필요합니다.');
    }

    if (!endAt.isAfter(startAt)) {
      throw ArgumentError('종료 시간은 시작 시간보다 뒤여야 합니다.');
    }

    try {
      final params = <String, dynamic>{
        'p_reservation_id': reservationId,
        'p_start_time': startAt.toUtc().toIso8601String(),
        'p_end_time': endAt.toUtc().toIso8601String(),
      };
      if (totalPrice != null) {
        params['p_total_price'] = totalPrice;
      }

      final data = await supabase.rpc('update_reservation_for_me', params: params);
      RentalService.signalListRefresh();
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      return {'id': reservationId};
    } on PostgrestException catch (e) {
      throw ReservationChangeException(friendlyUpdateReservationError(e));
    }
  }

  String _reservationIdFrom(Map<String, dynamic> map) {
    return map['reservationId']?.toString() ??
        map['reservation_id']?.toString() ??
        '';
  }

  /// 결제 금액 — URL amount → 결과 totalPrice → payment_orders → reservations
  Future<int> resolveGrantAmount({
    required String orderId,
    required int paymentAmount,
    int? resultTotalPrice,
    String? reservationId,
  }) async {
    if (paymentAmount > 0) {
      debugPrint('[payment/points] resolveGrantAmount: paymentAmount=$paymentAmount');
      return paymentAmount;
    }
    if (resultTotalPrice != null && resultTotalPrice > 0) {
      debugPrint(
        '[payment/points] resolveGrantAmount: resultTotalPrice=$resultTotalPrice',
      );
      return resultTotalPrice;
    }

    final order = await findPaymentOrderByOrderId(orderId);
    final fromOrder = (order?['total_price'] as num?)?.toInt() ?? 0;
    if (fromOrder > 0) {
      debugPrint('[payment/points] resolveGrantAmount: order.total_price=$fromOrder');
      return fromOrder;
    }

    final rid = reservationId?.trim() ?? '';
    if (rid.isNotEmpty) {
      try {
        final row = await supabase
            .from('reservations')
            .select('total_price')
            .eq('id', rid)
            .maybeSingle();
        final fromReservation = (row?['total_price'] as num?)?.toInt() ?? 0;
        if (fromReservation > 0) {
          debugPrint(
            '[payment/points] resolveGrantAmount: reservation.total_price=$fromReservation',
          );
          return fromReservation;
        }
      } on PostgrestException catch (e) {
        debugPrint('[payment/points] resolveGrantAmount reservation lookup: $e');
      }
    }

    debugPrint(
      '[payment/points] resolveGrantAmount: no amount (payment=$paymentAmount, '
      'resultTotalPrice=$resultTotalPrice, orderId=$orderId)',
    );
    return 0;
  }

  /// 결제 주문에 저장된 쿠폰·포인트 사용 (결제 완료 후)
  Future<void> tryApplyBookingDiscounts({
    required String orderId,
    required String reservationId,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null || reservationId.isEmpty) return;

    Map<String, dynamic>? order;
    try {
      order = await supabase
          .from('payment_orders')
          .select('user_coupon_id, points_used')
          .eq('order_id', orderId)
          .eq('user_id', userId)
          .maybeSingle();
    } on PostgrestException catch (e) {
      if (e.code == '42703' || e.code == 'PGRST204') return;
      rethrow;
    }

    if (order == null) return;

    final userCouponId = order['user_coupon_id']?.toString();
    final pointsUsed = (order['points_used'] as num?)?.toInt() ?? 0;

    if (userCouponId != null && userCouponId.isNotEmpty) {
      try {
        await supabase.rpc('consume_user_coupon_for_me', params: {
          'p_user_coupon_id': userCouponId,
          'p_reservation_id': reservationId,
        });
      } catch (e) {
        debugPrint('[booking/checkout] consume_user_coupon_for_me: $e');
      }
    }

    if (pointsUsed > 0) {
      try {
        await supabase.rpc('spend_booking_points_for_me', params: {
          'p_user_id': userId,
          'p_reservation_id': reservationId,
          'p_points': pointsUsed,
        });
      } catch (e) {
        debugPrint('[booking/checkout] spend_booking_points_for_me: $e');
      }
    }
  }

  /// 예약 카드 — payment_orders 할인 정보 (reservation_id / order_id 매칭)
  Future<Map<String, ReservationPaymentPricing>> fetchPaymentPricingForReservations(
    Iterable<Reservation> reservations,
  ) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return {};

    final byReservationId = <String, Reservation>{};
    final orderIds = <String>[];
    for (final r in reservations) {
      if (r.id.isEmpty) continue;
      byReservationId[r.id] = r;
      final oid = r.orderId?.trim();
      if (oid != null && oid.isNotEmpty) orderIds.add(oid);
    }
    if (byReservationId.isEmpty) return {};

    final rows = <Map<String, dynamic>>[];

    try {
      final byRes = await supabase
          .from('payment_orders')
          .select(PaymentOrderColumns.selectPricing)
          .eq('user_id', userId)
          .inFilter('reservation_id', byReservationId.keys.toList());
      for (final row in byRes as List) {
        rows.add(Map<String, dynamic>.from(row));
      }
    } on PostgrestException catch (e) {
      if (e.code != '42703' && e.code != 'PGRST204') {
        debugPrint('[reservation/pricing] by reservation_id: $e');
      }
    }

    final foundResIds = rows
        .map((r) => r['reservation_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
    final missingOrderIds = <String>{};
    for (final r in byReservationId.values) {
      if (foundResIds.contains(r.id)) continue;
      final oid = r.orderId?.trim();
      if (oid != null && oid.isNotEmpty) missingOrderIds.add(oid);
    }
    if (missingOrderIds.isNotEmpty) {
      try {
        final byOrder = await supabase
            .from('payment_orders')
            .select(PaymentOrderColumns.selectPricing)
            .eq('user_id', userId)
            .inFilter('order_id', missingOrderIds.toList());
        for (final row in byOrder as List) {
          rows.add(Map<String, dynamic>.from(row));
        }
      } on PostgrestException catch (e) {
        if (e.code != '42703' && e.code != 'PGRST204') {
          debugPrint('[reservation/pricing] by order_id: $e');
        }
      }
    }

    final bestByReservation = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      var resKey = '';
      final numericResId = row['reservation_id']?.toString().trim() ?? '';
      if (numericResId.isNotEmpty &&
          byReservationId.containsKey(numericResId)) {
        resKey = numericResId;
      } else {
        final oid = row['order_id']?.toString().trim();
        if (oid != null && oid.isNotEmpty) {
          for (final r in byReservationId.values) {
            if (r.id == oid || r.orderId == oid) {
              resKey = r.id;
              break;
            }
          }
        }
        if (resKey.isEmpty && numericResId.isNotEmpty) {
          for (final r in byReservationId.values) {
            final rOid = r.orderId?.trim();
            final rowOid = row['order_id']?.toString().trim();
            if (rowOid != null &&
                rowOid.isNotEmpty &&
                (rOid == rowOid || r.id == rowOid)) {
              resKey = r.id;
              break;
            }
          }
        }
      }
      if (resKey.isEmpty) continue;

      final existing = bestByReservation[resKey];
      if (existing == null || _pricingRowRank(row) > _pricingRowRank(existing)) {
        bestByReservation[resKey] = row;
      }
    }

    final out = <String, ReservationPaymentPricing>{};
    for (final entry in bestByReservation.entries) {
      final pricing = ReservationPaymentPricing.fromPaymentOrderRowOrId(
        entry.value,
        fallbackPrice: byReservationId[entry.key]!.totalPrice,
      );
      if (pricing != null) out[entry.key] = pricing;
    }
    return out;
  }

  int _pricingRowRank(Map<String, dynamic> row) {
    final status = row['status']?.toString() ?? '';
    var rank = 0;
    if (PaymentOrderStatus.isPaid(status)) rank += 100;
    if (row['original_price'] != null) rank += 10;
    if ((row['user_coupon_id']?.toString() ?? '').isNotEmpty) rank += 5;
    if (((row['points_used'] as num?)?.toInt() ?? 0) > 0) rank += 5;
    return rank;
  }

  /// 예약·결제 변경 후 홈·내 예약 목록 갱신
  void notifyReservationListRefresh() {
    RentalService.signalListRefresh();
  }

  /// 결제 완료 포인트 적립 — RPC 내부 중복 방지, 실패해도 결제 흐름 유지
  Future<void> tryGrantReservationPoints({
    required String reservationId,
    required int amount,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    debugPrint(
      '[payment/points] tryGrantReservationPoints start: '
      'reservationId=$reservationId, p_amount=$amount, userId=$userId',
    );

    if (userId == null) {
      debugPrint('[payment/points] skip — not logged in');
      return;
    }
    if (reservationId.isEmpty) {
      debugPrint('[payment/points] skip — empty reservationId');
      return;
    }
    if (amount <= 0) {
      debugPrint('[payment/points] skip — p_amount is 0 or negative');
      return;
    }

    try {
      final data = await supabase.rpc(
        'grant_reservation_points',
        params: {
          'p_user_id': userId,
          'p_reservation_id': reservationId,
          'p_amount': amount,
        },
      );
      debugPrint('[payment/points] grant_reservation_points ok: $data');
    } on PostgrestException catch (e) {
      debugPrint(
        '[payment/points] grant_reservation_points PostgrestException: '
        '${e.code} ${e.message}',
      );
    } catch (e, st) {
      debugPrint('[payment/points] grant_reservation_points error: $e\n$st');
    }
  }

  /// 결제 주문에 제2운전자 정보 임시 저장 (예약 생성 전)
  Future<void> storeContractConsentOnOrder({
    required String orderId,
    required BookingContractConsent consent,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null || !consent.hasSecondDriverInfo) return;

    try {
      await supabase
          .from('payment_orders')
          .update({
            'second_driver_name': consent.secondDriverName!.trim(),
            'second_driver_license': consent.secondDriverLicense!.trim(),
          })
          .eq('order_id', orderId)
          .eq('user_id', userId);
    } on PostgrestException catch (e) {
      if (e.code == '42703' || e.code == 'PGRST204') return;
      rethrow;
    }
  }

  /// 대여 시작 전 — 제2운전자 저장 + 계약서 생성 RPC
  Future<void> applyContractConsentBeforeRentalStart({
    required String reservationId,
    required BookingContractConsent consent,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null || reservationId.isEmpty) return;

    if (consent.hasSecondDriverInfo) {
      try {
        await supabase
            .from('reservations')
            .update({
              'second_driver_name': consent.secondDriverName!.trim(),
              'second_driver_license': consent.secondDriverLicense!.trim(),
            })
            .eq('id', _reservationIdFilterForUpdate(reservationId))
            .eq('user_id', userId);
      } on PostgrestException catch (e) {
        if (e.code != '42703' && e.code != 'PGRST204') {
          debugPrint('[contract] second_driver update failed: $e');
        }
      }
    }

    await _tryGenerateRentalContract(reservationId);
  }

  /// 예약 생성 후 제2운전자 반영 + 계약서 생성 RPC
  Future<void> applyBookingContractAfterReservation({
    required String reservationId,
    required String orderId,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null || reservationId.isEmpty) return;

    final order = await findPaymentOrderByOrderId(orderId);
    final name = order?['second_driver_name']?.toString().trim();
    final license = order?['second_driver_license']?.toString().trim();

    if (name != null && name.isNotEmpty && license != null && license.isNotEmpty) {
      try {
        await supabase
            .from('reservations')
            .update({
              'second_driver_name': name,
              'second_driver_license': license,
            })
            .eq('id', _reservationIdFilterForUpdate(reservationId))
            .eq('user_id', userId);
      } on PostgrestException catch (e) {
        if (e.code != '42703' && e.code != 'PGRST204') {
          debugPrint('[contract] second_driver update failed: $e');
        }
      }
    }

    await _tryGenerateRentalContract(reservationId);
  }

  Object _reservationIdFilterForUpdate(String reservationId) {
    final parsed = int.tryParse(reservationId.trim());
    return parsed ?? reservationId;
  }

  Future<void> _tryGenerateRentalContract(String reservationId) async {
    try {
      final id = int.parse(reservationId.trim());
      await supabase.rpc('generate_rental_contract', params: {
        'p_reservation_id': id,
      });
      debugPrint('[contract] generate_rental_contract ok');
    } catch (e) {
      debugPrint('[contract] generate_rental_contract failed: $e');
    }
  }

  /// 결제 성공 콜백 — payment_orders → reservations 최종 저장
  Future<Map<String, dynamic>> saveReservationAfterPayment({
    required String paymentKey,
    required String orderId,
    required int amount,
  }) async {
    final existing = await findReservationByOrderId(orderId);
    if (existing != null) {
      return _ensureSavedResult(
        existing,
        paymentKey: paymentKey,
        orderId: orderId,
      );
    }

    try {
      final data = await supabase.rpc('finalize_reservation_after_payment', params: {
        'p_payment_key': paymentKey,
        'p_order_id': orderId,
        'p_amount': amount,
      });

      final map = _normalizeFinalizeResult(data);
      if (_hasReservationId(map)) {
        return _ensureSavedResult(
          map,
          paymentKey: paymentKey,
          orderId: orderId,
        );
      }
    } on PostgrestException catch (e) {
      if (!_isFinalizeFallbackError(e)) rethrow;
    } catch (e) {
      if (!_isFinalizeFallbackMessage(e.toString())) rethrow;
    }

    final direct = await _finalizeReservationDirect(
      paymentKey: paymentKey,
      orderId: orderId,
      amount: amount,
    );
    if (_hasReservationId(direct)) {
      return _ensureSavedResult(
        direct,
        paymentKey: paymentKey,
        orderId: orderId,
      );
    }

    final recovered = await findReservationByOrderId(orderId);
    if (recovered != null) {
      return _ensureSavedResult(
        recovered,
        paymentKey: paymentKey,
        orderId: orderId,
      );
    }

    throw Exception(
      '예약 저장에 실패했습니다.\n'
      'Supabase SQL Editor에서 fix_reservation_insert.sql 과 '
      'finalize_reservation_after_payment.sql 을 실행해주세요.',
    );
  }

  Future<Map<String, dynamic>> _ensureSavedResult(
    Map<String, dynamic> result, {
    required String paymentKey,
    required String orderId,
  }) async {
    final reservationId = _reservationIdFrom(result);
    if (reservationId.isNotEmpty) {
      await linkPaymentOrderReservation(
        orderId: orderId,
        reservationId: reservationId,
      );
      await ensureReservationConfirmed(
        reservationId: reservationId,
        paymentKey: paymentKey,
        orderId: orderId,
      );
    }
    return result;
  }

  /// 예약 저장 후 payment_orders.reservation_id 연결 (bigint/uuid 모두 text 저장)
  Future<void> linkPaymentOrderReservation({
    required String orderId,
    required String reservationId,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final rid = reservationId.trim();
    final oid = orderId.trim();
    if (rid.isEmpty || oid.isEmpty) return;

    try {
      await supabase
          .from('payment_orders')
          .update({
            'reservation_id': rid,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('order_id', oid)
          .eq('user_id', user.id);
      debugPrint(
        '[payment] payment_orders.reservation_id linked: '
        'orderId=$oid reservationId=$rid',
      );
    } catch (e, st) {
      debugPrint(
        '[payment] payment_orders.reservation_id link failed: $e\n$st',
      );
    }
  }

  /// pending → confirmed 보장 + payment_orders paid 연동
  Future<void> ensureReservationConfirmed({
    required String reservationId,
    String? paymentKey,
    String? orderId,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    Map<String, dynamic>? row;
    try {
      row = await supabase
          .from('reservations')
          .select('id, status, payment_status, payment_key, order_id')
          .eq('id', reservationId)
          .eq('user_id', user.id)
          .maybeSingle();
    } on PostgrestException catch (e) {
      if (e.code == '42703' || e.code == 'PGRST204') {
        row = await supabase
            .from('reservations')
            .select('id, status')
            .eq('id', reservationId)
            .eq('user_id', user.id)
            .maybeSingle();
      } else {
        rethrow;
      }
    }

    if (row == null) return;

    final status = row['status']?.toString() ?? '';
    final updatePayload = <String, dynamic>{};
    if (status != 'confirmed') {
      updatePayload['status'] = 'confirmed';
    }
    if (paymentKey != null && paymentKey.isNotEmpty) {
      final existingKey = row['payment_key']?.toString() ?? '';
      if (existingKey.isEmpty) updatePayload['payment_key'] = paymentKey;
    }
    if (orderId != null && orderId.isNotEmpty) {
      final existingOrder = row['order_id']?.toString() ?? '';
      if (existingOrder.isEmpty) updatePayload['order_id'] = orderId;
    }
    if (row.containsKey('payment_status') &&
        row['payment_status']?.toString() != 'paid') {
      updatePayload['payment_status'] = 'paid';
    }

    if (updatePayload.isNotEmpty) {
      try {
        await supabase
            .from('reservations')
            .update(updatePayload)
            .eq('id', reservationId)
            .eq('user_id', user.id);
      } on PostgrestException {
        if (updatePayload.containsKey('status') &&
            updatePayload.length == 1) {
          rethrow;
        }
        updatePayload.remove('payment_status');
        updatePayload.remove('payment_key');
        updatePayload.remove('order_id');
        if (updatePayload.isNotEmpty) {
          await supabase
              .from('reservations')
              .update(updatePayload)
              .eq('id', reservationId)
              .eq('user_id', user.id);
        }
      }
    }

    if (orderId != null && orderId.isNotEmpty) {
      await markPaymentOrderPaidSafe(
        orderId: orderId,
        paymentKey: paymentKey,
        reservationId: reservationId,
      );
    }
  }

  /// payment_orders.status 는 paid 만 사용 (confirmed 등 금지)
  Future<void> markPaymentOrderPaidSafe({
    required String orderId,
    String? paymentKey,
    String? reservationId,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final payload = PaymentOrderPayload.markPaid(
      paymentKey: paymentKey ?? '',
      reservationId: reservationId,
    );

    try {
      await supabase
          .from('payment_orders')
          .update(payload)
          .eq('order_id', orderId)
          .eq('user_id', user.id);
    } on PostgrestException catch (e) {
      final msg = e.message.toLowerCase();
      if (!msg.contains('payment_orders_status_check') &&
          !(msg.contains('payment_orders') && msg.contains('check constraint')) &&
          !msg.contains('42703') &&
          e.code != 'PGRST204') {
        rethrow;
      }
      final minimal = <String, dynamic>{
        'status': PaymentOrderStatus.paid,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (paymentKey != null && paymentKey.isNotEmpty) {
        minimal['payment_key'] = paymentKey;
        minimal['has_payment_key'] = true;
      }
      final rid = reservationId?.trim();
      if (rid != null && rid.isNotEmpty) {
        minimal['reservation_id'] = rid;
      }
      await supabase
          .from('payment_orders')
          .update(minimal)
          .eq('order_id', orderId)
          .eq('user_id', user.id);
    }

    if (reservationId != null && reservationId.trim().isNotEmpty) {
      await linkPaymentOrderReservation(
        orderId: orderId,
        reservationId: reservationId,
      );
    }
  }

  /// DB에 confirmed 예약이 조회될 때까지 짧게 재시도
  Future<void> waitUntilReservationReady(
    String reservationId, {
    int maxAttempts = 8,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final row = await supabase
          .from('reservations')
          .select('id, status')
          .eq('id', reservationId)
          .eq('user_id', user.id)
          .maybeSingle();

      if (row != null && row['status']?.toString() == 'confirmed') {
        return;
      }

      await ensureReservationConfirmed(reservationId: reservationId);
      if (attempt < maxAttempts - 1) {
        await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
      }
    }
  }

  Map<String, dynamic> _normalizeFinalizeResult(Object? data) {
    if (data == null) return {};
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  Future<Map<String, dynamic>?> findPaymentOrderByOrderId(String orderId) async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;

    return await supabase
        .from('payment_orders')
        .select(PaymentOrderColumns.selectSummary)
        .eq('order_id', orderId)
        .eq('user_id', user.id)
        .maybeSingle();
  }

  bool isPaymentOrderConfirmed(Map<String, dynamic>? order) {
    if (order == null) return false;
    final status = order['status']?.toString() ?? '';
    final paymentKey = order['payment_key']?.toString().trim() ?? '';
    final hasKeyFlag = order['has_payment_key'] == true;
    final hasKey = hasKeyFlag || paymentKey.isNotEmpty;
    return hasKey && PaymentOrderStatus.isPaid(status);
  }

  Future<Map<String, dynamic>?> findReservationByOrderId(String orderId) async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;

    try {
      final row = await supabase
          .from('reservations')
          .select('id, order_id, payment_key, total_price')
          .eq('order_id', orderId)
          .eq('user_id', user.id)
          .maybeSingle();
      if (row == null) return null;
      return {
        'reservationId': row['id']?.toString() ?? '',
        'orderId': orderId,
        'paymentKey': row['payment_key']?.toString(),
        'totalPrice': (row['total_price'] as num?)?.toInt(),
        'alreadyPaid': true,
      };
    } on PostgrestException catch (e) {
      if (e.code == '42703' || e.code == 'PGRST204') return null;
      rethrow;
    }
  }

  bool _hasReservationId(Map<String, dynamic> map) {
    final id = map['reservationId']?.toString() ??
        map['reservation_id']?.toString() ??
        '';
    return id.isNotEmpty;
  }

  dynamic _vehicleIdForInsert(Object? raw) {
    final text = raw?.toString() ?? '';
    if (text.isEmpty) return text;
    final asInt = int.tryParse(text);
    if (asInt != null) return asInt;
    return text;
  }

  bool _isFinalizeFallbackMessage(String message) {
    final msg = message.toLowerCase();
    return msg.contains('finalize_reservation') ||
        msg.contains('invalid input syntax for type uuid') ||
        msg.contains('reservation_id') ||
        msg.contains('does not exist') ||
        msg.contains('invalid_order_status') ||
        msg.contains('42703') ||
        msg.contains('예약 저장');
  }

  bool _isFinalizeFallbackError(PostgrestException error) {
    final msg = error.message.toLowerCase();
    return msg.contains('could not find the function') ||
        msg.contains('finalize_reservation_after_payment') ||
        msg.contains('invalid input syntax for type uuid') ||
        msg.contains('reservation_id') ||
        msg.contains('invalid_order_status') ||
        msg.contains('does not exist') ||
        error.code == '42703';
  }

  Future<Map<String, dynamic>> _finalizeReservationDirect({
    required String paymentKey,
    required String orderId,
    required int amount,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw const AuthException('로그인이 필요합니다.');
    }

    final existing = await supabase
        .from('reservations')
        .select('id, order_id')
        .eq('order_id', orderId)
        .eq('user_id', user.id)
        .maybeSingle();

    if (existing != null) {
      final reservationId = existing['id']?.toString() ?? '';
      await ensureReservationConfirmed(
        reservationId: reservationId,
        paymentKey: paymentKey,
        orderId: orderId,
      );
      return {
        'reservationId': reservationId,
        'orderId': orderId,
        'paymentKey': paymentKey,
        'alreadyPaid': true,
      };
    }

    final order = await supabase
        .from('payment_orders')
        .select(PaymentOrderColumns.selectDetail)
        .eq('order_id', orderId)
        .eq('user_id', user.id)
        .maybeSingle();

    if (order == null) {
      throw Exception('order_not_found');
    }

    final orderStatus = order['status']?.toString() ?? '';

    if (PaymentOrderStatus.isPaid(orderStatus)) {
      final linkedId = order['reservation_id']?.toString();
      if (linkedId != null && linkedId.isNotEmpty) {
        return {
          'reservationId': linkedId,
          'orderId': orderId,
          'paymentKey': order['payment_key']?.toString() ?? paymentKey,
          'alreadyPaid': true,
          'vehicleName': order['vehicle_name']?.toString(),
        };
      }
      // paid 이지만 reservations 미생성 — 아래에서 복구 저장
    } else if (orderStatus != PaymentOrderStatus.pending &&
        orderStatus != PaymentOrderStatus.failed) {
      throw Exception('invalid_order_status');
    }

    if ((order['total_price'] as num?)?.toInt() != amount) {
      throw Exception('amount_mismatch');
    }

    final overlaps = await hasOverlappingReservation(
      vehicleId: order['vehicle_id']?.toString() ?? '',
      startAt: DateTime.parse(order['start_time'] as String).toLocal(),
      endAt: DateTime.parse(order['end_time'] as String).toLocal(),
    );
    if (overlaps) {
      await supabase
          .from('payment_orders')
          .update(PaymentOrderPayload.markCancelled())
          .eq('order_id', orderId);
      throw const ReservationOverlapException();
    }

    final startUtc = DateTime.parse(order['start_time'] as String).toUtc();
    final endUtc = DateTime.parse(order['end_time'] as String).toUtc();

    final basePayload = {
      'user_id': user.id,
      'vehicle_id': _vehicleIdForInsert(order['vehicle_id']),
      'start_time': startUtc.toIso8601String(),
      'end_time': endUtc.toIso8601String(),
      'start_at': startUtc.toIso8601String(),
      'end_at': endUtc.toIso8601String(),
      'total_price': order['total_price'],
    };

    Map<String, dynamic> inserted;
    final variants = <Map<String, dynamic>>[
      {
        ...basePayload,
        'status': 'confirmed',
        'payment_key': paymentKey,
        'order_id': orderId,
        'payment_status': 'paid',
      },
      {
        ...basePayload,
        'status': 'pending',
        'payment_key': paymentKey,
        'order_id': orderId,
        'payment_status': 'paid',
      },
      {...basePayload, 'status': 'pending'},
    ];

    PostgrestException? lastError;
    inserted = {};
    for (final payload in variants) {
      try {
        inserted = Map<String, dynamic>.from(
          await supabase
              .from('reservations')
              .insert(payload)
              .select('id, status')
              .single(),
        );
        lastError = null;
        break;
      } on PostgrestException catch (e) {
        lastError = e;
        final msg = e.message.toLowerCase();
        if (e.code == '42703' ||
            e.code == 'PGRST204' ||
            msg.contains('schema cache') ||
            msg.contains('invalid input syntax')) {
          continue;
        }
        if (msg.contains('policy') || msg.contains('row-level security')) {
          continue;
        }
        rethrow;
      }
    }
    if (lastError != null) throw lastError;

    final reservationId = inserted['id']?.toString() ?? '';
    final insertedStatus = inserted['status']?.toString() ?? 'pending';

    if (insertedStatus != 'confirmed') {
      try {
        await supabase
            .from('reservations')
            .update({'status': 'confirmed'})
            .eq('id', reservationId)
            .eq('user_id', user.id);
      } on PostgrestException catch (e) {
        if (!e.message.toLowerCase().contains('policy') &&
            e.code != '42501') {
          rethrow;
        }
      }
    }

    await markPaymentOrderPaidSafe(
      orderId: orderId,
      paymentKey: paymentKey,
      reservationId: reservationId,
    );

    return {
      'reservationId': reservationId,
      'orderId': orderId,
      'paymentKey': paymentKey,
      'vehicleName': order['vehicle_name']?.toString(),
      'totalPrice': order['total_price'],
    };
  }
}

String friendlyUpdateReservationError(PostgrestException error) {
  final msg = error.message.toLowerCase();
  if (msg.contains('change_too_late')) {
    return '대여 시작 1시간 전부터는 예약 변경이 불가합니다.';
  }
  if (msg.contains('time_overlap') ||
      (msg.contains('overlap') && !msg.contains('change'))) {
    return '이미 예약된 시간입니다';
  }
  if (msg.contains('invalid_status')) {
    return '현재 상태에서는 예약을 변경할 수 없습니다.';
  }
  if (msg.contains('invalid_time_range')) {
    return '종료 시간은 시작 시간보다 뒤여야 합니다.';
  }
  if (msg.contains('reservation_not_found')) {
    return '예약 정보를 찾을 수 없습니다.';
  }
  if (msg.contains('could not find the function') ||
      msg.contains('update_reservation_for_me')) {
    return '예약 변경 RPC가 설치되지 않았습니다.\n'
        'Supabase에서 supabase/migrations/20260601170000_update_reservation_for_me.sql 을 실행해주세요.';
  }
  return error.message;
}

String friendlyReservationError(Object error) {
  if (error is ReservationChangeException) return error.message;
  if (error is ReservationOverlapException) return error.message;
  if (error is ReservationPermissionException) return error.message;
  if (error is PostgrestException) {
    final msg = error.message.toLowerCase();
    if (msg.contains('change_too_late')) {
      return '대여 시작 1시간 전부터는 예약 변경이 불가합니다.';
    }
    if (msg.contains('time_overlap')) {
      return '이미 예약된 시간입니다';
    }
    if (msg.contains(maintenanceActiveCode)) {
      return AppMaintenanceService.instance.cached.message;
    }
    if (msg.contains('user_blacklisted')) {
      return '서비스 이용이 제한된 계정입니다. 고객센터로 문의해주세요.';
    }
    if (msg.contains('insurance_expired')) {
      return '보험이 만료된 차량은 예약할 수 없습니다.';
    }
    if (msg.contains('vehicle_unavailable')) {
      return '현재 예약할 수 없는 차량입니다.';
    }
    if (msg.contains('overlap') || msg.contains('exclusion')) {
      return '이미 예약된 시간입니다';
    }
    if (msg.contains('foreign key') || msg.contains('violates foreign key')) {
      return '차량 ID 형식이 맞지 않습니다. Supabase vehicles.id 타입을 확인해주세요.';
    }
    if (msg.contains('row-level security') || msg.contains('policy')) {
      return '예약 insert가 거부되었습니다.\n'
          'Supabase에서 fix_reservation_insert.sql 을 실행하고, '
          '입주민·차량 complex_id가 같은지 확인해주세요.\n'
          '(${error.message})';
    }
    return error.message;
  }
  if (error is AuthException) return error.message;
  return error.toString();
}
