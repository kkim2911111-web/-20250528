import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/reservation.dart';
import '../supabase_client.dart';
import '../constants/payment_order_status.dart';
import '../utils/booking_eligibility.dart';
import 'my_page_service.dart';
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

class ReservationService {
  static const _startCols = ['start_time', 'start_at'];
  static const _endCols = ['end_time', 'end_at'];

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
        .select('id, complex_id, model_name')
        .eq('id', vehicleId)
        .maybeSingle();

    if (vehicle == null) {
      throw const ReservationPermissionException(
        '차량 정보를 불러올 수 없습니다. 차량이 내 단지에 등록되어 있는지 확인해주세요.',
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
  }) async {
    if (await _vehicleHasInUseReservation(vehicleId)) {
      return VehicleBookingBlockReason.inUse;
    }
    final overlaps = await _hasConfirmedOrPendingTimeOverlap(
      vehicleId: vehicleId,
      startAt: startAt,
      endAt: endAt,
    );
    if (overlaps) return VehicleBookingBlockReason.timeOverlap;
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

  Future<bool> _vehicleHasInUseReservation(String vehicleId) async {
    final vid = _vehicleIdForQuery(vehicleId);
    try {
      final rows = await supabase
          .from('reservations')
          .select('id')
          .eq('vehicle_id', vid)
          .eq('status', 'in_use')
          .limit(1);
      return rows.isNotEmpty;
    } on PostgrestException catch (e) {
      if (e.code == '42703') return false;
      rethrow;
    }
  }

  Future<bool> _hasConfirmedOrPendingTimeOverlap({
    required String vehicleId,
    required DateTime startAt,
    required DateTime endAt,
  }) async {
    final startUtc = startAt.toUtc().toIso8601String();
    final endUtc = endAt.toUtc().toIso8601String();
    final vid = _vehicleIdForQuery(vehicleId);

    for (final startCol in _startCols) {
      for (final endCol in _endCols) {
        try {
          final rows = await supabase
              .from('reservations')
              .select('id')
              .eq('vehicle_id', vid)
              .inFilter('status', ['pending', 'confirmed'])
              .lt(startCol, endUtc)
              .gt(endCol, startUtc)
              .limit(1);
          if (rows.isNotEmpty) return true;
        } on PostgrestException catch (e) {
          if (e.code == '42703') continue;
          rethrow;
        }
      }
    }
    return false;
  }

  dynamic _vehicleIdForQuery(String vehicleId) {
    final parsed = int.tryParse(vehicleId.trim());
    return parsed ?? vehicleId;
  }

  Future<void> _insertReservation(Map<String, dynamic> payload) async {
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
        await supabase.from('reservations').insert(data);
        return;
      } on PostgrestException catch (e) {
        lastError = e;
        if (e.code == '42703' || e.code == '23502') continue;
        rethrow;
      }
    }
    if (lastError != null) throw lastError;
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
      await supabase.rpc('create_reservation_for_me', params: {
        'p_vehicle_id': vehicleId,
        'p_start_time': startUtc.toIso8601String(),
        'p_end_time': endUtc.toIso8601String(),
        'p_total_price': totalPrice,
      });
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
      if (msg.contains('could not find the function') ||
          msg.contains('create_reservation_for_me')) {
        // RPC 미설치 → direct insert fallback
      } else {
        rethrow;
      }
    }

    await _insertReservation({
      'user_id': user.id,
      'vehicle_id': vehicleId,
      'start_time': startUtc.toIso8601String(),
      'end_time': endUtc.toIso8601String(),
      'start_at': startUtc.toIso8601String(),
      'end_at': endUtc.toIso8601String(),
      'total_price': totalPrice,
      'status': 'pending',
    });
  }

  Future<void> createReservation({
    required String vehicleId,
    required DateTime startAt,
    required DateTime endAt,
    int totalPrice = 0,
  }) async {
    await createBooking(
      vehicleId: vehicleId,
      startTime: startAt,
      endTime: endAt,
      totalPrice: totalPrice,
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
      await ensureReservationConfirmed(
        reservationId: reservationId,
        paymentKey: paymentKey,
        orderId: orderId,
      );
    }
    return result;
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
      await supabase.from('payment_orders').update(
        PaymentOrderPayload.markPaid(
          paymentKey: paymentKey ?? '',
          reservationId: reservationId,
        ),
      ).eq('order_id', orderId).eq('user_id', user.id);
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

    await supabase.from('payment_orders').update(
      PaymentOrderPayload.markPaid(
        paymentKey: paymentKey,
        reservationId: reservationId,
      ),
    ).eq('order_id', orderId);

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
    return ReservationCancelMessages.changeTooLate;
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
      return ReservationCancelMessages.changeTooLate;
    }
    if (msg.contains('time_overlap')) {
      return '이미 예약된 시간입니다';
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
