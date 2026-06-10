import 'package:flutter/material.dart';

import 'vehicle_insurance_status.dart';

/// 관리자·입주민 공통 차량 노출 상태 (우선순위: 보험만료 > 점검중 > 대기 > 노출중)
enum VehicleExposureStatus {
  published,
  waiting,
  maintenance,
  insuranceExpired,
}

abstract final class VehicleExposureStatusUtil {
  static const publishedColor = Color(0xFF22C55E);
  static const waitingColor = Color(0xFF9CA3AF);
  static const maintenanceColor = Color(0xFFF97316);
  static const insuranceExpiredColor = Color(0xFFD32F2F);

  static VehicleExposureStatus resolve({
    required bool isPublished,
    required bool isUnderMaintenance,
    DateTime? insuranceExpiresAt,
  }) {
    if (VehicleInsuranceStatus.isExpired(insuranceExpiresAt)) {
      return VehicleExposureStatus.insuranceExpired;
    }
    if (isUnderMaintenance) return VehicleExposureStatus.maintenance;
    if (!isPublished) return VehicleExposureStatus.waiting;
    return VehicleExposureStatus.published;
  }

  static String label(VehicleExposureStatus status) {
    switch (status) {
      case VehicleExposureStatus.published:
        return '노출중';
      case VehicleExposureStatus.waiting:
        return '대기';
      case VehicleExposureStatus.maintenance:
        return '점검중';
      case VehicleExposureStatus.insuranceExpired:
        return '보험만료';
    }
  }

  static Color color(VehicleExposureStatus status) {
    switch (status) {
      case VehicleExposureStatus.published:
        return publishedColor;
      case VehicleExposureStatus.waiting:
        return waitingColor;
      case VehicleExposureStatus.maintenance:
        return maintenanceColor;
      case VehicleExposureStatus.insuranceExpired:
        return insuranceExpiredColor;
    }
  }

  static bool isResidentBookable({
    required bool isPublished,
    required bool isUnderMaintenance,
    DateTime? insuranceExpiresAt,
  }) {
    return resolve(
          isPublished: isPublished,
          isUnderMaintenance: isUnderMaintenance,
          insuranceExpiresAt: insuranceExpiresAt,
        ) ==
        VehicleExposureStatus.published;
  }
}

class VehicleExposureBadge extends StatelessWidget {
  final bool isPublished;
  final bool isUnderMaintenance;
  final DateTime? insuranceExpiresAt;

  const VehicleExposureBadge({
    super.key,
    required this.isPublished,
    required this.isUnderMaintenance,
    this.insuranceExpiresAt,
  });

  @override
  Widget build(BuildContext context) {
    final status = VehicleExposureStatusUtil.resolve(
      isPublished: isPublished,
      isUnderMaintenance: isUnderMaintenance,
      insuranceExpiresAt: insuranceExpiresAt,
    );
    final color = VehicleExposureStatusUtil.color(status);
    final label = VehicleExposureStatusUtil.label(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
