import 'package:flutter/material.dart';

import '../models/inbox_notification.dart';
import '../models/staff_profile.dart';
import '../screens/admin/admin_customer_hub_screen.dart';
import '../screens/admin/admin_management_screens.dart';
import '../screens/admin/admin_reservation_list_screen.dart';
import '../screens/super_admin/super_admin_entity_screens.dart';
import '../screens/super_admin/super_admin_reservations_screen.dart';
import '../screens/super_admin/super_admin_revenue_screen.dart';
import '../services/super_admin_service.dart';
import '../utils/super_admin_settlement_dashboard.dart';

/// 관리자 알림함 탭 시 화면 이동
class AdminNotificationNavigation {
  AdminNotificationNavigation._();

  static void openFromInbox(
    BuildContext context, {
    required InboxNotification item,
    StaffProfile? staffProfile,
    bool isSuperAdmin = false,
    SuperAdminService? superAdminService,
  }) {
    final type = item.type;
    final openConflict = type == 'admin_reservation' &&
        item.body.contains('충돌');

    if (isSuperAdmin && superAdminService != null) {
      _openSuperAdmin(
        context,
        type: type,
        service: superAdminService,
        openConflict: openConflict,
      );
      return;
    }

    if (staffProfile != null) {
      _openStaff(
        context,
        type: type,
        profile: staffProfile,
        openConflict: openConflict,
      );
    }
  }

  static void _openStaff(
    BuildContext context, {
    required String type,
    required StaffProfile profile,
    required bool openConflict,
  }) {
    switch (type) {
      case 'admin_license':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AdminCustomerHubScreen(
              profile: profile,
              initialTab: AdminCustomerHubTab.license,
            ),
          ),
        );
        return;
      case 'admin_resident':
      case 'admin':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AdminCustomerHubScreen(profile: profile),
          ),
        );
        return;
      case 'admin_vehicle':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AdminVehicleManageScreen(profile: profile),
          ),
        );
        return;
      case 'admin_billing':
      case 'admin_reservation':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AdminReservationListScreen(
              openConflictTab: openConflict,
            ),
          ),
        );
        return;
      default:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const AdminReservationListScreen(),
          ),
        );
    }
  }

  static void _openSuperAdmin(
    BuildContext context, {
    required String type,
    required SuperAdminService service,
    required bool openConflict,
  }) {
    switch (type) {
      case 'admin_vehicle':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SuperAdminVehiclesScreen(service: service),
          ),
        );
        return;
      case 'admin_license':
      case 'admin_resident':
      case 'admin':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SuperAdminResidentsScreen(service: service),
          ),
        );
        return;
      case 'admin_billing':
      case 'admin_reservation':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SuperAdminReservationsScreen(service: service),
          ),
        );
        return;
      case 'admin_settlement_request':
        final period = superAdminSettlementDashboardPeriod();
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SuperAdminRevenueScreen(
              service: service,
              initialYear: period.year,
              initialMonth: period.month,
            ),
          ),
        );
        return;
      default:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SuperAdminReservationsScreen(service: service),
          ),
        );
    }
  }
}
