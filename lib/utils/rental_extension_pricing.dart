import '../models/vehicle.dart';
import '../utils/booking_time_slots.dart';
import '../utils/rental_pricing.dart';

/// 연장 요금·종료 시각 계산 (서버 `calc_rental_extension_added_price`와 동일)
abstract final class RentalExtensionPricing {
  static int addedPrice({
    required RentalType rentalType,
    required DateTime currentEnd,
    required DateTime newEnd,
    required Vehicle vehicle,
  }) {
    if (!newEnd.isAfter(currentEnd)) return 0;

    switch (rentalType) {
      case RentalType.daily:
        final rate = vehicle.dailyOverageHourlyRate;
        if (rate == null || rate <= 0) return 0;
        return _ceilDays(currentEnd, newEnd) * rate;
      case RentalType.monthly:
        final rate = vehicle.monthlyExcessDailyPrice;
        if (rate == null || rate <= 0) return 0;
        return _ceilDays(currentEnd, newEnd) * rate;
      case RentalType.hourly:
        final minutes = newEnd.difference(currentEnd).inMinutes;
        return RentalPricing.hourlyAmountFromMinutes(
          minutes,
          vehicle.pricePerHour,
        );
    }
  }

  static int _ceilDays(DateTime start, DateTime end) {
    final seconds = end.difference(start).inSeconds;
    return (seconds / 86400).ceil().clamp(1, 999);
  }

  static DateTime newEndForPreset({
    required RentalType rentalType,
    required DateTime currentEnd,
    required int presetValue,
  }) {
    switch (rentalType) {
      case RentalType.hourly:
        return currentEnd.add(Duration(hours: presetValue));
      case RentalType.daily:
      case RentalType.monthly:
        return currentEnd.add(Duration(days: presetValue));
    }
  }

  static List<int> presetValuesFor(RentalType rentalType) {
    switch (rentalType) {
      case RentalType.hourly:
        return const [1, 2, 3];
      case RentalType.daily:
        return const [1, 2, 3];
      case RentalType.monthly:
        return const [30];
    }
  }

  static String presetLabel(RentalType rentalType, int value) {
    switch (rentalType) {
      case RentalType.hourly:
        return '+${value}시간';
      case RentalType.daily:
        return '+${value}일';
      case RentalType.monthly:
        return '+${value}일';
    }
  }

  static String sectionTitle(RentalType rentalType) {
    switch (rentalType) {
      case RentalType.hourly:
        return '카셰어링';
      case RentalType.daily:
        return '일렌트';
      case RentalType.monthly:
        return '월렌트';
    }
  }

  /// 직접 선택 — 연장 후 종료 시각 후보
  static List<DateTime> customEndOptions({
    required RentalType rentalType,
    required DateTime currentEnd,
    DateTime? maxEnd,
  }) {
    final options = <DateTime>[];
    switch (rentalType) {
      case RentalType.hourly:
        var cursor = currentEnd.add(const Duration(hours: 1));
        for (var i = 0; i < RentalPricing.maxHourlyHours; i++) {
          if (maxEnd != null && cursor.isAfter(maxEnd)) break;
          options.add(cursor);
          cursor = cursor.add(const Duration(hours: 1));
        }
      case RentalType.daily:
        var cursor = currentEnd.add(const Duration(days: 1));
        for (var i = 0; i < RentalPricing.maxDailyDays; i++) {
          if (maxEnd != null && cursor.isAfter(maxEnd)) break;
          options.add(cursor);
          cursor = cursor.add(const Duration(days: 1));
        }
      case RentalType.monthly:
        var cursor = currentEnd.add(const Duration(days: 30));
        final limit = currentEnd.add(
          Duration(days: RentalPricing.maxMonthlyMonths * 30),
        );
        while (!cursor.isAfter(limit)) {
          if (maxEnd != null && cursor.isAfter(maxEnd)) break;
          options.add(cursor);
          cursor = cursor.add(const Duration(days: 1));
        }
    }
    return options;
  }

  /// `BookingDrumTimePicker`용 카탈로그
  static BookingDrumTimeCatalog drumCatalogForEnds(
    List<DateTime> endOptions,
    DateTime anchorDay,
  ) {
    if (endOptions.isEmpty) {
      return const BookingDrumTimeCatalog(hourOptions: [], minutesPerHour: []);
    }

    final anchor = DateTime(anchorDay.year, anchorDay.month, anchorDay.day);
    final slots = <({int hour, int minute})>[];
    for (final dt in endOptions) {
      slots.add((hour: dt.hour, minute: dt.minute));
    }

    return BookingDrumTimeCatalog.fromSlots(
      slots,
      isNextDayFor: (hour, minute) {
        final idx = slots.indexWhere((s) => s.hour == hour && s.minute == minute);
        if (idx < 0) return false;
        final dt = endOptions[idx];
        final slotDay = DateTime(dt.year, dt.month, dt.day);
        return slotDay.isAfter(anchor);
      },
    );
  }

  static DateTime? endFromDrumSlot({
    required List<DateTime> endOptions,
    required int hour,
    required int minute,
    bool isNextDay = false,
  }) {
    for (final dt in endOptions) {
      final nextDay = DateTime(dt.year, dt.month, dt.day).isAfter(
        DateTime(
          endOptions.first.year,
          endOptions.first.month,
          endOptions.first.day,
        ),
      );
      if (dt.hour == hour && dt.minute == minute && nextDay == isNextDay) {
        return dt;
      }
    }
    for (final dt in endOptions) {
      if (dt.hour == hour && dt.minute == minute) return dt;
    }
    return null;
  }
}
