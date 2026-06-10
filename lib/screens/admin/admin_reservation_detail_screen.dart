import 'package:flutter/material.dart';

import '../../models/admin_timeline.dart';
import '../../models/rental_detail.dart';
import '../shared/rental_detail_screen.dart' show RentalDetailScreen;

export '../shared/rental_detail_screen.dart' show RentalDetailScreen;

/// 관리자 — 타임라인·목록 공통 예약 상세 (→ 공용 [RentalDetailScreen])
@Deprecated('Use RentalDetailScreen or openStaffRentalDetail')
class AdminReservationDetailScreen extends StatelessWidget {
  final AdminTimelineReservation reservation;

  const AdminReservationDetailScreen({
    super.key,
    required this.reservation,
  });

  @override
  Widget build(BuildContext context) {
    return RentalDetailScreen(
      reservationId: reservation.id,
      scope: RentalDetailScope.staff,
    );
  }
}
