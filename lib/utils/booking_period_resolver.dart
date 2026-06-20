import 'daily_rental_duration.dart';
import 'rental_pricing.dart';

enum BookingPeriodInquiry {
  dailyOverMax,
  monthlyOverMax,
}

class BookingPeriodResult {
  final RentalType rentalType;
  final int hours;
  final int days;
  final int months;
  final DateTime start;
  final DateTime end;
  final bool valid;
  final BookingPeriodInquiry? inquiry;

  const BookingPeriodResult({
    required this.rentalType,
    required this.hours,
    required this.days,
    required this.months,
    required this.start,
    required this.end,
    required this.valid,
    this.inquiry,
  });

  factory BookingPeriodResult.invalid() => BookingPeriodResult(
        rentalType: RentalType.hourly,
        hours: 0,
        days: 1,
        months: 1,
        start: DateTime(1970),
        end: DateTime(1970),
        valid: false,
      );

  factory BookingPeriodResult.inquiry(BookingPeriodInquiry kind) =>
      BookingPeriodResult(
        rentalType: RentalType.daily,
        hours: 0,
        days: 0,
        months: 0,
        start: DateTime(1970),
        end: DateTime(1970),
        valid: false,
        inquiry: kind,
      );
}

/// 예약 1단계 — 시작/반납일·시각으로 rental_type·기간 산출 (RentalPricing 재사용)
abstract final class BookingPeriodResolver {
  static DateTime dateOnly(DateTime dt) {
    final local = dt.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  static bool isSameCalendarDay(DateTime a, DateTime b) =>
      dateOnly(a) == dateOnly(b);

  static DateTime buildStart(DateTime day, int hour) =>
      DateTime(day.year, day.month, day.day, hour);

  static DateTime? buildEnd({
    required DateTime startDay,
    required DateTime returnDay,
    required int startHour,
    int? endHour,
    int? returnHour,
  }) {
    if (isSameCalendarDay(startDay, returnDay)) {
      if (endHour == null) return null;
      var end = DateTime(startDay.year, startDay.month, startDay.day, endHour);
      final start = buildStart(startDay, startHour);
      if (!end.isAfter(start)) {
        end = end.add(const Duration(days: 1));
      }
      return end;
    }
    final hour = returnHour ?? startHour;
    final end = DateTime(returnDay.year, returnDay.month, returnDay.day, hour);
    final start = buildStart(startDay, startHour);
    if (start != null && !end.isAfter(start)) return null;
    return end;
  }

  static BookingPeriodResult resolve({
    required DateTime startDay,
    required DateTime returnDay,
    required int startHour,
    int? endHour,
    int? returnHour,
  }) {
    final start = buildStart(startDay, startHour);
    final end = buildEnd(
      startDay: startDay,
      returnDay: returnDay,
      startHour: startHour,
      endHour: endHour,
      returnHour: returnHour,
    );
    if (end == null || !end.isAfter(start)) {
      return BookingPeriodResult.invalid();
    }

    if (isSameCalendarDay(startDay, returnDay)) {
      final hours = RentalPricing.inferHoursBetween(start, end);
      if (hours == null) return BookingPeriodResult.invalid();
      return BookingPeriodResult(
        rentalType: RentalType.hourly,
        hours: hours,
        days: 1,
        months: 1,
        start: start,
        end: end,
        valid: RentalPricing.isValidDuration(
          RentalType.hourly,
          hours: hours,
          days: 1,
          months: 1,
        ),
      );
    }

    final maxReturn = RentalPricing.maxReturnDay(dateOnly(startDay));
    if (dateOnly(returnDay).isAfter(dateOnly(maxReturn))) {
      return BookingPeriodResult.inquiry(BookingPeriodInquiry.monthlyOverMax);
    }

    final type = RentalPricing.inferRentalTypeFromInterval(start: start, end: end);
    if (type == RentalType.daily) {
      final split = DailyRentalDurationSplit.fromInterval(start: start, end: end);
      if (split.fullDays < 1 || split.fullDays > RentalPricing.maxDailyDays) {
        return BookingPeriodResult.invalid();
      }
      return BookingPeriodResult(
        rentalType: RentalType.daily,
        hours: 0,
        days: split.fullDays,
        months: 1,
        start: start,
        end: end,
        valid: true,
      );
    }

    final months = RentalPricing.inferMonthsBetween(start, end) ??
        RentalPricing.inferBillingMonthsBetween(start, end);
    if (months == null) {
      return BookingPeriodResult.inquiry(BookingPeriodInquiry.monthlyOverMax);
    }
    return BookingPeriodResult(
      rentalType: RentalType.monthly,
      hours: 0,
      days: 1,
      months: months,
      start: start,
      end: end,
      valid: true,
    );
  }

  static String inquiryMessage(BookingPeriodInquiry inquiry) {
    switch (inquiry) {
      case BookingPeriodInquiry.dailyOverMax:
        return '30일 이상 대여는 앱에서 월 단위로 예약하시거나 전화로 문의해 주세요.';
      case BookingPeriodInquiry.monthlyOverMax:
        return '11개월을 초과하는 장기 대여는 전화로 문의해 주세요.';
    }
  }
}
