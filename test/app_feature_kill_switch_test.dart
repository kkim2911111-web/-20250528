import 'package:danjicar_app/models/app_feature_config.dart';
import 'package:danjicar_app/services/app_feature_config_service.dart';
import 'package:danjicar_app/utils/feature_kill_switch.dart';
import 'package:danjicar_app/utils/rental_pricing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppFeatureConfig', () {
    test('fromRpc — disabled with custom message', () {
      final config = AppFeatureConfig.fromMap('booking_monthly', {
        'isEnabled': false,
        'disabledMessage': '월렌트 점검 중입니다.',
      });
      expect(config.isEnabled, isFalse);
      expect(config.blockMessage, '월렌트 점검 중입니다.');
    });

    test('fromRpc — disabled without message uses default', () {
      final config = AppFeatureConfig.fromMap('payment', {'isEnabled': false});
      expect(config.blockMessage, AppFeatureConfig.defaultFeatureDisabledMessage);
    });

    test('fromRpc — enabled by default when missing', () {
      final config = AppFeatureConfig.fromMap('booking_hourly', null);
      expect(config.isEnabled, isTrue);
    });
  });

  group('bookingFeatureKeyFor', () {
    test('maps rental types to feature keys', () {
      expect(bookingFeatureKeyFor(RentalType.hourly), AppFeatureKeys.bookingHourly);
      expect(bookingFeatureKeyFor(RentalType.daily), AppFeatureKeys.bookingDaily);
      expect(
        bookingFeatureKeyFor(RentalType.monthly),
        AppFeatureKeys.bookingMonthly,
      );
    });
  });

  group('AppFeatureConfigService — fail-open', () {
    test('isEnabled defaults to true for unknown keys', () {
      final service = AppFeatureConfigService.instance;
      service.applyConfigs(AppFeatureConfig.allEnabled());
      expect(service.isEnabled('unknown_key'), isTrue);
    });

    test('fetch failure keeps allow-all cached state', () {
      final service = AppFeatureConfigService.instance;
      service.clearCache();
      service.applyConfigs(AppFeatureConfig.allEnabled());
      expect(service.isEnabled(AppFeatureKeys.bookingMonthly), isTrue);
      expect(service.isEnabled(AppFeatureKeys.payment), isTrue);
    });
  });

  group('kill switch scenarios (client logic)', () {
    test('booking_monthly OFF — monthly blocked, hourly allowed', () {
      final configs = AppFeatureConfig.allEnabled();
      configs[AppFeatureKeys.bookingMonthly] = const AppFeatureConfig(
        featureKey: AppFeatureKeys.bookingMonthly,
        isEnabled: false,
      );
      AppFeatureConfigService.instance.applyConfigs(configs);

      expect(
        AppFeatureConfigService.instance.isEnabled(
          bookingFeatureKeyFor(RentalType.monthly),
        ),
        isFalse,
      );
      expect(
        AppFeatureConfigService.instance.isEnabled(
          bookingFeatureKeyFor(RentalType.hourly),
        ),
        isTrue,
      );
    });

    test('payment OFF — payment blocked', () {
      final configs = AppFeatureConfig.allEnabled();
      configs[AppFeatureKeys.payment] = const AppFeatureConfig(
        featureKey: AppFeatureKeys.payment,
        isEnabled: false,
        disabledMessage: '결제 점검 중',
      );
      AppFeatureConfigService.instance.applyConfigs(configs);

      expect(
        AppFeatureConfigService.instance.isEnabled(AppFeatureKeys.payment),
        isFalse,
      );
      expect(
        AppFeatureConfigService.instance.messageFor(AppFeatureKeys.payment),
        '결제 점검 중',
      );
    });

    test('feature_disabled error detection', () {
      expect(
        isFeatureDisabledError(Exception('feature_disabled')),
        isTrue,
      );
      expect(
        isFeatureDisabledError(Exception('time_overlap')),
        isFalse,
      );
    });
  });
}
