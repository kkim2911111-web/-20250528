import 'super_admin_settlement_dashboard.dart' show superAdminSettlementDashboardPeriod;

/// 플랫폼 수수료 — 대당 월 10만원 (일할 없음)
const platformFeePerVehicle = 100000;

int platformFeeAmount(int vehicleCount) =>
    vehicleCount * platformFeePerVehicle;

/// 해당 월에 수수료 과금 대상인지 (등록·해지 규칙 — 서버 platform_fee_vehicle_count_for_month 동일)
bool isVehicleBillableForMonth({
  required DateTime registeredAt,
  DateTime? deactivatedAt,
  required int year,
  required int month,
  DateTime? asOf,
}) {
  final bounds = _monthBoundsKst(year, month);
  final now = asOf ?? DateTime.now();

  if (bounds.start.isAfter(now)) {
    return deactivatedAt == null;
  }

  if (!registeredAt.isBefore(bounds.end)) {
    return false;
  }

  if (deactivatedAt != null && deactivatedAt.isBefore(bounds.start)) {
    return false;
  }

  return true;
}

int countBillableVehiclesForMonth(
  Iterable<({DateTime registeredAt, DateTime? deactivatedAt})> vehicles, {
  required int year,
  required int month,
  DateTime? asOf,
}) {
  return vehicles
      .where(
        (v) => isVehicleBillableForMonth(
          registeredAt: v.registeredAt,
          deactivatedAt: v.deactivatedAt,
          year: year,
          month: month,
          asOf: asOf,
        ),
      )
      .length;
}

bool isPlatformFeeEstimateMonth({
  required int year,
  required int month,
  DateTime? asOf,
}) {
  final bounds = _monthBoundsKst(year, month);
  return bounds.start.isAfter(asOf ?? DateTime.now());
}

({DateTime start, DateTime end}) _monthBoundsKst(int year, int month) {
  final start = DateTime(year, month, 1);
  final end = month == 12
      ? DateTime(year + 1, 1, 1)
      : DateTime(year, month + 1, 1);
  return (start: start, end: end);
}

/// 대시보드 정산 카드 기준월과 동일한 KST 월 경계 (테스트·표시용)
({int year, int month}) platformFeeDefaultPeriod([DateTime? now]) =>
    superAdminSettlementDashboardPeriod(now);
