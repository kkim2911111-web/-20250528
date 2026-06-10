import 'package:flutter/material.dart';

import '../models/rental_detail.dart';
import '../screens/shared/rental_detail_screen.dart';
import '../services/admin_service.dart';
import '../services/super_admin_service.dart';

Future<bool?> openStaffRentalDetail(
  BuildContext context, {
  required String reservationId,
  AdminService? adminService,
  RentalDetailPrefetch? prefetch,
}) {
  return Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => RentalDetailScreen(
        reservationId: reservationId,
        scope: RentalDetailScope.staff,
        adminService: adminService ?? AdminService(),
        prefetch: prefetch,
      ),
    ),
  );
}

Future<bool?> openSuperAdminRentalDetail(
  BuildContext context, {
  required String reservationId,
  required SuperAdminService service,
  RentalDetailPrefetch? prefetch,
}) {
  return Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => RentalDetailScreen(
        reservationId: reservationId,
        scope: RentalDetailScope.superAdmin,
        superAdminService: service,
        prefetch: prefetch,
      ),
    ),
  );
}
