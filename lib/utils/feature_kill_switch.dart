import '../models/app_feature_config.dart';
import '../utils/rental_pricing.dart';

const featureDisabledCode = 'feature_disabled';

String bookingFeatureKeyFor(RentalType rentalType) {
  switch (rentalType) {
    case RentalType.hourly:
      return AppFeatureKeys.bookingHourly;
    case RentalType.daily:
      return AppFeatureKeys.bookingDaily;
    case RentalType.monthly:
      return AppFeatureKeys.bookingMonthly;
  }
}

String featureLabelKo(String featureKey) {
  switch (featureKey) {
    case AppFeatureKeys.bookingHourly:
      return '카셰어링 예약';
    case AppFeatureKeys.bookingDaily:
      return '일렌트 예약';
    case AppFeatureKeys.bookingMonthly:
      return '월렌트 예약';
    case AppFeatureKeys.payment:
      return '신규 결제';
    case AppFeatureKeys.extension:
      return '이용 연장';
    default:
      return featureKey;
  }
}

bool isFeatureDisabledError(Object error) {
  return error.toString().toLowerCase().contains(featureDisabledCode);
}
