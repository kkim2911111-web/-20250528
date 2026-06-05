import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../screens/reservation_detail_screen.dart';

/// FCM 알림 탭 시 화면 이동
class FcmNavigationService {
  FcmNavigationService._();

  static GlobalKey<NavigatorState>? _navigatorKey;
  static String? _pendingReservationId;

  static void bindNavigator(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
    _flushPending();
  }

  static void handleRemoteMessage(RemoteMessage message) {
    handleData(message.data);
  }

  static void handleData(Map<String, dynamic> data) {
    final type = data['type']?.toString() ?? '';
    final reservationId = data['reservation_id']?.toString();

    if (reservationId != null && reservationId.isNotEmpty) {
      if (type.contains('reservation') ||
          type.startsWith('customer_') ||
          type == 'reservation') {
        openReservationDetail(reservationId);
        return;
      }
    }

    // 예약 상세 없는 시나리오 — 홈 유지 (추후 딥링크 확장)
    if (type == 'booking' || type == 'home' || type == 'license') {
      return;
    }
  }

  static void openReservationDetail(String reservationId) {
    final nav = _navigatorKey?.currentState;
    if (nav == null || !nav.mounted) {
      _pendingReservationId = reservationId;
      return;
    }

    _pendingReservationId = null;
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => ReservationDetailScreen(reservationId: reservationId),
      ),
    );
  }

  static void _flushPending() {
    final id = _pendingReservationId;
    if (id == null) return;
    openReservationDetail(id);
  }
}
