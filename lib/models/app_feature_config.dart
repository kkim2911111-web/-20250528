class AppFeatureConfig {
  final String featureKey;
  final bool isEnabled;
  final String? disabledMessage;

  const AppFeatureConfig({
    required this.featureKey,
    this.isEnabled = true,
    this.disabledMessage,
  });

  String get blockMessage =>
      disabledMessage?.trim().isNotEmpty == true
          ? disabledMessage!.trim()
          : defaultFeatureDisabledMessage;

  static const defaultFeatureDisabledMessage =
      '현재 점검 중입니다. 잠시 후 다시 이용해주세요.';

  static const allEnabledKeys = [
    AppFeatureKeys.bookingHourly,
    AppFeatureKeys.bookingDaily,
    AppFeatureKeys.bookingMonthly,
    AppFeatureKeys.payment,
    AppFeatureKeys.extension,
  ];

  static Map<String, AppFeatureConfig> allEnabled() {
    return {
      for (final key in allEnabledKeys) key: AppFeatureConfig(featureKey: key),
    };
  }

  factory AppFeatureConfig.fromMap(String key, Object? raw) {
    if (raw is! Map) {
      return AppFeatureConfig(featureKey: key);
    }
    final m = Map<String, dynamic>.from(raw);
    return AppFeatureConfig(
      featureKey: key,
      isEnabled: m['isEnabled'] != false,
      disabledMessage: m['disabledMessage']?.toString(),
    );
  }

  factory AppFeatureConfig.fromSuperAdminRow(Map<String, dynamic> row) {
    final key = row['featureKey']?.toString() ?? '';
    return AppFeatureConfig(
      featureKey: key,
      isEnabled: row['isEnabled'] != false,
      disabledMessage: row['disabledMessage']?.toString(),
    );
  }

  Map<String, dynamic> toSuperAdminParams() => {
        'featureKey': featureKey,
        'isEnabled': isEnabled,
        'disabledMessage': disabledMessage,
      };
}

abstract final class AppFeatureKeys {
  static const bookingHourly = 'booking_hourly';
  static const bookingDaily = 'booking_daily';
  static const bookingMonthly = 'booking_monthly';
  static const payment = 'payment';
  static const extension = 'extension';
}
