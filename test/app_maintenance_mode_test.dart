import 'package:danjicar_app/models/app_maintenance_status.dart';
import 'package:danjicar_app/utils/maintenance_error.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppMaintenanceStatus', () {
    test('fromRpc — enabled with custom message', () {
      final status = AppMaintenanceStatus.fromRpc({
        'enabled': true,
        'message': '오늘 밤 12시까지 점검합니다.',
      });
      expect(status.enabled, isTrue);
      expect(status.message, '오늘 밤 12시까지 점검합니다.');
    });

    test('fromRpc — disabled', () {
      final status = AppMaintenanceStatus.fromRpc({'enabled': false});
      expect(status.enabled, isFalse);
    });

    test('fromSettingsValue — app_settings.value shape', () {
      final status = AppMaintenanceStatus.fromSettingsValue({
        'enabled': true,
        'message': '잠시만 기다려주세요.',
      });
      expect(status.enabled, isTrue);
      expect(status.message, '잠시만 기다려주세요.');
    });

    test('OFF 상태 — disabled 기본 메시지', () {
      expect(AppMaintenanceStatus.disabled.enabled, isFalse);
      expect(
        AppMaintenanceStatus.fromRpc(null).enabled,
        isFalse,
      );
    });
  });

  group('maintenance_error', () {
    test('detects maintenance_active from Postgrest-style message', () {
      expect(
        isMaintenanceActiveError(
          Exception('maintenance_active'),
        ),
        isTrue,
      );
    });

    test('ignores unrelated errors', () {
      expect(
        isMaintenanceActiveError(Exception('time_overlap')),
        isFalse,
      );
    });
  });

  group('점검 ON/OFF 시나리오 (클라이언트)', () {
    test('ON — 입주민 차단 플래그', () {
      const on = AppMaintenanceStatus(
        enabled: true,
        message: '점검 중',
      );
      expect(on.enabled, isTrue);
    });

    test('OFF — 즉시 복귀(플래그 해제)', () {
      const off = AppMaintenanceStatus.disabled;
      expect(off.enabled, isFalse);
      expect(
        AppMaintenanceStatus.fromRpc({'enabled': false}).enabled,
        isFalse,
      );
    });
  });
}
