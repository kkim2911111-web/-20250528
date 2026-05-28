import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_client.dart';

class ReservationOverlapException implements Exception {
  final String message;
  const ReservationOverlapException([this.message = '이미 예약된 시간입니다']);
  @override
  String toString() => message;
}

class ReservationPermissionException implements Exception {
  final String message;
  const ReservationPermissionException(this.message);
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
  }

  Future<bool> hasOverlappingReservation({
    required String vehicleId,
    required DateTime startAt,
    required DateTime endAt,
  }) async {
    final startUtc = startAt.toUtc().toIso8601String();
    final endUtc = endAt.toUtc().toIso8601String();

    for (final startCol in _startCols) {
      for (final endCol in _endCols) {
        try {
          final rows = await supabase
              .from('reservations')
              .select('id')
              .eq('vehicle_id', vehicleId)
              .inFilter('status', ['pending', 'confirmed', 'in_use'])
              .lt(startCol, endUtc)
              .gt(endCol, startUtc)
              .limit(1);
          return rows.isNotEmpty;
        } on PostgrestException catch (e) {
          if (e.code == '42703') continue;
          rethrow;
        }
      }
    }
    return false;
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

  /// 결제 성공 콜백 — payment_orders → reservations 최종 저장
  Future<Map<String, dynamic>> saveReservationAfterPayment({
    required String paymentKey,
    required String orderId,
    required int amount,
  }) async {
    final data = await supabase.rpc('finalize_reservation_after_payment', params: {
      'p_payment_key': paymentKey,
      'p_order_id': orderId,
      'p_amount': amount,
    });

    if (data is Map<String, dynamic>) return data;
    return Map<String, dynamic>.from(data as Map);
  }
}

String friendlyReservationError(Object error) {
  if (error is ReservationOverlapException) return error.message;
  if (error is ReservationPermissionException) return error.message;
  if (error is PostgrestException) {
    final msg = error.message.toLowerCase();
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
