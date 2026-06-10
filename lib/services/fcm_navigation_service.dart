import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../models/inbox_notification.dart';
import '../repositories/staff_repository.dart';
import '../screens/admin/admin_management_screens.dart';
import '../screens/admin/admin_reservation_list_screen.dart';
import '../screens/notification_list_screen.dart';
import '../screens/reservation_detail_screen.dart';
import '../screens/super_admin/super_admin_reservations_screen.dart';
import '../screens/super_admin/super_admin_revenue_screen.dart';
import '../services/admin_notification_navigation.dart';
import '../services/super_admin_service.dart';
import '../supabase_client.dart';

/// FCM 알림 탭 시 screen·reservationId 기반 딥링크
class FcmNavigationService {
  FcmNavigationService._();

  static GlobalKey<NavigatorState>? _navigatorKey;
  static Map<String, dynamic>? _pendingData;

  static void bindNavigator(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
    _flushPending();
  }

  static void handleRemoteMessage(RemoteMessage message) {
    handleData(message.data);
  }

  static void handleData(Map<String, dynamic> data) {
    final nav = _navigatorKey?.currentState;
    if (nav == null || !nav.mounted) {
      _pendingData = Map<String, dynamic>.from(data);
      return;
    }
    _pendingData = null;
    _navigate(nav, data);
  }

  static void _flushPending() {
    final data = _pendingData;
    if (data == null) return;
    _pendingData = null;
    final nav = _navigatorKey?.currentState;
    if (nav == null || !nav.mounted) {
      _pendingData = data;
      return;
    }
    _navigate(nav, data);
  }

  static Future<void> _navigate(
    NavigatorState nav,
    Map<String, dynamic> data,
  ) async {
    final screen = _resolveScreen(data);
    final reservationId = _resolveReservationId(data);
    final type = data['type']?.toString() ?? '';

    final user = supabase.auth.currentUser;
    if (user == null) return;

    final superAdminService = SuperAdminService();
    final isSuperAdmin = await superAdminService.isSuperAdmin();
    final staffProfile = isSuperAdmin
        ? null
        : await StaffRepository().fetchMyProfile();

    if (!nav.mounted) return;

    switch (screen) {
      case 'reservation':
      case 'reservation_detail':
        if (isSuperAdmin) {
          nav.push(
            MaterialPageRoute<void>(
              builder: (_) => SuperAdminReservationsScreen(
                service: superAdminService,
              ),
            ),
          );
          return;
        }
        if (staffProfile != null && staffProfile.approved) {
          nav.push(
            MaterialPageRoute<void>(
              builder: (_) => const AdminReservationListScreen(),
            ),
          );
          return;
        }
        if (reservationId != null && reservationId.isNotEmpty) {
          openReservationDetail(reservationId);
        }
        return;

      case 'no_show':
        if (isSuperAdmin) {
          nav.push(
            MaterialPageRoute<void>(
              builder: (_) => SuperAdminReservationsScreen(
                service: superAdminService,
              ),
            ),
          );
          return;
        }
        if (staffProfile != null && staffProfile.approved) {
          nav.push(
            MaterialPageRoute<void>(
              builder: (_) => const AdminReservationListScreen(),
            ),
          );
        }
        return;

      case 'payment':
      case 'sales':
      case 'revenue':
        if (isSuperAdmin) {
          nav.push(
            MaterialPageRoute<void>(
              builder: (_) => SuperAdminRevenueScreen(
                service: superAdminService,
              ),
            ),
          );
          return;
        }
        if (staffProfile != null && staffProfile.approved) {
          nav.push(
            MaterialPageRoute<void>(
              builder: (_) => AdminSalesScreen(profile: staffProfile),
            ),
          );
        }
        return;

      case 'notice':
      case 'notification':
      case 'notifications':
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) => NotificationListScreen(
              onlyOwnRows: staffProfile == null && !isSuperAdmin,
              onNotificationTap: (ctx, item) async {
                if (isSuperAdmin) {
                  AdminNotificationNavigation.openFromInbox(
                    ctx,
                    item: item,
                    isSuperAdmin: true,
                    superAdminService: superAdminService,
                  );
                  return;
                }
                if (staffProfile != null) {
                  AdminNotificationNavigation.openFromInbox(
                    ctx,
                    item: item,
                    staffProfile: staffProfile,
                  );
                }
              },
            ),
          ),
        );
        return;

      default:
        if (type.startsWith('admin_') || type.startsWith('staff_')) {
          if (isSuperAdmin) {
            AdminNotificationNavigation.openFromInbox(
              nav.context,
              item: _inboxFromData(data),
              isSuperAdmin: true,
              superAdminService: superAdminService,
            );
          } else if (staffProfile != null) {
            AdminNotificationNavigation.openFromInbox(
              nav.context,
              item: _inboxFromData(data),
              staffProfile: staffProfile,
            );
          }
          return;
        }
        if (reservationId != null && reservationId.isNotEmpty) {
          openReservationDetail(reservationId);
        }
    }
  }

  static String _resolveScreen(Map<String, dynamic> data) {
    final screen = data['screen']?.toString().trim().toLowerCase();
    if (screen != null && screen.isNotEmpty) return screen;

    final type = data['type']?.toString() ?? '';
    if (type.contains('no_show') || type == 'staff_no_show_auto_completed') {
      return 'no_show';
    }
    if (type.contains('billing') ||
        type.contains('payment') ||
        type == 'admin_settlement_request') {
      return 'payment';
    }
    if (type.contains('reservation') ||
        type.contains('rental') ||
        type.contains('return') ||
        type.startsWith('customer_')) {
      return 'reservation';
    }
    if (type.contains('license') ||
        type.contains('resident') ||
        type.contains('signup') ||
        type == 'admin') {
      return 'notice';
    }
    return 'notice';
  }

  static String? _resolveReservationId(Map<String, dynamic> data) {
    final id = data['reservationId']?.toString() ??
        data['reservation_id']?.toString();
    if (id == null || id.isEmpty) return null;
    return id;
  }

  static InboxNotification _inboxFromData(Map<String, dynamic> data) {
    return InboxNotification(
      id: '',
      title: data['title']?.toString() ?? '',
      body: data['body']?.toString() ?? '',
      type: data['type']?.toString() ?? '',
      reservationId: _resolveReservationId(data),
    );
  }

  static void openReservationDetail(String reservationId) {
    final nav = _navigatorKey?.currentState;
    if (nav == null || !nav.mounted) {
      _pendingData = {
        'screen': 'reservation_detail',
        'reservationId': reservationId,
      };
      return;
    }

    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => ReservationDetailScreen(reservationId: reservationId),
      ),
    );
  }
}
