import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/payment_config.dart';
import '../models/payment_confirm_result.dart';
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

  String _friendlyError(Object error) {
    if (error is PostgrestException) {
      final msg = error.message.toLowerCase();
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
        return details['error'].toString();
      }
      if (details is String && details.isNotEmpty) return details;
      return error.reasonPhrase ?? '결제 승인 API 오류 (Edge Function 배포 확인)';
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
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);

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

    final prepared = await preparePayment(
      vehicle: vehicle,
      startTime: startTime,
      endTime: endTime,
      totalPrice: totalPrice,
    );
    await openTossPayment(prepared: prepared, method: method);
  }

  /// 결제 성공 콜백 — 토스 승인(Edge Function) 후 reservations 저장
  Future<PaymentConfirmResult> onPaymentSuccess({
    required String paymentKey,
    required String orderId,
    required int amount,
  }) async {
    try {
      return await _confirmViaEdgeFunction(
        paymentKey: paymentKey,
        orderId: orderId,
        amount: amount,
      );
    } on FunctionException catch (_) {
      // Edge Function 미배포 시 RPC로 reservations 저장 (로컬/테스트 fallback)
      return _finalizeViaRpc(
        paymentKey: paymentKey,
        orderId: orderId,
        amount: amount,
      );
    } catch (e) {
      final message = _friendlyError(e);
      if (message.contains('Edge Function') ||
          message.contains('payment-confirm') ||
          message.contains('Failed to fetch')) {
        return _finalizeViaRpc(
          paymentKey: paymentKey,
          orderId: orderId,
          amount: amount,
        );
      }
      throw Exception(message);
    }
  }

  Future<PaymentConfirmResult> _confirmViaEdgeFunction({
    required String paymentKey,
    required String orderId,
    required int amount,
  }) async {
    final body = await _invokeFunction('payment-confirm', {
      'paymentKey': paymentKey,
      'orderId': orderId,
      'amount': amount,
    });

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
}

String friendlyPaymentError(Object error) {
  if (error is Exception && error.toString().startsWith('Exception: ')) {
    return error.toString().substring('Exception: '.length);
  }
  return error.toString();
}
