import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
      await supabase.functions.invoke(
        'dispatch-push-scenario',
        body: {
          'scenario': scenario,
          if (payload != null) ...payload,
        },
      );
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
