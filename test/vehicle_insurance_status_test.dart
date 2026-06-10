import 'package:danjicar_app/utils/vehicle_exposure_status.dart';
import 'package:danjicar_app/utils/vehicle_insurance_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime today;

  setUp(() {
    today = VehicleInsuranceStatus.kstToday();
  });

  group('VehicleInsuranceStatus.badgeKind — 3단계', () {
    test('D-25: 주황 보험확인', () {
      final expires = today.add(const Duration(days: 25));
      final kind = VehicleInsuranceStatus.badgeKind(expires);

      expect(kind, VehicleInsuranceBadgeKind.expiringWarning);
      expect(VehicleInsuranceStatus.badgeLabel(kind), '보험확인');
      expect(
        VehicleInsuranceStatus.badgeColor(kind),
        VehicleInsuranceStatus.expiringWarningColor,
      );
      expect(
        VehicleInsuranceStatus.badgeColor(kind),
        const Color(0xFFFF9800),
      );
    });

    test('D-5: 빨강 보험확인', () {
      final expires = today.add(const Duration(days: 5));
      final kind = VehicleInsuranceStatus.badgeKind(expires);

      expect(kind, VehicleInsuranceBadgeKind.expiringUrgent);
      expect(VehicleInsuranceStatus.badgeLabel(kind), '보험확인');
      expect(
        VehicleInsuranceStatus.badgeColor(kind),
        VehicleInsuranceStatus.expiringUrgentColor,
      );
      expect(
        VehicleInsuranceStatus.badgeColor(kind),
        const Color(0xFFD32F2F),
      );
    });

    test('D+1(만료): 보험만료', () {
      final expires = today.subtract(const Duration(days: 1));
      final kind = VehicleInsuranceStatus.badgeKind(expires);

      expect(kind, VehicleInsuranceBadgeKind.expired);
      expect(VehicleInsuranceStatus.badgeLabel(kind), '보험만료');
      expect(VehicleInsuranceStatus.isExpired(expires), isTrue);
    });

    test('D-8 경계: warning / D-7 경계: urgent', () {
      expect(
        VehicleInsuranceStatus.badgeKind(today.add(const Duration(days: 8))),
        VehicleInsuranceBadgeKind.expiringWarning,
      );
      expect(
        VehicleInsuranceStatus.badgeKind(today.add(const Duration(days: 7))),
        VehicleInsuranceBadgeKind.expiringUrgent,
      );
      expect(
        VehicleInsuranceStatus.badgeKind(today),
        VehicleInsuranceBadgeKind.expiringUrgent,
      );
    });
  });

  group('menuBadgeLevel — 가장 심각한 단계', () {
    test('만료가 있으면 expired 우선', () {
      final level = VehicleInsuranceStatus.menuBadgeLevel([
        today.add(const Duration(days: 20)),
        today.subtract(const Duration(days: 1)),
        today.add(const Duration(days: 3)),
      ]);
      expect(level, VehicleInsuranceMenuBadgeLevel.expired);
      expect(VehicleInsuranceStatus.menuBadgeLabel(level), '보험만료');
    });

    test('urgent가 warning보다 우선', () {
      final level = VehicleInsuranceStatus.menuBadgeLevel([
        today.add(const Duration(days: 20)),
        today.add(const Duration(days: 3)),
      ]);
      expect(level, VehicleInsuranceMenuBadgeLevel.urgent);
      expect(VehicleInsuranceStatus.menuBadgeLabel(level), '보험확인');
      expect(
        VehicleInsuranceStatus.menuBadgeColor(level),
        VehicleInsuranceStatus.expiringUrgentColor,
      );
    });
  });

  group('입주민 예약 노출 — is_published + 보험', () {
    test('만료 차량은 예약 불가', () {
      expect(
        VehicleInsuranceStatus.isResidentBookable(
          isPublished: true,
          isUnderMaintenance: false,
          insuranceExpiresAt: today.subtract(const Duration(days: 1)),
        ),
        isFalse,
      );
      expect(
        VehicleExposureStatusUtil.isResidentBookable(
          isPublished: true,
          isUnderMaintenance: false,
          insuranceExpiresAt: today.subtract(const Duration(days: 1)),
        ),
        isFalse,
      );
    });

    test('갱신(미래 만료일) 후 예약 가능·뱃지 없음', () {
      final renewed = today.add(const Duration(days: 180));
      expect(VehicleInsuranceStatus.isExpired(renewed), isFalse);
      expect(
        VehicleInsuranceStatus.badgeKind(renewed),
        VehicleInsuranceBadgeKind.none,
      );
      expect(
        VehicleInsuranceStatus.isResidentBookable(
          isPublished: true,
          isUnderMaintenance: false,
          insuranceExpiresAt: renewed,
        ),
        isTrue,
      );
    });

    test('is_published=false면 보험 유효해도 미노출', () {
      expect(
        VehicleInsuranceStatus.isResidentBookable(
          isPublished: false,
          isUnderMaintenance: false,
          insuranceExpiresAt: today.add(const Duration(days: 90)),
        ),
        isFalse,
      );
    });
  });
}
