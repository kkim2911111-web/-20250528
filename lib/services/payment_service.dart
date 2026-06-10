import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/payment_config.dart';
import '../constants/payment_order_status.dart';
import '../models/payment_confirm_result.dart';
import '../models/reservation.dart';
import '../models/vehicle.dart';
import '../screens/main_shell.dart';
import '../screens/my_reservations_screen.dart';
import '../screens/payment_fail_screen.dart';
import '../screens/payment_success_screen.dart';
import '../screens/toss_billing_webview_screen.dart';
import '../screens/toss_payment_webview_screen.dart';
import '../supabase_client.dart';
import '../utils/maintenance_error.dart';
import '../utils/network_retry.dart';
import 'app_maintenance_service.dart';
import '../utils/rental_pricing.dart';
import 'reservation_service.dart';
import 'toss_payments.dart';

/// 결제카드(빌링키) 등록·변경 성공 안내 — 마이페이지·온보딩·웹 리다이렉트 공통
const paymentCardRegistrationSuccessMessage =
    '결제카드 등록이 완료되었습니다.';

/// 쿠폰+포인트로 결제금액 0원일 때 안내
const zeroAmountBookingSnackMessage =
    '🎉 쿠폰과 포인트로 전액 할인되었습니다!\n'
    '결제 없이 예약이 완료됩니다.';

bool isPaymentOrderStatusConstraintError(Object error) {
  final msg = error is PostgrestException
      ? error.message.toLowerCase()
      : error.toString().toLowerCase();
  return msg.contains('payment_orders_status_check') ||
      (msg.contains('payment_orders') && msg.contains('check constraint')) ||
      msg.contains('payment_orders status');
}

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
            '허용값: ${PaymentOrderStatus.allowed.join(', ')}\n'
            'Supabase에서 fix_payment_orders_status_check.sql 을 실행해주세요.';
      }
      if (msg.contains(maintenanceActiveCode)) {
        return AppMaintenanceService.instance.cached.message;
      }
      if (msg.contains('not_authenticated')) {
        return '로그인이 필요합니다. 다시 로그인한 뒤 결제를 시도해주세요.';
      }
      if (msg.contains('not_approved')) {
        return '입주민 승인이 필요합니다.';
      }
      if (msg.contains('license_not_verified')) {
        return '면허 심사 승인 후 예약할 수 있습니다.\n마이페이지에서 면허 등록·심사 상태를 확인해주세요.';
      }
      if (msg.contains('vehicle_not_in_complex')) {
        return '내 단지 차량만 예약할 수 있습니다.';
      }
      if (msg.contains('time_overlap')) {
        return '이미 예약된 시간입니다.';
      }
      if (msg.contains('price_mismatch') ||
          msg.contains('original_price_required')) {
        return '요금 정보가 올바르지 않습니다. 다시 시도해주세요.';
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
      if (details is Map) {
        if (details['code']?.toString() == maintenanceActiveCode ||
            details['error']?.toString() == maintenanceActiveCode) {
          return AppMaintenanceService.instance.cached.message;
        }
        if (details['error'] != null) {
          return _mapCancelError(details['error'].toString());
        }
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
      final response = await withNetworkRetry(
        () => supabase.functions.invoke(
          functionName,
          body: body,
        ),
      );

      final data = response.data;
      if (data is Map<String, dynamic>) {
        if (data['code']?.toString() == maintenanceActiveCode ||
            data['error']?.toString() == maintenanceActiveCode) {
          throw Exception(AppMaintenanceService.instance.cached.message);
        }
        if (data['error'] != null) {
          throw Exception(_mapCancelError(data['error'].toString()));
        }
        return data;
      }
      if (data is Map) {
        final map = Map<String, dynamic>.from(data);
        if (map['code']?.toString() == maintenanceActiveCode ||
            map['error']?.toString() == maintenanceActiveCode) {
          throw Exception(AppMaintenanceService.instance.cached.message);
        }
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
    required RentalType rentalType,
    required int totalPrice,
    required int originalPrice,
    String? userCouponId,
    int pointsUsed = 0,
  }) async {
    if (!isSupabaseInitialized) {
      throw StateError(
        '서버(Supabase)에 연결되지 않았습니다.\n'
        '네트워크 연결을 확인한 뒤 다시 시도해주세요.',
      );
    }
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw const AuthException('로그인이 필요합니다. 다시 로그인한 뒤 결제를 시도해주세요.');
    }
    try {
      final data = await withNetworkRetry(
        () => supabase.rpc('prepare_payment_order', params: {
          'p_vehicle_id': vehicle.id,
          'p_vehicle_name': vehicle.name,
          'p_start_time': startTime.toUtc().toIso8601String(),
          'p_end_time': endTime.toUtc().toIso8601String(),
          'p_total_price': totalPrice,
          'p_user_coupon_id': userCouponId,
          'p_points_used': pointsUsed,
          'p_original_price': originalPrice,
          'p_rental_type': rentalType.dbValue,
        }),
      );

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
    required BuildContext context,
    required PreparePaymentResult prepared,
    required TossPaymentMethod method,
  }) async {
    final user = supabase.auth.currentUser;

    // Web(테스트) — JS SDK
    if (kIsWeb) {
      if (!_toss.isReady) {
        throw StateError(
          '토스페이먼츠 SDK가 로드되지 않았습니다.\n'
          '페이지를 새로고침(F5) 후 다시 시도해주세요.',
        );
      }

      await _toss.requestPayment(
        orderId: prepared.orderId,
        orderName: prepared.orderName,
        amount: prepared.amount,
        customerKey: prepared.customerKey,
        method: method,
        customerEmail: user?.email,
        customerName: user?.email?.split('@').first,
      );
      return;
    }

    // Android/iOS — WebView 결제창
    final params = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TossPaymentWebViewScreen(
          orderId: prepared.orderId,
          orderName: prepared.orderName,
          amount: prepared.amount,
          customerKey: prepared.customerKey,
          method: method,
          customerEmail: user?.email,
          customerName: user?.email?.split('@').first,
        ),
      ),
    );

    if (!context.mounted) return;

    if (params == null) {
      throw StateError('결제가 취소되었습니다.');
    }

    if (params['_route'] == 'fail') {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => PaymentFailScreen(queryParams: params),
        ),
      );
      return;
    }

    final paymentKey = params['paymentKey'] ?? params['payment_key'];
    if (paymentKey == null || paymentKey.isEmpty) {
      throw StateError(
        '결제 승인 정보를 받지 못했습니다.\n'
        '다시 예약하기를 시도해주세요.',
      );
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PaymentSuccessScreen(queryParams: params),
      ),
    );
  }

  /// 예약하기 → 결제창
  Future<void> startBookingPayment({
    required BuildContext context,
    required Vehicle vehicle,
    required DateTime startTime,
    required DateTime endTime,
    required RentalType rentalType,
    required int totalPrice,
    required int originalPrice,
    String? userCouponId,
    int pointsUsed = 0,
    required TossPaymentMethod method,
  }) async {
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
      rentalType: rentalType,
      totalPrice: totalPrice,
      originalPrice: originalPrice,
      userCouponId: userCouponId,
      pointsUsed: pointsUsed,
    );

    if (totalPrice <= 0) {
      await _completeZeroAmountBooking(
        context: context,
        prepared: prepared,
        userCouponId: userCouponId,
        pointsUsed: pointsUsed,
      );
      return;
    }

    await openTossPayment(
      context: context,
      prepared: prepared,
      method: method,
    );
  }

  Future<void> _completeZeroAmountBooking({
    required BuildContext context,
    required PreparePaymentResult prepared,
    String? userCouponId,
    int pointsUsed = 0,
  }) async {
    final paymentKey = 'free_${prepared.orderId}';
    final saved = await _reservationService.saveReservationAfterPayment(
      paymentKey: paymentKey,
      orderId: prepared.orderId,
      amount: 0,
    );

    final reservationId = saved['reservationId']?.toString() ??
        saved['reservation_id']?.toString() ??
        '';
    if (reservationId.isNotEmpty) {
      await _reservationService.ensureReservationConfirmed(
        reservationId: reservationId,
        paymentKey: paymentKey,
        orderId: prepared.orderId,
      );
      await _reservationService.tryApplyBookingDiscounts(
        orderId: prepared.orderId,
        reservationId: reservationId,
      );
      await _reservationService.markPaymentOrderPaidSafe(
        orderId: prepared.orderId,
        paymentKey: paymentKey,
        reservationId: reservationId,
      );
      final user = supabase.auth.currentUser;
      if (user != null) {
        await _reservationService.notifyReservationCreatedForReservation(
          reservationId: reservationId,
          userId: user.id,
        );
      }
    } else {
      await _reservationService.markPaymentOrderPaidSafe(
        orderId: prepared.orderId,
        paymentKey: paymentKey,
      );
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(zeroAmountBookingSnackMessage),
        duration: Duration(seconds: 4),
      ),
    );

    _reservationService.notifyReservationListRefresh();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainShell()),
      (route) => false,
    );
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => const MyReservationsScreen(forceRefreshOnOpen: true),
      ),
    );
  }

  /// 반납 검수 면책금 — 관리자가 고객 빌링키로 자동 결제 (Edge Function)
  Future<Map<String, dynamic>> payDeductibleWithBilling({
    required String reservationId,
  }) async {
    if (!isSupabaseInitialized) {
      throw StateError('Supabase가 초기화되지 않았습니다.');
    }
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw const AuthException('로그인이 필요합니다.');
    }

    try {
      return await _invokeFunction('billing-deductible-charge', {
        'reservationId': reservationId,
      });
    } on FunctionException catch (e) {
      throw Exception(_friendlyDeductibleBillingError(e));
    }
  }

  String _friendlyDeductibleBillingError(FunctionException error) {
    final details = error.details;
    if (details is Map) {
      final msg = details['error']?.toString();
      if (msg != null && msg.isNotEmpty) return msg;
      final code = details['code']?.toString();
      if (code == 'billing_key_missing') {
        return '고객에게 등록된 결제카드가 없습니다.';
      }
      if (code == 'billing_charge_failed') {
        return '결제에 실패했습니다. 1시간 간격으로 최대 3회 자동 재시도됩니다. 카드 한도·잔액을 확인해주세요.';
      }
    }
    if (details is String && details.isNotEmpty) {
      return _mapCancelError(details);
    }
    return error.reasonPhrase ?? '면책금 청구에 실패했습니다.';
  }

  /// 대여 연장 — 등록된 빌링키로 추가 요금 결제 후 연장 적용
  Future<Map<String, dynamic>> payRentalExtensionWithBilling({
    required String reservationId,
    int extensionHours = 1,
  }) async {
    if (!isSupabaseInitialized) {
      throw StateError('Supabase가 초기화되지 않았습니다.');
    }
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw const AuthException('로그인이 필요합니다.');
    }

    try {
      final data = await _invokeFunction('billing-extension-charge', {
        'reservationId': reservationId,
        'extensionHours': extensionHours,
      });
      return data;
    } on FunctionException catch (e) {
      throw Exception(_friendlyExtensionBillingError(e));
    }
  }

  String _friendlyExtensionBillingError(FunctionException error) {
    final details = error.details;
    if (details is Map) {
      final msg = details['error']?.toString();
      if (msg != null && msg.isNotEmpty) return msg;
      final code = details['code']?.toString();
      if (code == 'billing_key_missing') {
        return '등록된 결제카드가 없습니다. 마이페이지에서 결제카드를 등록해주세요.';
      }
      if (code == 'billing_charge_failed') {
        return '결제에 실패했습니다. 1시간 간격으로 최대 3회 자동 재시도됩니다. 카드 한도·잔액을 확인해주세요.';
      }
      if (code == 'extension_apply_failed') {
        return '결제는 완료되었으나 연장 적용에 실패했습니다. 고객센터로 문의해주세요.';
      }
    }
    if (details is String && details.isNotEmpty) {
      return _mapCancelError(details);
    }
    return error.reasonPhrase ?? '연장 결제에 실패했습니다.';
  }

  /// 온보딩 — 빌링키 발급 (Edge Function, 실결제 없음)
  Future<void> issueSignupBillingKey({
    required String authKey,
    required String customerKey,
  }) async {
    await _invokeFunction('billing-key-issue', {
      'authKey': authKey,
      'customerKey': customerKey,
    });
  }

  /// 결제카드 등록 — 토스 빌링키 발급 (온보딩·마이페이지 공통). 성공 시 true.
  /// `billing-key-issue` Edge Function → `user_profiles.toss_billing_key` 저장.
  Future<bool> registerSignupBillingKey(BuildContext context) async {
    if (!PaymentConfig.isConfigured) {
      throw StateError('TOSS_CLIENT_KEY가 필요합니다.');
    }

    final maintenance =
        await AppMaintenanceService.instance.current(force: true);
    if (maintenance.enabled) {
      throw Exception(maintenance.message);
    }

    final user = supabase.auth.currentUser;
    if (user == null) {
      throw const AuthException('로그인이 필요합니다.');
    }
    final customerKey = user.id;

    if (kIsWeb) {
      if (!_toss.isReady) {
        throw StateError(
          '토스페이먼츠 SDK가 로드되지 않았습니다. 페이지를 새로고침 후 다시 시도해주세요.',
        );
      }
      await _toss.requestBillingAuth(
        customerKey: customerKey,
        customerEmail: user.email,
        customerName: user.email?.split('@').first,
      );
      return false;
    }

    final params = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TossBillingWebViewScreen(
          customerKey: customerKey,
          customerEmail: user.email,
          customerName: user.email?.split('@').first,
        ),
      ),
    );

    if (!context.mounted) return false;
    if (params == null || params['_route'] == 'fail') {
      return false;
    }

    final authKey = params['authKey']?.trim();
    if (authKey == null || authKey.isEmpty) {
      throw StateError('카드 등록 승인 정보를 받지 못했습니다.');
    }

    final returnedCustomerKey =
        params['customerKey']?.trim() ?? customerKey;

    await issueSignupBillingKey(
      authKey: authKey,
      customerKey: returnedCustomerKey,
    );
    return true;
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
      totalPrice: (paymentOrder?['total_price'] as num?)?.toInt(),
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
        amount: amount,
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
          amount: amount,
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
        amount: amount,
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
        amount: amount,
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
          amount: amount,
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
        amount: amount,
      );
    }

    if (lastError != null) {
      throw Exception(_friendlyError(lastError));
    }
    throw Exception(
      '결제는 완료되었으나 예약 저장에 실패했습니다.\n'
      'Supabase SQL Editor에서 fix_reservation_insert.sql 과 '
      'finalize_reservation_after_payment.sql 을 실행한 뒤 '
      '「예약 저장 재시도」를 눌러주세요.',
    );
  }

  Future<PaymentConfirmResult> _finalizePaymentResult(
    PaymentConfirmResult result, {
    required String paymentKey,
    required String orderId,
    required int amount,
  }) async {
    if (result.reservationId.isEmpty) {
      return result;
    }

    await _reservationService.linkPaymentOrderReservation(
      orderId: orderId,
      reservationId: result.reservationId,
    );
    await _reservationService.ensureReservationConfirmed(
      reservationId: result.reservationId,
      paymentKey: paymentKey,
      orderId: orderId,
    );
    await _reservationService.waitUntilReservationReady(result.reservationId);

    await _reservationService.tryApplyBookingDiscounts(
      orderId: orderId,
      reservationId: result.reservationId,
    );

    if (!result.alreadyPaid) {
      final user = supabase.auth.currentUser;
      if (user != null) {
        await _reservationService.notifyReservationCreatedForReservation(
          reservationId: result.reservationId,
          userId: user.id,
        );
      }
    }

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
      totalPrice: (body['totalPrice'] as num?)?.toInt() ??
          (body['total_price'] as num?)?.toInt(),
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
      if (isReservationAlreadyGoneError(e)) {
        return {
          'reservationId': reservationId,
          'alreadyCancelled': true,
        };
      }
      throw Exception(_friendlyError(e));
    } catch (e) {
      if (isReservationAlreadyGoneError(e)) {
        return {
          'reservationId': reservationId,
          'alreadyCancelled': true,
        };
      }
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
  if (isReservationAlreadyGoneError(message)) {
    return ReservationCancelMessages.alreadyCancelled;
  }
  final lower = message.toLowerCase();
  if (lower.contains(maintenanceActiveCode)) {
    return AppMaintenanceService.instance.cached.message;
  }
  if (lower.contains('refund_amount_mismatch')) {
    return '환불 금액이 변경되었습니다. 다시 시도해주세요.';
  }
  if (lower.contains('invalid input syntax for type uuid')) {
    return '예약 취소 처리 중 ID 형식 오류가 발생했습니다. 잠시 후 다시 시도해주세요.';
  }
  return message;
}

String _friendlyCancelError(PostgrestException error) {
  final msg = error.message.toLowerCase();
  if (msg.contains('refund_amount_mismatch')) {
    return '환불 금액이 변경되었습니다. 다시 시도해주세요.';
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
  if (isRetryableNetworkError(error)) {
    return friendlyNetworkError(error);
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
