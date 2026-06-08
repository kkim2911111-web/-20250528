import 'package:flutter/material.dart';

/// scheduled-vehicle-insurance cron·DB 예약 차단과 동일한 KST 날짜 기준
enum VehicleInsuranceBadgeKind { none, expiringSoon, expired }

abstract final class VehicleInsuranceStatus {
  static const expiringSoonColor = Color(0xFFFF9800);
  static const expiredColor = Color(0xFFFB8C00);

  static DateTime kstToday() {
    final kst = DateTime.now().toUtc().add(const Duration(hours: 9));
    return DateTime(kst.year, kst.month, kst.day);
  }

  static DateTime dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  /// 만료: expiry <= today (cron `expires <= today`)
  /// 임박: expiry > today && expiry <= today + 30일
  static VehicleInsuranceBadgeKind badgeKind(DateTime? expiresAt) {
    if (expiresAt == null) return VehicleInsuranceBadgeKind.none;

    final expiry = dateOnly(expiresAt);
    final today = kstToday();

    if (!expiry.isAfter(today)) {
      return VehicleInsuranceBadgeKind.expired;
    }

    final limit = today.add(const Duration(days: 30));
    if (!expiry.isAfter(limit)) {
      return VehicleInsuranceBadgeKind.expiringSoon;
    }

    return VehicleInsuranceBadgeKind.none;
  }
}

class VehicleInsuranceBadge extends StatelessWidget {
  final DateTime? insuranceExpiresAt;

  const VehicleInsuranceBadge({
    super.key,
    required this.insuranceExpiresAt,
  });

  @override
  Widget build(BuildContext context) {
    final kind = VehicleInsuranceStatus.badgeKind(insuranceExpiresAt);
    if (kind == VehicleInsuranceBadgeKind.none) {
      return const SizedBox.shrink();
    }

    final isExpired = kind == VehicleInsuranceBadgeKind.expired;
    final label = isExpired ? '보험만료' : '보험확인';
    final color = isExpired
        ? VehicleInsuranceStatus.expiredColor
        : VehicleInsuranceStatus.expiringSoonColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
