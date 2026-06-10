import 'package:flutter/material.dart';

import 'vehicle_exposure_status.dart';

/// scheduled-vehicle-insurance cron·DB 예약 차단과 동일한 KST 날짜 기준
enum VehicleInsuranceBadgeKind {
  none,
  /// 만료 8~30일 전
  expiringWarning,
  /// 만료 7일 이내(만료 전)
  expiringUrgent,
  /// 만료됨(만료일 당일 포함)
  expired,
}

/// 홈 차량관리 메뉴 뱃지 — 단지 내 최악 단계
enum VehicleInsuranceMenuBadgeLevel {
  none,
  warning,
  urgent,
  expired,
}

abstract final class VehicleInsuranceStatus {
  static const expiringWarningColor = Color(0xFFFF9800);
  static const expiringUrgentColor = Color(0xFFD32F2F);
  static const expiredColor = Color(0xFF757575);

  static DateTime kstToday() {
    final kst = DateTime.now().toUtc().add(const Duration(hours: 9));
    return DateTime(kst.year, kst.month, kst.day);
  }

  static DateTime dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  /// KST 기준 만료까지 남은 일수 (만료 당일 = 0, 이미 지남 = 음수)
  static int daysUntilExpiry(DateTime? expiresAt) {
    if (expiresAt == null) return 9999;
    final expiry = dateOnly(expiresAt);
    final today = kstToday();
    return expiry.difference(today).inDays;
  }

  static bool isExpired(DateTime? expiresAt) => daysUntilExpiry(expiresAt) < 0;

  static bool isResidentBookable({
    required bool isPublished,
    required bool isUnderMaintenance,
    DateTime? insuranceExpiresAt,
  }) {
    return VehicleExposureStatusUtil.isResidentBookable(
      isPublished: isPublished,
      isUnderMaintenance: isUnderMaintenance,
      insuranceExpiresAt: insuranceExpiresAt,
    );
  }

  /// 1) 8~30일 전: warning / 2) 7일 이내: urgent / 3) 만료: expired
  static VehicleInsuranceBadgeKind badgeKind(DateTime? expiresAt) {
    if (expiresAt == null) return VehicleInsuranceBadgeKind.none;

    final daysLeft = daysUntilExpiry(expiresAt);
    if (daysLeft < 0) return VehicleInsuranceBadgeKind.expired;
    if (daysLeft <= 7) return VehicleInsuranceBadgeKind.expiringUrgent;
    if (daysLeft <= 30) return VehicleInsuranceBadgeKind.expiringWarning;
    return VehicleInsuranceBadgeKind.none;
  }

  static VehicleInsuranceMenuBadgeLevel menuBadgeLevel(
    Iterable<DateTime?> expiryDates,
  ) {
    var level = VehicleInsuranceMenuBadgeLevel.none;
    for (final expiresAt in expiryDates) {
      switch (badgeKind(expiresAt)) {
        case VehicleInsuranceBadgeKind.expired:
          return VehicleInsuranceMenuBadgeLevel.expired;
        case VehicleInsuranceBadgeKind.expiringUrgent:
          level = VehicleInsuranceMenuBadgeLevel.urgent;
          break;
        case VehicleInsuranceBadgeKind.expiringWarning:
          if (level == VehicleInsuranceMenuBadgeLevel.none) {
            level = VehicleInsuranceMenuBadgeLevel.warning;
          }
          break;
        case VehicleInsuranceBadgeKind.none:
          break;
      }
    }
    return level;
  }

  static String menuBadgeLabel(VehicleInsuranceMenuBadgeLevel level) {
    switch (level) {
      case VehicleInsuranceMenuBadgeLevel.none:
        return '';
      case VehicleInsuranceMenuBadgeLevel.warning:
      case VehicleInsuranceMenuBadgeLevel.urgent:
        return '보험확인';
      case VehicleInsuranceMenuBadgeLevel.expired:
        return '보험만료';
    }
  }

  static Color menuBadgeColor(VehicleInsuranceMenuBadgeLevel level) {
    switch (level) {
      case VehicleInsuranceMenuBadgeLevel.none:
        return Colors.transparent;
      case VehicleInsuranceMenuBadgeLevel.warning:
        return expiringWarningColor;
      case VehicleInsuranceMenuBadgeLevel.urgent:
        return expiringUrgentColor;
      case VehicleInsuranceMenuBadgeLevel.expired:
        return expiredColor;
    }
  }

  static Color badgeColor(VehicleInsuranceBadgeKind kind) {
    switch (kind) {
      case VehicleInsuranceBadgeKind.none:
        return Colors.transparent;
      case VehicleInsuranceBadgeKind.expiringWarning:
        return expiringWarningColor;
      case VehicleInsuranceBadgeKind.expiringUrgent:
        return expiringUrgentColor;
      case VehicleInsuranceBadgeKind.expired:
        return expiredColor;
    }
  }

  static String badgeLabel(VehicleInsuranceBadgeKind kind) {
    switch (kind) {
      case VehicleInsuranceBadgeKind.none:
        return '';
      case VehicleInsuranceBadgeKind.expiringWarning:
      case VehicleInsuranceBadgeKind.expiringUrgent:
        return '보험확인';
      case VehicleInsuranceBadgeKind.expired:
        return '보험만료';
    }
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

    final color = VehicleInsuranceStatus.badgeColor(kind);
    final label = VehicleInsuranceStatus.badgeLabel(kind);

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
