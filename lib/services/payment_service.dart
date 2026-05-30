import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/payment_config.dart';
import '../models/payment_confirm_result.dart';
import '../models/reservation.dart';
import '../models/vehicle.dart';
import '../supabase_client.dart';
import 'reservation_service.dart';
import 'toss_payments.dart';

class PreparePaymentResult {
  final String orderId;
  final int amount;
  final String orderName;
  final String customerKey;

  const PreparePaymentResult({
    required this.orderId,
    required this.amount,
    required this.orderName,
    required this.customerKey,
  });
}

class PaymentService {
  final _toss = TossPaymentsLauncher();
  final _reservationService = ReservationService();

  /// 동일 orderId 중복 승인 요청 방지 (페이지 재진입·initState 이중 실행 대비)
  static final _confirmInflight = <String, Future<PaymentConfirmResult>>{};

  String _friendlyError(Object error) {
    if (error is PostgrestException) {
      final msg = error.message.toLowerCase();
      if (msg.contains('payment_orders_status_check') ||
          (msg.contains('payment_orders') && msg.contains('check constraint'))) {
        return 'payment_orders status 값이 DB 허용 범위를 벗어났습니다.\n'
            '허용값: pending, paid, failed, cancelled\n'
            'Supabase에서 fix_payment_orders_status_check.sql 을 실행해주세요.';
      }
      if (msg.contains('not_authenticated')) {
        return '로그인이 필요합니다. 다시 로그인한 뒤 결제를 시도해주세요.';
      }
      if (msg.contains('not_approved')) {
        return '입주민 승인이 필요합니다.';
      }
      if (msg.contains('vehicle_not_in_complex')) {
        return '내 단지 차량만 예약할 수 있습니다.';
      }
      if (msg.contains('time_overlap')) {
        return '이미 예약된 시간입니다.';
      }
      if (msg.contains('payment_orders') && msg.contains('does not exist')) {
        return 'payment_orders 테이블이 없습니다.\n'
            'Supabase에서 create_payment_orders_table.sql 을 실행해주세요.';
      }
      if (msg.contains('prepare_payment_order') &&
          msg.contains('could not find')) {
        return '결제 준비 RPC가 없습니다.\n'
            'Supabase에서 prepare_payment_order_rpc.sql 을 실행해주세요.';
      }
      if (msg.contains('finalize_reservation_after_payment') &&
          msg.contains('could not find')) {
        return '예약 저장 RPC가 없습니다.\n'
            'Supabase에서 finalize_reservation_after_payment.sql 을 실행해주세요.';
      }
      if (msg.contains('order_not_found')) {
        return '결제 주문을 찾을 수 없습니다.';
      }
      if (msg.contains('amount_mismatch')) {
        return '결제 금액이 일치하지 않습니다.';
      }
      return error.message;
    }
    if (error is FunctionException) {
      final details = error.details;
      if (details is Map && details['error'] != null) {
        return _mapCancelError(details['error'].toString());
      }
      if (details is String && details.isNotEmpty) {
        final lower = details.toLowerCase();
        if (lower.contains('toss_secret_key')) {
          return 'TOSS_SECRET_KEY 시크릿이 Edge Function에 연결되지 않았습니다.\n'
              'Supabase 대시보드 → Edge Functions → Secrets 확인';
        }
        return _mapCancelError(details);
      }
      return error.reasonPhrase ?? '결제 API 오류 (Edge Function 배포 확인)';
    }
    if (error is StateError) return error.message;
    final text = error.toString();
    if (text.startsWith('Exception: ')) {
      return text.substring('Exception: '.length);
    }
    return text;
  }

  Future<Map<String, dynamic>> _invokeFunction(
    String functionName,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await supabase.functions.invoke(
        functionName,
        body: body,
      );

      final data = response.data;
      if (data is Map<String, dynamic>) {
        if (data['error'] != null) {
          throw Exception(_mapCancelError(data['error'].toString()));
        }
        return data;
      }
      if (data is Map) {
        final map = Map<String, dynamic>.from(data);
        if (map['error'] != null) {
          throw Exception(_mapCancelError(map['error'].toString()));
        }
        return map;
      }

      throw Exception('결제 API 응답 형식 오류');
    } on FunctionException catch (e) {
      throw Exception(_friendlyError(e));
    }
  }

  Future<PreparePaymentResult> preparePayment({
    required Vehicle vehicle,
    required DateTime startTime,
    required DateTime endTime,
    required int totalPrice,
  }) async {
    if (!isSupabaseInitialized) {
      throw StateError(
        '서버(Supabase)에 연결되지 않았습니다.\n'
        '앱을 새로고침하거나 .env의 SUPABASE_URL·SUPABASE_ANON_KEY를 확인해주세요.',
      );
    }
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw const AuthException('로그인이 필요합니다. 다시 로그인한 뒤 결제를 시도해주세요.');
    }
    try {
      final data = await supabase.rpc('prepare_payment_order', params: {
        'p_vehicle_id': vehicle.id,
        'p_vehicle_name': vehicle.name,
        'p_start_time': startTime.toUtc().toIso8601String(),
        'p_end_time': endTime.toUtc().toIso8601String(),
        'p_total_price': totalPrice,
      });

      final map = data is Map<String, dynamic>
          ? data
          : Map<String, dynamic>.from(data as Map);

      return PreparePaymentResult(
        orderId: map['orderId'] as String,
        amount: (map['amount'] as num).toInt(),
        orderName: map['orderName'] as String,
        customerKey: map['customerKey'] as String,
      );
    } on PostgrestException catch (e) {
      throw Exception(_friendlyError(e));
    }
  }

  Future<void> openTossPayment({
    required PreparePaymentResult prepared,
    required TossPaymentMethod method,
  }) async {
    if (!_toss.isReady) {
      throw StateError(
        '토스페이먼츠 SDK가 로드되지 않았습니다.\n'
        '페이지를 새로고침(F5) 후 다시 시도해주세요.',
      );
    }

    final user = supabase.auth.currentUser;
    await _toss.requestPayment(
      orderId: prepared.orderId,
      orderName: prepared.orderName,
      amount: prepared.amount,
      customerKey: prepared.customerKey,
      method: method,
      customerEmail: user?.email,
      customerName: user?.email?.split('@').first,
    );
  }

  /// 예약하기 → 결제창 (Flutter Web)
  Future<void> startBookingPayment({
    required Vehicle vehicle,
    required DateTime startTime,
    required DateTime endTime,
    required int totalPrice,
    required TossPaymentMethod method,
  }) async {
    if (!kIsWeb) {
      throw UnsupportedError('결제는 Flutter Web에서만 지원합니다.');
    }

    if (!PaymentConfig.isConfigured) {
      throw StateError('TOSS_CLIENT_KEY가 필요합니다.');
    }

    debugPrint(
      '[payment] TOSS key from ${PaymentConfig.keySource}: ${PaymentConfig.maskedKey}',
    );

    final user = supabase.auth.currentUser;
    if (user == null) {
      throw const AuthException('로그인이 필요합니다. 다시 로그인한 뒤 결제를 시도해주세요.');
    }

    final prepared = await preparePayment(
      vehicle: vehicle,
      startTime: startTime,
      endTime: endTime,
      totalPrice: totalPrice,
    );
    await openTossPayment(prepared: prepared, method: method);
  }

  /// API 호출 전 — DB에 이미 저장된 결제/예약인지 조회 (네트워크 승인 생략용)
  Future<PaymentConfirmResult?> tryResolveExistingPayment({
    required String orderId,
    String? paymentKey,
  }) async {
    final existing =
        await _reservationService.findReservationByOrderId(orderId);
    if (existing != null) {
      return PaymentConfirmResult.fromMap(existing);
    }

    final paymentOrder =
        await _reservationService.findPaymentOrderByOrderId(orderId);
    if (!_reservationService.isPaymentOrderConfirmed(paymentOrder)) {
      return null;
    }

    final linkedId = paymentOrder?['reservation_id']?.toString() ?? '';
    if (linkedId.isEmpty) return null;

    return PaymentConfirmResult(
      reservationId: linkedId,
      orderId: orderId,
      paymentKey: paymentKey ?? paymentOrder?['payment_key']?.toString() ?? '',
      alreadyPaid: true,
    );
  }

  /// 결제 성공 콜백 — 토스 승인 후 reservations 저장
  Future<PaymentConfirmResult> onPaymentSuccess({
    required String paymentKey,
    required String orderId,
    required int amount,
  }) {
    final existingFuture = _confirmInflight[orderId];
    if (existingFuture != null) {
      debugPrint(
        '[payment/success] reuse in-flight confirm for orderId=$orderId',
      );
      return existingFuture;
    }

    final future = _onPaymentSuccessOnce(
      paymentKey: paymentKey,
      orderId: orderId,
      amount: amount,
    );
    _confirmInflight[orderId] = future;
    return future.whenComplete(() => _confirmInflight.remove(orderId));
  }

  Future<PaymentConfirmResult> _onPaymentSuccessOnce({
    required String paymentKey,
    required String orderId,
    required int amount,
  }) async {
    final existing = await _reservationService.findReservationByOrderId(orderId);
    if (existing != null) {
      debugPrint(
        '[payment/success] reservation already exists for orderId=$orderId',
      );
      return _finalizePaymentResult(
        PaymentConfirmResult.fromMap(existing),
        paymentKey: paymentKey,
        orderId: orderId,
      );
    }

    final paymentOrder =
        await _reservationService.findPaymentOrderByOrderId(orderId);
    if (_reservationService.isPaymentOrderConfirmed(paymentOrder)) {
      debugPrint(
        '[payment/success] payment order already confirmed — skip Toss API: '
        'orderId=$orderId, status=${paymentOrder?['status']}',
      );
      final linkedId = paymentOrder?['reservation_id']?.toString() ?? '';
      if (linkedId.isNotEmpty) {
        return _finalizePaymentResult(
          PaymentConfirmResult(
            reservationId: linkedId,
            orderId: orderId,
            paymentKey: paymentKey,
            alreadyPaid: true,
          ),
          paymentKey: paymentKey,
          orderId: orderId,
        );
      }
      return _finalizePaymentResult(
        await _finalizeViaRpc(
          paymentKey: paymentKey,
          orderId: orderId,
          amount: amount,
        ),
        paymentKey: paymentKey,
        orderId: orderId,
      );
    }

    Object? lastError;

    // Edge Function — 토스 승인 API(POST /v1/payments/confirm) 호출
    PaymentConfirmResult? edgeResult;
    try {
      debugPrint('[payment/success] calling Edge Function payment-confirm...');
      edgeResult = await _confirmViaEdgeFunction(
        paymentKey: paymentKey,
        orderId: orderId,
        amount: amount,
      );
    } on FunctionException catch (e) {
      debugPrint('[payment/success] Edge Function error: $e');
      lastError = e;
    } catch (e) {
      debugPrint('[payment/success] Edge Function error: $e');
      lastError = e;
    }

    if (edgeResult != null && edgeResult.reservationId.isNotEmpty) {
      return _finalizePaymentResult(
        edgeResult,
        paymentKey: paymentKey,
        orderId: orderId,
      );
    }

    // RPC fallback (Edge 실패 또는 TOSS_SECRET_KEY 미설정)
    try {
      debugPrint('[payment/success] Edge failed — trying RPC finalize...');
      final rpcResult = await _finalizeViaRpc(
        paymentKey: paymentKey,
        orderId: orderId,
        amount: amount,
      );
      if (rpcResult.reservationId.isNotEmpty) {
        return _finalizePaymentResult(
          rpcResult,
          paymentKey: paymentKey,
          orderId: orderId,
        );
      }
    } catch (e) {
      debugPrint('[payment/success] RPC finalize error: $e');
      lastError ??= e;
    }

    final recovered = await _reservationService.findReservationByOrderId(orderId);
    if (recovered != null) {
      return _finalizePaymentResult(
        PaymentConfirmResult.fromMap(recovered),
        paymentKey: paymentKey,
        orderId: orderId,
      );
    }

    if (lastError != null) {
      throw Exception(_friendlyError(lastError));
    }
    throw Exception(
      '결제는 완료되었으나 예약 저장에 실패했습니다.\n'
      'Supabase SQL Editor에서 fix_reservation_insert.sql 과 '
      'finalize_reservation_after_payment.sql 을 실행한 뒤 '
      '결제 완료 화면을 새로고침해주세요.',
    );
  }

  Future<PaymentConfirmResult> _finalizePaymentResult(
    PaymentConfirmResult result, {
    required String paymentKey,
    required String orderId,
  }) async {
    if (result.reservationId.isEmpty) return result;

    await _reservationService.ensureReservationConfirmed(
      reservationId: result.reservationId,
      paymentKey: paymentKey,
      orderId: orderId,
    );
    await _reservationService.waitUntilReservationReady(result.reservationId);
    return result;
  }

  Future<PaymentConfirmResult> _confirmViaEdgeFunction({
    required String paymentKey,
    required String orderId,
    required int amount,
  }) async {
    debugPrint(
      '[payment/success] Edge payment-confirm request: '
      'paymentKey=$paymentKey, orderId=$orderId, amount=$amount',
    );

    final body = await _invokeFunction('payment-confirm', {
      'paymentKey': paymentKey,
      'orderId': orderId,
      'amount': amount,
    });

    debugPrint('[payment/success] Edge payment-confirm response: $body');

    if (body['payment'] != null) {
      debugPrint(
        '[payment/success] Toss confirm API response: ${body['payment']}',
      );
    }

    if (body['error'] != null) {
      throw Exception(body['error'].toString());
    }

    return PaymentConfirmResult(
      reservationId: body['reservationId']?.toString() ?? '',
      orderId: body['orderId']?.toString() ?? orderId,
      paymentKey: body['paymentKey']?.toString() ?? paymentKey,
      alreadyPaid: body['alreadyPaid'] == true,
    );
  }

  Future<PaymentConfirmResult> _finalizeViaRpc({
    required String paymentKey,
    required String orderId,
    required int amount,
  }) async {
    try {
      final data = await _reservationService.saveReservationAfterPayment(
        paymentKey: paymentKey,
        orderId: orderId,
        amount: amount,
      );
      return PaymentConfirmResult.fromMap(data);
    } on PostgrestException catch (e) {
      throw Exception(_friendlyError(e));
    } catch (e) {
      throw Exception(_friendlyError(e));
    }
  }

  @Deprecated('Use onPaymentSuccess instead')
  Future<String?> confirmPayment({
    required String paymentKey,
    required String orderId,
    required int amount,
  }) async {
    final result = await onPaymentSuccess(
      paymentKey: paymentKey,
      orderId: orderId,
      amount: amount,
    );
    return result.reservationId.isEmpty ? null : result.reservationId;
  }

  Future<void> cancelPayment({
    required String orderId,
    String? code,
    String? message,
  }) async {
    try {
      await _invokeFunction('payment-cancel', {
        'orderId': orderId,
        'code': code,
        'message': message,
      });
    } catch (_) {
      // 취소 API 실패는 UI 복귀를 막지 않음
    }
  }

  /// 확정 예약 취소 + Toss 환불 (payment-cancel Edge Function, TOSS_SECRET_KEY)
  Future<Map<String, dynamic>> cancelConfirmedReservation({
    required String reservationId,
  }) async {
    try {
      return await _invokeFunction('payment-cancel', {
        'reservationId': reservationId,
      });
    } on FunctionException catch (e) {
      if (_isMissingFunctionError(e)) {
        return _cancelReservationViaRpc(reservationId);
      }
      throw Exception(_friendlyError(e));
    } catch (e) {
      final message = _friendlyError(e);
      if (_shouldCancelViaRpcFallback(message)) {
        return _cancelReservationViaRpc(reservationId);
      }
      throw Exception(message);
    }
  }

  bool _isMissingFunctionError(FunctionException error) {
    final details = error.details?.toString().toLowerCase() ?? '';
    final reason = error.reasonPhrase?.toLowerCase() ?? '';
    return details.contains('not found') ||
        reason.contains('not found') ||
        error.status == 404;
  }

  bool _shouldCancelViaRpcFallback(String message) {
    final lower = message.toLowerCase();
    return lower.contains('failed to fetch') ||
        lower.contains('payment-cancel') ||
        lower.contains('v.name') ||
        lower.contains('does not exist') ||
        lower.contains('42703') ||
        lower.contains('cancel_reservation_for_me');
  }

  Future<Map<String, dynamic>> _cancelReservationViaRpc(
    String reservationId,
  ) async {
    try {
      final data = await supabase.rpc('cancel_reservation_for_me', params: {
        'p_reservation_id': reservationId,
      });
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return {'ok': true};
    } on PostgrestException catch (e) {
      throw Exception(_friendlyCancelError(e));
    }
  }
}

String _mapCancelError(String message) {
  final lower = message.toLowerCase();
  if (lower.contains('cancel_too_late') ||
      lower.contains('1시간') ||
      lower.contains('60분')) {
    return ReservationCancelMessages.tooLate;
  }
  if (lower.contains('invalid input syntax for type uuid')) {
    return '예약 취소 처리 중 ID 형식 오류가 발생했습니다. 잠시 후 다시 시도해주세요.';
  }
  return message;
}

String _friendlyCancelError(PostgrestException error) {
  final msg = error.message.toLowerCase();
  if (msg.contains('cancel_too_late')) {
    return ReservationCancelMessages.tooLate;
  }
  if (msg.contains('invalid_status')) {
    return '취소할 수 없는 예약 상태입니다.';
  }
  if (msg.contains('reservation_not_found')) {
    return '예약 정보를 찾을 수 없습니다.';
  }
  if (msg.contains('cancel_reservation_for_me') &&
      msg.contains('could not find')) {
    return '예약 취소 RPC가 설치되지 않았습니다.\n'
        'Supabase에서 cancel_reservation_rpc.sql 을 실행해주세요.';
  }
  return error.message;
}

String friendlyPaymentError(Object error) {
  if (error is StateError) return error.message;
  if (error is AuthException) {
    return error.message.isNotEmpty
        ? error.message
        : '로그인이 필요합니다. 다시 로그인해주세요.';
  }
  if (error is PostgrestException) {
    return error.message;
  }
  final text = error.toString();
  if (text.contains('AbortError') ||
      text.contains('push service not available')) {
    return '알림 설정 오류입니다. 예약·결제는 계속 진행할 수 있습니다.';
  }
  if (text.contains('알 수 없') || text.toLowerCase().contains('unknown')) {
    if (text.toLowerCase().contains('client') ||
        text.contains('clientKey') ||
        text.contains('인증')) {
      return 'TOSS_CLIENT_KEY가 올바르지 않습니다.\n'
          '.env의 TOSS_CLIENT_KEY(test_ck_...)를 확인하거나 '
          'flutter run 시 잘못된 --dart-define 값이 덮어쓰지 않는지 확인해주세요.\n'
          '(상세: $text)';
    }
    return '결제 요청 중 오류가 발생했습니다.\n'
        '로그인 상태와 TOSS_CLIENT_KEY 설정을 확인한 뒤 다시 시도해주세요.\n'
        '(상세: $text)';
  }
  if (text.startsWith('Exception: ')) {
    return text.substring('Exception: '.length);
  }
  return text;
}
