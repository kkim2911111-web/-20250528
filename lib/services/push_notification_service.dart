import 'package:flutter/foundation.dart';

import '../supabase_client.dart';

/// FCM 시나리오 발송 — dispatch-push-scenario Edge Function
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  /// 실패해도 본 흐름은 유지 (non-fatal)
  Future<void> dispatch(
    String scenario, {
    Map<String, String>? payload,
  }) async {
    if (!isSupabaseInitialized) return;

    try {
      final response = await supabase.functions.invoke(
        'dispatch-push-scenario',
        body: {
          'scenario': scenario,
          if (payload != null) ...payload,
        },
      );

      if (response.status != 200) {
        debugPrint(
          '[push] $scenario HTTP ${response.status}: ${response.data}',
        );
        return;
      }

      final data = response.data;
      if (data is Map) {
        if (data['ok'] != true) {
          debugPrint('[push] $scenario rejected: $data');
          return;
        }
        final skipped = data['skipped'] == true;
        final customerSent = (data['customerSent'] as num?)?.toInt() ?? 0;
        final staffSent = (data['staffSent'] as num?)?.toInt() ?? 0;
        final sent = customerSent + staffSent;
        if (skipped) {
          debugPrint(
            '[push] $scenario skipped — FIREBASE_SERVICE_ACCOUNT_JSON 확인 필요',
          );
        } else if (sent == 0) {
          debugPrint(
            '[push] $scenario sent=0 — fcm_tokens에 기기 토큰이 없거나 FCM 발송 실패',
          );
        } else {
          debugPrint('[push] $scenario ok (sent=$sent)');
        }
      }
    } catch (e, st) {
      debugPrint('[push] $scenario failed (non-fatal): $e\n$st');
    }
  }

  // ── 고객 ──────────────────────────────────────────────

  Future<void> customerSignupComplete() =>
      dispatch('customer_signup_complete');

  Future<void> customerLicenseApproved(String userId) => dispatch(
        'customer_license_approved',
        payload: {'userId': userId},
      );

  Future<void> customerLicenseRejected(
    String userId, {
    required String reason,
  }) =>
      dispatch(
        'customer_license_rejected',
        payload: {'userId': userId, 'reason': reason},
      );

  Future<void> customerResidentApproved(String userId) => dispatch(
        'customer_resident_approved',
        payload: {'userId': userId},
      );

  Future<void> customerResidentRejected(
    String userId, {
    required String reason,
  }) =>
      dispatch(
        'customer_resident_rejected',
        payload: {'userId': userId, 'reason': reason},
      );

  Future<void> customerReservationConfirmed({
    required String userId,
    required String reservationId,
    required String vehicleName,
    String? startAt,
  }) =>
      dispatch(
        'customer_reservation_confirmed',
        payload: {
          'userId': userId,
          'reservationId': reservationId,
          'vehicleName': vehicleName,
          if (startAt != null) 'startAt': startAt,
        },
      );

  Future<void> customerReservationCancelled({
    required String userId,
    required String reservationId,
    required String vehicleName,
  }) =>
      dispatch(
        'customer_reservation_cancelled',
        payload: {
          'userId': userId,
          'reservationId': reservationId,
          'vehicleName': vehicleName,
        },
      );

  Future<void> customerRentalStarted({
    required String userId,
    required String reservationId,
    String? endAt,
  }) =>
      dispatch(
        'customer_rental_started',
        payload: {
          'userId': userId,
          'reservationId': reservationId,
          if (endAt != null) 'endAt': endAt,
        },
      );

  Future<void> customerPaymentCompleted({
    required String userId,
    required String reservationId,
    required String vehicleName,
    String? pointsEarned,
  }) =>
      dispatch(
        'customer_payment_completed',
        payload: {
          'userId': userId,
          'reservationId': reservationId,
          'vehicleName': vehicleName,
          if (pointsEarned != null) 'pointsEarned': pointsEarned,
        },
      );

  Future<void> customerReturnInspectionComplete({
    required String userId,
    required String reservationId,
  }) =>
      dispatch(
        'customer_return_inspection_complete',
        payload: {
          'userId': userId,
          'reservationId': reservationId,
        },
      );

  // ── 관리자(단지 staff) ───────────────────────────────

  Future<void> staffNewSignup({required String complexId}) => dispatch(
        'staff_new_signup',
        payload: {'complexId': complexId},
      );

  Future<void> staffLicenseReviewRequest({required String complexId}) =>
      dispatch(
        'staff_license_review_request',
        payload: {'complexId': complexId},
      );

  Future<void> staffResidentReviewRequest({required String complexId}) =>
      dispatch(
        'staff_resident_review_request',
        payload: {'complexId': complexId},
      );

  Future<void> staffNewReservation({
    required String complexId,
    required String reservationId,
    required String vehicleName,
    String? startAt,
    String? userId,
  }) =>
      dispatch(
        'staff_new_reservation',
        payload: {
          'complexId': complexId,
          'reservationId': reservationId,
          'vehicleName': vehicleName,
          if (startAt != null) 'startAt': startAt,
          if (userId != null) 'userId': userId,
        },
      );

  Future<void> staffReservationCancelled({
    required String complexId,
    required String reservationId,
    required String vehicleName,
  }) =>
      dispatch(
        'staff_reservation_cancelled',
        payload: {
          'complexId': complexId,
          'reservationId': reservationId,
          'vehicleName': vehicleName,
        },
      );

  Future<void> staffRentalStarted({
    required String complexId,
    required String reservationId,
    required String vehicleName,
    String? renterName,
  }) =>
      dispatch(
        'staff_rental_started',
        payload: {
          'complexId': complexId,
          'reservationId': reservationId,
          'vehicleName': vehicleName,
          if (renterName != null) 'renterName': renterName,
        },
      );

  Future<void> staffReturnCompleted({
    required String complexId,
    required String reservationId,
    required String vehicleName,
  }) =>
      dispatch(
        'staff_return_completed',
        payload: {
          'complexId': complexId,
          'reservationId': reservationId,
          'vehicleName': vehicleName,
        },
      );
}
