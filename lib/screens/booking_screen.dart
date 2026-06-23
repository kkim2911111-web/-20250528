import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../config/payment_config.dart';
import '../models/coupon.dart';
import '../models/vehicle.dart';
import '../models/vehicle_query_result.dart';
import '../services/app_feature_config_service.dart';
import '../services/coupon_service.dart';
import '../services/payment_service.dart';
import '../services/point_service.dart';
import '../utils/point_policy.dart';
import '../services/reservation_service.dart';
import '../services/vehicle_service.dart';
import '../supabase_client.dart';
import '../theme/danji_colors.dart';
import '../theme/danji_typography.dart';
import '../utils/booking_period_resolver.dart';
import '../utils/booking_time_slots.dart';
import '../utils/feature_kill_switch_guard.dart';
import '../utils/booking_vehicle_price_display.dart';
import '../utils/rental_inquiry_flow.dart';
import '../utils/rental_interval_billing.dart' as interval_billing;
import '../utils/rental_pricing.dart';
import '../widgets/booking_time_drum_picker.dart';
import '../widgets/danji_app_bar.dart';
import '../widgets/payment_method_sheet.dart';

bool _isHoliday(DateTime day) {
  return _BookingScreenState._holidays.any(
    (h) => h.year == day.year && h.month == day.month && h.day == day.day,
  );
}

Color _bookingCalendarDayTextColor(DateTime day, {required bool isPast}) {
  if (isPast) return const Color(0xFFCCCCCC);
  if (_isHoliday(day) || day.weekday == DateTime.sunday) {
    return const Color(0xFFF04452);
  }
  if (day.weekday == DateTime.saturday) {
    return const Color(0xFF3182F6);
  }
  return const Color(0xFF111111);
}

class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  static final List<DateTime> _holidays = [
    // 2026년 공휴일
    DateTime(2026, 1, 1), // 신정
    DateTime(2026, 2, 17), // 설날 연휴
    DateTime(2026, 2, 18), // 설날
    DateTime(2026, 2, 19), // 설날 연휴
    DateTime(2026, 3, 1), // 삼일절
    DateTime(2026, 5, 5), // 어린이날
    DateTime(2026, 5, 24), // 부처님오신날
    DateTime(2026, 6, 3), // 지방선거일 (임시공휴일)
    DateTime(2026, 6, 6), // 현충일
    DateTime(2026, 8, 15), // 광복절
    DateTime(2026, 9, 24), // 추석 연휴
    DateTime(2026, 9, 25), // 추석
    DateTime(2026, 9, 26), // 추석 연휴
    DateTime(2026, 10, 3), // 개천절
    DateTime(2026, 10, 9), // 한글날
    DateTime(2026, 12, 25), // 성탄절
  ];

  final _vehicleService = VehicleService();
  final _reservationService = ReservationService();
  final _paymentService = PaymentService();
  final _couponService = CouponService();
  final _pointService = PointService();
  final _dateLabelFormat = DateFormat('yyyy년 M월 d일 (E)', 'ko_KR');
  final _periodDateFormat = DateFormat('M/d HH:mm');

  Future<VehicleQueryResult>? _vehiclesFuture;
  Future<List<_BookingVehicleListEntry>>? _vehicleListFuture;
  VehicleQueryResult? _lastResult;
  List<Vehicle> _allVehicles = [];
  Vehicle? _selected;
  late DateTime _focusedDay;
  late DateTime _returnFocusedDay;
  DateTime? _startDay;
  DateTime? _returnDay;
  int _startHour = 9;
  int _startMinute = 0;
  int _endHour = 10;
  int _endMinute = 0;
  bool _endHourManuallySet = false;
  int _returnHour = 9;
  int _returnMinute = 0;
  bool _returnHourManuallySet = false;
  RentalType _rentalType = RentalType.hourly;
  int _durationDays = 1;
  int _durationMonths = 1;
  bool _loading = false;
  String? _error;
  bool _autoBumpedEmptyList = false;

  List<UserCoupon> _availableCoupons = [];
  int _pointBalance = 0;
  String? _selectedUserCouponId;
  bool _usePoints = false;
  int _pointsToUse = 0;
  bool _checkoutExtrasLoaded = false;
  bool _loadingCheckoutExtras = false;

  @override
  void initState() {
    super.initState();
    _applyInitialDateTime();
    _applyResolvedPeriod(_resolvedPeriod);
    _vehiclesFuture = _loadVehicles();
    AppFeatureConfigService.instance.fetch(force: true);
  }

  /// 23:50 이후 — 내일 00:00 시작 / 그 외 — 다음 10분 슬롯
  void _applyInitialDateTime() {
    final now = DateTime.now();
    if (now.hour >= 23 && now.minute >= 50) {
      final tomorrow = _todayCalendarDate.add(const Duration(days: 1));
      _startDay = tomorrow;
      _returnDay = tomorrow;
      _focusedDay = tomorrow;
      _returnFocusedDay = tomorrow;
      _startHour = 0;
      _startMinute = 0;
      _endHour = 0;
      _endMinute = 10;
    } else {
      final today = _todayCalendarDate;
      _startDay = today;
      _returnDay = today;
      _focusedDay = today;
      _returnFocusedDay = today;
      final next = BookingTimeSlots.ceilToNextSlot(now);
      _startHour = next.hour;
      _startMinute = next.minute;
      final end = next.add(const Duration(hours: 1));
      _endHour = end.hour;
      _endMinute = end.minute;
    }
    _endHourManuallySet = false;
    _returnHour = _startHour;
    _returnMinute = _startMinute;
    _returnHourManuallySet = false;
    _normalizeTimesForSelectedDay();
    if (!_endHourManuallySet) {
      _syncEndTimeFromStart(force: true);
    }
  }

  DateTime get _tomorrowCalendarDate =>
      _todayCalendarDate.add(const Duration(days: 1));

  bool get _isTomorrowMidnightSlot {
    final day = _startDay;
    if (day == null) return false;
    return isSameDay(day, _tomorrowCalendarDate) &&
        _startHour == 0 &&
        _startMinute == 0;
  }

  void _applyTomorrowMidnightSlot() {
    _startDay = _tomorrowCalendarDate;
    _returnDay = _tomorrowCalendarDate;
    _focusedDay = _tomorrowCalendarDate;
    _returnFocusedDay = _tomorrowCalendarDate;
    _startHour = 0;
    _startMinute = 0;
    _endHour = 0;
    _endMinute = 10;
    _endHourManuallySet = false;
    _returnHour = _startHour;
    _returnMinute = _startMinute;
    _returnHourManuallySet = false;
    _normalizeTimesForSelectedDay();
    if (!_endHourManuallySet) {
      _syncEndTimeFromStart(force: true);
    }
  }

  DateTime _dateOnly(DateTime dt) => _localDateOnly(dt);

  /// 로컬 연월일 (KST 등 디바이스 타임존)
  DateTime _localDateOnly(DateTime dt) {
    final local = dt.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  /// TableCalendar 셀용 UTC 연월일 (패키지 내부 day.isBefore(firstDay)와 동일 기준)
  DateTime _tableCalendarDay(DateTime dt) {
    final local = dt.toLocal();
    return DateTime.utc(local.year, local.month, local.day);
  }

  /// 달력·선택용 오늘 (시간 제거, 로컬 연월일)
  DateTime get _todayCalendarDate => _localDateOnly(DateTime.now());

  DateTime _calendarDateOnly(DateTime dt) => _localDateOnly(dt);

  /// 오늘 이전 날짜만 비활성 (오늘 포함 이후는 선택 가능)
  bool _isCalendarDayBeforeToday(DateTime day) {
    return _tableCalendarDay(day).isBefore(_tableCalendarDay(DateTime.now()));
  }

  bool _isCalendarDayEnabled(DateTime day) =>
      !_isCalendarDayBeforeToday(day);

  Widget _bookingCalendarDayCell(DateTime cellDay, {bool isPast = false}) {
    return _BookingRangeDayCell(
      day: cellDay,
      isToday: _isToday(cellDay),
      isRangeStart: _isRangeStart(cellDay),
      isRangeEnd: _isRangeEnd(cellDay),
      isInRange: _isInBookingRange(cellDay),
      isPast: isPast,
    );
  }

  Future<VehicleQueryResult> _loadVehicles() async {
    final result = await _vehicleService.fetchVehiclesForMyComplex();
    _lastResult = result;
    _allVehicles = result.vehicles;

    _applyResolvedPeriod(_resolvedPeriod);
    if (!_availableRentalTypes.contains(_rentalType)) {
      _rentalType = _availableRentalTypes.first;
    }
    _refreshAvailability();
    return result;
  }

  Set<RentalType> get _availableRentalTypes {
    if (_selected != null) return _selected!.rentalTypes.toSet();
    final types = <RentalType>{};
    for (final vehicle in _allVehicles) {
      types.addAll(vehicle.rentalTypes);
    }
    return types.isEmpty ? {RentalType.hourly} : types;
  }

  bool get _hasValidDuration {
    final period = _resolvedPeriod;
    return period != null && period.valid && period.inquiry == null;
  }

  bool get _isSameDayBooking =>
      _startDay != null &&
      _returnDay != null &&
      BookingPeriodResolver.isSameCalendarDay(_startDay!, _returnDay!);

  bool get _fleetAllowsDailyReturnTime =>
      RentalPricing.fleetAllowsDailyReturnTime(_allVehicles);

  bool get _allowsDailyReturnTimePick =>
      !_isSameDayBooking && _fleetAllowsDailyReturnTime;

  BookingPeriodResult? get _resolvedPeriod {
    final startDay = _startDay;
    final returnDay = _returnDay;
    if (startDay == null || returnDay == null) return null;
    return BookingPeriodResolver.resolve(
      startDay: startDay,
      returnDay: returnDay,
      startHour: _startHour,
      startMinute: _startMinute,
      endHour: _isSameDayBooking ? _endHour : null,
      endMinute: _isSameDayBooking ? _endMinute : null,
      returnHour: _allowsDailyReturnTimePick ? _returnHour : null,
      returnMinute: _allowsDailyReturnTimePick ? _returnMinute : null,
    );
  }

  void _applyResolvedPeriod(BookingPeriodResult? period) {
    if (period == null || !period.valid) return;
    _rentalType = period.rentalType;
    switch (period.rentalType) {
      case RentalType.hourly:
        _durationDays = 1;
        _durationMonths = 1;
        break;
      case RentalType.daily:
        _durationDays = period.days;
        _durationMonths = 1;
        break;
      case RentalType.monthly:
        _durationDays = 1;
        _durationMonths = period.months;
        break;
    }
  }

  String get _durationSummary {
    final period = _resolvedPeriod;
    if (period != null && period.valid) {
      return RentalPricing.formatDurationLabelFromInterval(
        start: period.start,
        end: period.end,
      );
    }
    return RentalPricing.durationSummary(
      _rentalType,
      hours: _resolvedPeriod?.hours ?? 0,
      days: _durationDays,
      months: _durationMonths,
    );
  }

  String? get _periodSummaryLine {
    final period = _resolvedPeriod;
    if (period == null || !period.valid) return null;
    final startLabel = _periodDateFormat.format(period.start);
    final endLabel = _periodDateFormat.format(period.end);
    final duration = _durationSummary;
    final price = _originalPrice;
    final buffer = StringBuffer('$startLabel ~ $endLabel · $duration');
    if (price != null) {
      buffer.write(' · ₩${_formatWon(price)}');
    }
    return buffer.toString();
  }

  int get _activeStep {
    if (_selected == null) return 1;
    if (_hasValidDuration && _originalPrice != null) return 3;
    return 2;
  }

  /// 3단계 확인/결제 — 차량 선택 후 쿠폰·포인트 패널 표시
  bool get _showCheckoutDiscounts =>
      _selected != null && _hasValidDuration && _originalPrice != null;

  String get _durationLabel {
    final period = _resolvedPeriod;
    if (period != null && period.valid && period.rentalType == RentalType.hourly) {
      return RentalPricing.formatHourlyDurationLabel(period.minutes);
    }
    final start = _buildStartDateTime(_startDay, _startHour, _startMinute);
    final end = _buildEndDateTime(_startDay, _endHour, _endMinute);
    if (start == null || end == null) return '';
    final minutes = RentalPricing.inferMinutesBetween(start, end);
    if (minutes == null) return '';
    return RentalPricing.formatHourlyDurationLabel(minutes);
  }

  bool get _hasValidHourlyDuration {
    final period = _resolvedPeriod;
    if (period != null && period.valid && period.rentalType == RentalType.hourly) {
      return period.minutes >= RentalPricing.minHourlyMinutes;
    }
    return false;
  }

  DateTime? get _rangeStartDay => _startDay;

  DateTime? get _rangeEndDay => _returnDay;

  bool _isRangeStart(DateTime day) {
    final start = _rangeStartDay;
    return start != null && isSameDay(day, start);
  }

  bool _isRangeEnd(DateTime day) {
    final end = _rangeEndDay;
    return end != null && isSameDay(day, end);
  }

  bool _isInBookingRange(DateTime day) {
    final start = _rangeStartDay;
    final end = _rangeEndDay;
    if (start == null || end == null) return false;
    final d = _dateOnly(day);
    final s = _dateOnly(start);
    final e = _dateOnly(end);
    if (e.isBefore(s)) return isSameDay(day, s);
    return !d.isBefore(s) && !d.isAfter(e);
  }

  bool _isToday(DateTime day) =>
      _localDateOnly(day) == _todayCalendarDate;

  /// 오늘이면 시작 시각(시간 단위)이 현재 시각보다 뒤인지
  bool _isStartTimeInFuture(DateTime startTime) =>
      startTime.isAfter(DateTime.now());

  bool _isStartSlotSelectable(DateTime day, int hour, int minute) {
    final slot = _buildStartDateTime(day, hour, minute);
    if (slot == null) return false;
    if (!_isToday(day)) return true;
    return _isStartTimeInFuture(slot);
  }

  List<({int hour, int minute})> get _startTimeOptions {
    final day = _startDay;
    if (day == null) return const [];
    return [
      for (final slot in BookingTimeSlots.allSlots())
        if (_isStartSlotSelectable(day, slot.hour, slot.minute)) slot,
    ];
  }

  List<({int hour, int minute})> get _endTimeOptions {
    final day = _startDay;
    if (day == null) return const [];

    final start = _buildStartDateTime(day, _startHour, _startMinute);
    if (start == null) return const [];

    return BookingTimeSlots.slotsAfter(
      start,
      minMinutes: RentalPricing.minHourlyMinutes,
      maxMinutes: RentalPricing.maxHourlyMinutes,
    ).where((slot) => _isValidEndSlot(day, slot.hour, slot.minute)).toList();
  }

  List<({int hour, int minute})> get _returnTimeOptions {
    return [
      for (final slot in BookingTimeSlots.allSlots())
        if (_isValidReturnSlot(slot.hour, slot.minute)) slot,
    ];
  }

  bool _isValidReturnSlot(int hour, int minute) {
    final startDay = _startDay;
    final returnDay = _returnDay;
    if (startDay == null || returnDay == null) return false;
    final period = BookingPeriodResolver.resolve(
      startDay: startDay,
      returnDay: returnDay,
      startHour: _startHour,
      startMinute: _startMinute,
      returnHour: hour,
      returnMinute: minute,
    );
    return period.valid && period.inquiry == null;
  }

  void _normalizeReturnTimeForSelectedPeriod() {
    if (!_allowsDailyReturnTimePick) {
      _returnHour = _startHour;
      _returnMinute = _startMinute;
      _returnHourManuallySet = false;
      return;
    }
    final options = _returnTimeOptions;
    if (options.isEmpty) return;
    final current = options.where(
      (slot) => slot.hour == _returnHour && slot.minute == _returnMinute,
    );
    if (current.isEmpty) {
      _returnHour = options.first.hour;
      _returnMinute = options.first.minute;
      _returnHourManuallySet = false;
    }
  }

  bool _isValidEndSlot(DateTime day, int endHour, int endMinute) {
    final start = _buildStartDateTime(day, _startHour, _startMinute);
    final end = _buildEndDateTime(day, endHour, endMinute);
    if (start == null || end == null) return false;
    return RentalPricing.inferMinutesBetween(start, end) != null;
  }

  DateTime? get _rentalStartTime {
    final period = _resolvedPeriod;
    if (period != null && period.valid) return period.start;
    return _buildStartDateTime(_startDay, _startHour, _startMinute);
  }

  DateTime? get _rentalEndTime {
    final period = _resolvedPeriod;
    if (period != null && period.valid) return period.end;
    final start = _rentalStartTime;
    if (start == null) return null;
    return RentalPricing.buildEndTime(
      start,
      _rentalType,
      endHour: _endHour,
      days: _durationDays,
      months: _durationMonths,
    );
  }

  /// 종료 시각 = 시작 + 1시간 (유효한 종료 시각 목록 기준)
  void _syncEndTimeFromStart({bool force = false}) {
    if (!force && _endHourManuallySet) return;

    final day = _startDay;
    if (day == null) return;

    final start = _buildStartDateTime(day, _startHour, _startMinute);
    if (start == null) return;

    final ends = _endTimeOptions;
    if (ends.isEmpty) return;

    for (final slot in ends) {
      final end = _buildEndDateTime(day, slot.hour, slot.minute);
      if (end != null && end.difference(start).inMinutes == 60) {
        _endHour = slot.hour;
        _endMinute = slot.minute;
        return;
      }
    }

    final first = ends.first;
    _endHour = first.hour;
    _endMinute = first.minute;
  }

  void _normalizeTimesForSelectedDay() {
    final starts = _startTimeOptions;
    if (starts.isEmpty) return;

    final currentStart = starts.where(
      (slot) => slot.hour == _startHour && slot.minute == _startMinute,
    );
    if (currentStart.isEmpty) {
      final first = starts.first;
      _startHour = first.hour;
      _startMinute = first.minute;
    }

    _syncEndTimeFromStart();

    final ends = _endTimeOptions;
    if (ends.isEmpty) return;
    final currentEnd = ends.where(
      (slot) => slot.hour == _endHour && slot.minute == _endMinute,
    );
    if (currentEnd.isEmpty) {
      final first = ends.first;
      _endHour = first.hour;
      _endMinute = first.minute;
      _endHourManuallySet = false;
    }
  }

  DateTime? _buildStartDateTime(DateTime? day, int hour, int minute) {
    if (day == null) return null;
    return BookingTimeSlots.buildLocal(day, hour, minute);
  }

  DateTime? _buildEndDateTime(DateTime? day, int hour, int minute) {
    if (day == null) return null;
    var end = BookingTimeSlots.buildLocal(day, hour, minute);
    final start = _buildStartDateTime(day, _startHour, _startMinute);
    if (start != null && !end.isAfter(start)) {
      end = end.add(const Duration(days: 1));
    }
    return end;
  }

  String _formatTimeLabel(int hour, int minute) =>
      BookingTimeSlots.format(hour, minute);

  String _formatEndTimeLabel(int hour, int minute) {
    final day = _startDay;
    if (day == null) return _formatTimeLabel(hour, minute);

    final start = _buildStartDateTime(day, _startHour, _startMinute);
    final end = _buildEndDateTime(day, hour, minute);
    if (start != null &&
        end != null &&
        _dateOnly(end).isAfter(_dateOnly(start))) {
      return '${_formatTimeLabel(hour, minute)} (익일)';
    }
    return _formatTimeLabel(hour, minute);
  }

  List<({int hour, int minute})> _endTimeOptionsFor(int startHour, int startMinute) {
    final day = _startDay;
    if (day == null) return const [];

    final start = _buildStartDateTime(day, startHour, startMinute);
    if (start == null) return const [];

    return BookingTimeSlots.slotsAfter(
      start,
      minMinutes: RentalPricing.minHourlyMinutes,
      maxMinutes: RentalPricing.maxHourlyMinutes,
    ).where(
      (slot) => _isValidEndSlotFor(day, startHour, startMinute, slot.hour, slot.minute),
    ).toList();
  }

  List<({int hour, int minute})> _returnTimeOptionsFor(int startHour, int startMinute) {
    return [
      for (final slot in BookingTimeSlots.allSlots())
        if (_isValidReturnSlotAt(startHour, startMinute, slot.hour, slot.minute))
          slot,
    ];
  }

  bool _isValidReturnSlotAt(
    int startHour,
    int startMinute,
    int hour,
    int minute,
  ) {
    final startDay = _startDay;
    final returnDay = _returnDay;
    if (startDay == null || returnDay == null) return false;
    final period = BookingPeriodResolver.resolve(
      startDay: startDay,
      returnDay: returnDay,
      startHour: startHour,
      startMinute: startMinute,
      returnHour: hour,
      returnMinute: minute,
    );
    return period.valid && period.inquiry == null;
  }

  bool _isValidEndSlotFor(
    DateTime day,
    int startHour,
    int startMinute,
    int endHour,
    int endMinute,
  ) {
    final start = BookingTimeSlots.buildLocal(day, startHour, startMinute);
    var end = BookingTimeSlots.buildLocal(day, endHour, endMinute);
    if (!end.isAfter(start)) {
      end = end.add(const Duration(days: 1));
    }
    return RentalPricing.inferMinutesBetween(start, end) != null;
  }

  bool _isSlotNextDayAfterStart(
    DateTime day,
    int startHour,
    int startMinute,
    int endHour,
    int endMinute,
  ) {
    final start = BookingTimeSlots.buildLocal(day, startHour, startMinute);
    var end = BookingTimeSlots.buildLocal(day, endHour, endMinute);
    if (!end.isAfter(start)) {
      end = end.add(const Duration(days: 1));
    }
    return _dateOnly(end).isAfter(_dateOnly(start));
  }

  bool get _currentEndIsNextDay {
    final day = _startDay;
    if (day == null || !_isSameDayBooking) return false;
    return _isSlotNextDayAfterStart(
      day,
      _startHour,
      _startMinute,
      _endHour,
      _endMinute,
    );
  }

  BookingDrumTimeCatalog get _startDrumCatalog =>
      BookingDrumTimeCatalog.fromSlots(_startTimeOptions);

  BookingDrumTimeCatalog _endDrumCatalogFor(int startHour, int startMinute) {
    final day = _startDay;
    if (day == null) {
      return const BookingDrumTimeCatalog(hourOptions: [], minutesPerHour: []);
    }
    return BookingDrumTimeCatalog.fromSlots(
      _endTimeOptionsFor(startHour, startMinute),
      isNextDayFor: (h, m) =>
          _isSlotNextDayAfterStart(day, startHour, startMinute, h, m),
    );
  }

  BookingDrumTimeCatalog _returnDrumCatalogFor(int startHour, int startMinute) {
    return BookingDrumTimeCatalog.fromSlots(
      _returnTimeOptionsFor(startHour, startMinute),
    );
  }

  String get _combinedTimeRangeLabel {
    final start = _formatTimeLabel(_startHour, _startMinute);
    if (_isSameDayBooking) {
      return '$start ~ ${_formatEndTimeLabel(_endHour, _endMinute)}';
    }
    if (_allowsDailyReturnTimePick) {
      return '$start ~ ${_formatTimeLabel(_returnHour, _returnMinute)}';
    }
    return start;
  }

  Future<void> _openBookingTimeDrumPicker() async {
    final startCatalog = _startDrumCatalog;
    if (startCatalog.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('선택 가능한 시간이 없습니다.')),
      );
      return;
    }

    if (_isSameDayBooking) {
      final endCatalog = _endDrumCatalogFor(_startHour, _startMinute);
      if (endCatalog.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('선택 가능한 종료 시각이 없습니다.')),
        );
        return;
      }

      final result = await showBookingTimeRangeDrumPicker(
        context: context,
        leftTitle: '출고',
        rightTitle: '반납',
        startCatalog: startCatalog,
        endCatalogBuilder: _endDrumCatalogFor,
        startHour: _startHour,
        startMinute: _startMinute,
        endHour: _endHour,
        endMinute: _endMinute,
        endIsNextDay: _currentEndIsNextDay,
      );
      if (result == null || !mounted) return;

      setState(() {
        _startHour = result.startHour;
        _startMinute = result.startMinute;
        _endHour = result.endHour;
        _endMinute = result.endMinute;
        _endHourManuallySet = true;
      });
      _onDateTimeChanged();
      return;
    }

    if (_allowsDailyReturnTimePick) {
      final returnCatalog = _returnDrumCatalogFor(_startHour, _startMinute);
      if (returnCatalog.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('선택 가능한 반납 시각이 없습니다.')),
        );
        return;
      }

      final result = await showBookingTimeRangeDrumPicker(
        context: context,
        leftTitle: '출고',
        rightTitle: '반납',
        startCatalog: startCatalog,
        endCatalogBuilder: _returnDrumCatalogFor,
        startHour: _startHour,
        startMinute: _startMinute,
        endHour: _returnHour,
        endMinute: _returnMinute,
      );
      if (result == null || !mounted) return;

      setState(() {
        _startHour = result.startHour;
        _startMinute = result.startMinute;
        _returnHour = result.endHour;
        _returnMinute = result.endMinute;
        _returnHourManuallySet = true;
      });
      _onDateTimeChanged();
      return;
    }

    final picked = await showBookingStartDrumPicker(
      context: context,
      startCatalog: startCatalog,
      startHour: _startHour,
      startMinute: _startMinute,
    );
    if (picked == null || !mounted) return;

    setState(() {
      _startHour = picked.hour;
      _startMinute = picked.minute;
      _returnHour = picked.hour;
      _returnMinute = picked.minute;
    });
    _onDateTimeChanged();
  }

  interval_billing.RentalPriceBreakdown? get _priceBreakdown {
    final vehicle = _selected;
    final period = _resolvedPeriod;
    if (vehicle == null || period == null || !_hasValidDuration) return null;
    return RentalPricing.calculateBasePriceBreakdownFromVehicle(
      vehicle,
      period.rentalType,
      start: period.start,
      end: period.end,
    );
  }

  String? get _dailyOveragePriceLabel {
    final breakdown = _priceBreakdown;
    final period = _resolvedPeriod;
    if (breakdown == null || period == null) return null;
    return breakdown.dailyOverageConfirmationLabel(
      fullDays: period.days,
      formatWon: _formatWon,
    );
  }

  int? get _originalPrice => _priceBreakdown?.amount;

  bool get _monthlyCapApplied {
    final vehicle = _selected;
    final period = _resolvedPeriod;
    if (vehicle == null || period == null || !_hasValidDuration) return false;
    return RentalPricing.monthlyCapAppliedForInterval(
      vehicle,
      period.rentalType,
      start: period.start,
      end: period.end,
    );
  }

  int? get _compareStrikethroughPrice {
    final vehicle = _selected;
    final period = _resolvedPeriod;
    if (vehicle == null || period == null || !_hasValidDuration) return null;
    return RentalPricing.comparisonStrikethroughPrice(
      vehicle,
      period.rentalType,
      hours: _resolvedPeriod?.hours ?? 0,
      days: _durationDays,
      months: _durationMonths,
      start: period.start,
      end: period.end,
    );
  }

  bool get _fleetAllowsPartialMonthlyReturn =>
      RentalPricing.fleetAllowsPartialMonthlyReturn(_allVehicles);

  int get _couponDiscount {
    final coupon = _selectedCoupon;
    if (coupon == null) return 0;
    return coupon.discountAmount;
  }

  int get _maxPointsUsable {
    if (!PointPolicy.canUsePoints(_pointBalance)) return 0;
    final original = _originalPrice;
    if (original == null) return 0;
    final afterCoupon = (original - _couponDiscount).clamp(0, original);
    if (afterCoupon < PointPolicy.minUseAmount) return 0;
    final cap = afterCoupon < _pointBalance ? afterCoupon : _pointBalance;
    return cap;
  }

  int get _pointsDiscount {
    if (!_usePoints) return 0;
    final amount = _pointsToUse;
    if (!PointPolicy.isValidUseAmount(amount)) return 0;
    if (amount > _maxPointsUsable) return 0;
    return amount;
  }

  bool get _pointsInputInvalid {
    if (!_usePoints || _maxPointsUsable <= 0) return false;
    return _pointsToUse < PointPolicy.minUseAmount ||
        _pointsToUse > _maxPointsUsable;
  }

  int? get _finalPrice {
    final original = _originalPrice;
    if (original == null) return null;
    final total = original - _couponDiscount - _pointsDiscount;
    return total < 0 ? 0 : total;
  }

  UserCoupon? get _selectedCoupon {
    final id = _selectedUserCouponId;
    if (id == null || id.isEmpty) return null;
    for (final c in _availableCoupons) {
      if (c.id == id) return c;
    }
    return null;
  }

  bool get _canSubmit {
    if (_loading || _selected == null || _originalPrice == null) return false;
    if (!_hasValidDuration) return false;
    if (_pointsInputInvalid) return false;
    final period = _resolvedPeriod;
    if (period?.inquiry != null) return false;
    if (period == null || !period.valid) return false;
    final start = period.start;
    if (_startDay != null &&
        _isToday(_startDay!) &&
        !_isStartTimeInFuture(start)) {
      return false;
    }
    return true;
  }

  void _resetCheckoutSelection() {
    _checkoutExtrasLoaded = false;
    _availableCoupons = [];
    _pointBalance = 0;
    _selectedUserCouponId = null;
    _usePoints = false;
    _pointsToUse = 0;
  }

  void _clampPointsToUse() {
    final max = _maxPointsUsable;
    if (max == 0) {
      _usePoints = false;
      _pointsToUse = 0;
      return;
    }
    if (_pointsToUse > max) _pointsToUse = max;
    if (_pointsToUse < 0) _pointsToUse = 0;
  }

  void _validateCouponForCurrentPrice() {
    final coupon = _selectedCoupon;
    final original = _originalPrice;
    if (coupon == null || original == null) return;
    if (!coupon.canApplyToOrderAmount(original)) {
      _selectedUserCouponId = null;
    }
  }

  void _scheduleCheckoutExtrasLoad() {
    if (!_showCheckoutDiscounts) return;
    if (_checkoutExtrasLoaded || _loadingCheckoutExtras) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadCheckoutExtras();
    });
  }

  Future<void> _loadCheckoutExtras() async {
    if (_loadingCheckoutExtras || !_showCheckoutDiscounts) return;
    setState(() => _loadingCheckoutExtras = true);
    try {
      final coupons = await _couponService.fetchAvailableCoupons();
      final balance = await _pointService.fetchBalance();
      if (!mounted) return;
      setState(() {
        _availableCoupons = coupons;
        _pointBalance = balance;
        _checkoutExtrasLoaded = true;
        _loadingCheckoutExtras = false;
        _validateCouponForCurrentPrice();
        _clampPointsToUse();
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingCheckoutExtras = false;
          _checkoutExtrasLoaded = true;
        });
      }
    }
  }

  void _onCouponSelected(String? userCouponId) {
    setState(() {
      _selectedUserCouponId = userCouponId;
      _validateCouponForCurrentPrice();
      _clampPointsToUse();
    });
  }

  void _onPointsToggle(bool value) {
    setState(() {
      _usePoints = value;
      if (value && _pointsToUse == 0) {
        final max = _maxPointsUsable;
        _pointsToUse = max >= PointPolicy.minUseAmount
            ? PointPolicy.minUseAmount
            : max;
      }
      if (!value) _pointsToUse = 0;
      _clampPointsToUse();
    });
  }

  void _onPointsAmountChanged(String text) {
    final parsed = int.tryParse(text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    setState(() => _pointsToUse = parsed < 0 ? 0 : parsed);
  }

  void _refreshAvailability() {
    final future = _buildVehicleListEntries(_allVehicles)
        .catchError((Object e, StackTrace st) {
      return <_BookingVehicleListEntry>[];
    });
    setState(() {
      _vehicleListFuture = future;
    });
    future.then(_onVehicleListUpdated);
  }

  Future<List<_BookingVehicleListEntry>> _buildVehicleListEntries(
    List<Vehicle> vehicles,
  ) async {
    final complexId = _lastResult?.complexId;
    final day = _startDay;

    if (day == null || !_hasValidDuration) {
      return [];
    }

    final period = _resolvedPeriod;
    if (period == null || !period.valid) {
      return [];
    }

    final startTime = period.start;
    final endTime = period.end;

    if (_isToday(day) && !_isStartTimeInFuture(startTime)) {
      return [];
    }

    final residentComplexId = complexId?.trim();
    final entries = <_BookingVehicleListEntry>[];

    for (final vehicle in vehicles) {
      if (!vehicle.isResidentBookable ||
          !vehicle.supportsRentalType(period.rentalType) ||
          !RentalPricing.vehicleSupportsBookingPeriod(
            vehicle,
            period.rentalType,
            start: startTime,
            end: endTime,
          )) {
        continue;
      }

      if (residentComplexId != null &&
          residentComplexId.isNotEmpty &&
          vehicle.complexId != residentComplexId) {
        continue;
      }

      final blockReason =
          await _reservationService.getVehicleBookingBlockReason(
        vehicleId: vehicle.id,
        startAt: startTime,
        endAt: endTime,
        isUnderMaintenance: vehicle.isUnderMaintenance,
      );
      entries.add(
        _BookingVehicleListEntry(
          vehicle: vehicle,
          blockReason: blockReason,
        ),
      );
    }

    entries.sort((a, b) {
      final aBlocked = a.isBlocked ? 1 : 0;
      final bBlocked = b.isBlocked ? 1 : 0;
      if (aBlocked != bBlocked) return aBlocked.compareTo(bBlocked);
      return a.vehicle.name.compareTo(b.vehicle.name);
    });

    return entries;
  }

  void _onVehicleListUpdated(List<_BookingVehicleListEntry> entries) {
    if (!mounted) return;

    if (entries.isEmpty &&
        _hasValidDuration &&
        _rentalType == RentalType.hourly &&
        !_autoBumpedEmptyList &&
        !_isTomorrowMidnightSlot) {
      _autoBumpedEmptyList = true;
      setState(() {
        _applyTomorrowMidnightSlot();
        _selected = null;
        _error = null;
      });
      _refreshAvailability();
      return;
    }

    if (entries.isEmpty && _hasValidDuration) {
      _autoBumpedEmptyList = true;
    }

    setState(() {
      if (_selected != null &&
          !entries.any(
            (e) => !e.isBlocked && e.vehicle.id == _selected!.id,
          )) {
        _selected = null;
      }
    });
  }

  void _onDateTimeChanged() {
    setState(() {
      _normalizeTimesForSelectedDay();
      _normalizeReturnTimeForSelectedPeriod();
      _applyResolvedPeriod(_resolvedPeriod);
      _error = null;
      _validateCouponForCurrentPrice();
      _clampPointsToUse();
    });
    _refreshAvailability();
    _scheduleCheckoutExtrasLoad();
  }

  void _selectVehicle(Vehicle vehicle) {
    setState(() {
      _selected = vehicle;
      if (!vehicle.supportsRentalType(_rentalType)) {
        _rentalType = vehicle.rentalTypes.first;
      }
      _error = null;
      _validateCouponForCurrentPrice();
      _clampPointsToUse();
    });
    _scheduleCheckoutExtrasLoad();
  }

  bool _isReturnDayEnabled(DateTime day) {
    if (!_isCalendarDayEnabled(day)) return false;
    final start = _startDay;
    if (start == null) return false;
    final dayOnly = _tableCalendarDay(day);
    if (dayOnly.isBefore(_tableCalendarDay(start))) return false;
    final maxReturn =
        _tableCalendarDay(RentalPricing.maxReturnDay(_localDateOnly(start)));
    if (dayOnly.isAfter(maxReturn)) return false;

    if (!_fleetAllowsPartialMonthlyReturn) {
      final previewEnd = BookingTimeSlots.buildLocal(
        day,
        _startHour,
        _startMinute,
      );
      final startTime = _buildStartDateTime(start, _startHour, _startMinute);
      if (startTime == null || !previewEnd.isAfter(startTime)) return false;
      final days = previewEnd.difference(startTime).inDays;
      if (days >= 30 && days % 30 != 0) return false;
    }
    return true;
  }

  Future<void> _openStartDayPicker() async {
    await _openBookingDayPicker(
      title: '대여 시작일',
      focusedDay: _focusedDay,
      selectedDay: _startDay,
      enabledDayPredicate: _isCalendarDayEnabled,
      onSelected: (selectedDay, newFocused) async {
        final picked = _calendarDateOnly(selectedDay);
        setState(() {
          _startDay = picked;
          _focusedDay = _calendarDateOnly(newFocused);
          if (_returnDay != null &&
              _tableCalendarDay(_returnDay!)
                  .isBefore(_tableCalendarDay(picked))) {
            _returnDay = picked;
            _returnFocusedDay = picked;
          }
        });
        _onDateTimeChanged();
      },
      onFocusedChanged: (newFocused) {
        _focusedDay = _calendarDateOnly(newFocused);
      },
    );
  }

  Future<void> _openReturnDayPicker() async {
    final start = _startDay;
    if (start == null) return;

    final calendarToday = _tableCalendarDay(DateTime.now());
    final startDayOnly = _tableCalendarDay(start);
    final firstDay =
        startDayOnly.isAfter(calendarToday) ? startDayOnly : calendarToday;
    final lastDay =
        _tableCalendarDay(RentalPricing.maxReturnDay(_localDateOnly(start)));

    await _openBookingDayPicker(
      title: '반납 일자',
      focusedDay: _returnFocusedDay,
      selectedDay: _returnDay,
      calendarFirstDay: firstDay,
      calendarLastDay: lastDay,
      enabledDayPredicate: _isReturnDayEnabled,
      onSelected: (selectedDay, newFocused) async {
        final picked = _calendarDateOnly(selectedDay);
        final preview = BookingPeriodResolver.resolve(
          startDay: start,
          returnDay: picked,
          startHour: _startHour,
          endHour: BookingPeriodResolver.isSameCalendarDay(start, picked)
              ? _endHour
              : null,
          returnHour: _allowsDailyReturnTimePick ? _returnHour : null,
        );
        if (preview.inquiry != null) {
          if (!mounted) return;
          await showExtendedRentalInquiryDialog(
            context,
            message: BookingPeriodResolver.inquiryMessage(preview.inquiry!),
          );
          return;
        }
        if (!mounted) return;
        setState(() {
          _returnDay = picked;
          _returnFocusedDay = _calendarDateOnly(newFocused);
        });
        _onDateTimeChanged();
      },
      onFocusedChanged: (newFocused) {
        _returnFocusedDay = _calendarDateOnly(newFocused);
      },
    );
  }

  Future<void> _openBookingDayPicker({
    required String title,
    required DateTime focusedDay,
    required DateTime? selectedDay,
    required bool Function(DateTime day) enabledDayPredicate,
    required Future<void> Function(DateTime selectedDay, DateTime newFocused)
        onSelected,
    required void Function(DateTime newFocused) onFocusedChanged,
    DateTime? calendarFirstDay,
    DateTime? calendarLastDay,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: DanjiColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        var sheetFocused = _tableCalendarDay(focusedDay);
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final calendarToday = _tableCalendarDay(DateTime.now());
            final firstDay = calendarFirstDay ?? calendarToday;
            final lastDay = calendarLastDay ??
                calendarToday.add(const Duration(days: 365));
            if (sheetFocused.isBefore(firstDay)) sheetFocused = firstDay;
            if (sheetFocused.isAfter(lastDay)) sheetFocused = lastDay;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: DanjiColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(title, style: DanjiTypography.subtitleLarge),
                    const SizedBox(height: 8),
                    TableCalendar<void>(
                      firstDay: firstDay,
                      lastDay: lastDay,
                      focusedDay: sheetFocused,
                      availableGestures: AvailableGestures.all,
                      currentDay: calendarToday,
                      selectedDayPredicate: (d) =>
                          selectedDay != null &&
                          _tableCalendarDay(d) ==
                              _tableCalendarDay(selectedDay),
                      locale: 'ko_KR',
                      startingDayOfWeek: StartingDayOfWeek.sunday,
                      headerStyle: const HeaderStyle(
                        formatButtonVisible: false,
                        titleCentered: true,
                        titleTextStyle: TextStyle(
                          color: DanjiColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                        leftChevronIcon: Icon(
                          Icons.chevron_left,
                          color: DanjiColors.textPrimary,
                        ),
                        rightChevronIcon: Icon(
                          Icons.chevron_right,
                          color: DanjiColors.textPrimary,
                        ),
                      ),
                      calendarStyle: CalendarStyle(
                        outsideDaysVisible: false,
                        defaultTextStyle: const TextStyle(
                          color: DanjiColors.textPrimary,
                        ),
                        weekendTextStyle: const TextStyle(
                          color: DanjiColors.textSecondary,
                        ),
                        disabledTextStyle: TextStyle(
                          color: DanjiColors.textSecondary.withValues(
                            alpha: 0.45,
                          ),
                        ),
                        todayDecoration: const BoxDecoration(),
                        selectedDecoration: const BoxDecoration(),
                      ),
                      calendarBuilders: CalendarBuilders(
                        disabledBuilder: (context, cellDay, _) =>
                            _bookingCalendarDayCell(cellDay, isPast: true),
                        todayBuilder: (context, cellDay, _) =>
                            _bookingCalendarDayCell(cellDay),
                        selectedBuilder: (context, cellDay, _) =>
                            _bookingCalendarDayCell(cellDay),
                        defaultBuilder: (context, cellDay, _) =>
                            _bookingCalendarDayCell(cellDay),
                      ),
                      enabledDayPredicate: enabledDayPredicate,
                      onDaySelected: (pickedDay, newFocused) async {
                        if (!enabledDayPredicate(pickedDay)) return;
                        Navigator.pop(sheetContext);
                        await onSelected(pickedDay, newFocused);
                      },
                      onPageChanged: (newFocused) {
                        sheetFocused = _tableCalendarDay(newFocused);
                        onFocusedChanged(newFocused);
                        setSheetState(() {});
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _submit() async {
    final vehicle = _selected;
    final day = _startDay;
    if (vehicle == null) {
      setState(() => _error = '예약할 차량을 선택해주세요.');
      return;
    }
    if (day == null || _returnDay == null) {
      setState(() => _error = '대여·반납 일자를 선택해주세요.');
      return;
    }
    if (!_hasValidDuration) {
      setState(() => _error = '대여 기간을 올바르게 선택해주세요.');
      return;
    }

    final startTime = _rentalStartTime;
    final endTime = _rentalEndTime;
    final originalPrice = _originalPrice;
    final totalPrice = _finalPrice;
    if (startTime == null || endTime == null || originalPrice == null || totalPrice == null) {
      return;
    }

    if (_isToday(day) && !_isStartTimeInFuture(startTime)) {
      setState(() => _error = '시작 시간은 현재 시각 이후로 선택해주세요.');
      return;
    }

    if (!PaymentConfig.isConfigured) {
      setState(() => _error = '결제 키(TOSS_CLIENT_KEY)가 설정되지 않았습니다.');
      return;
    }

    if (supabase.auth.currentUser == null) {
      setState(() => _error = '로그인이 필요합니다. 다시 로그인한 뒤 결제를 시도해주세요.');
      return;
    }

    if (_pointsInputInvalid) {
      setState(() {
        _error = _pointsToUse < PointPolicy.minUseAmount
            ? '최소 5,000원 이상 사용 가능합니다'
            : '사용 가능한 포인트를 초과했습니다';
      });
      return;
    }

    if (!await ensureBookingPaymentEnabled(context, _rentalType)) {
      return;
    }

    final isZeroAmount = totalPrice <= 0;
    TossPaymentMethod? method;
    if (!isZeroAmount) {
      method = await showPaymentMethodSheet(context);
      if (method == null || !mounted) return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _reservationService.validateBookingForPayment(
        vehicleId: vehicle.id,
        startTime: startTime,
        endTime: endTime,
      );

      await _paymentService.startBookingPayment(
        context: context,
        vehicle: vehicle,
        startTime: startTime,
        endTime: endTime,
        rentalType: _rentalType,
        totalPrice: totalPrice,
        originalPrice: originalPrice,
        userCouponId: _selectedUserCouponId,
        pointsUsed: _pointsDiscount,
        method: method ?? TossPaymentMethod.card,
      );
    } catch (e) {
      if (!mounted) return;
      if (e is ReservationOverlapException) {
        setState(() => _selected = null);
        _refreshAvailability();
      } else if (e is ReservationPermissionException) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      } else {
        final message = friendlyPaymentError(e);
        if (message.contains('이미 예약')) {
          setState(() {
            _selected = null;
            _error = null;
          });
          _refreshAvailability();
          return;
        }
        setState(() => _error = message);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatWon(int amount) => NumberFormat('#,###').format(amount);

  String? get _startDateLabel {
    final day = _startDay;
    if (day == null) return null;
    return _dateLabelFormat.format(day);
  }

  String? get _returnDateLabel {
    final day = _returnDay;
    if (day == null) return null;
    return _dateLabelFormat.format(day);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: DanjiAppBar(title: '차량 예약'),
      body: FutureBuilder<VehicleQueryResult>(
        future: _vehiclesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                '차량 목록 오류: ${snapshot.error}',
                style: const TextStyle(color: DanjiColors.accentRed),
              ),
            );
          }

          final result = snapshot.data ?? _lastResult;
          final vehicles = result?.vehicles ?? _allVehicles;

          if (vehicles.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  result?.emptyMessage ??
                      '등록된 차량이 없습니다.\n입주민 인증·승인·Supabase 차량 데이터를 확인해주세요.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: DanjiColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ),
            );
          }

          return Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  color: DanjiColors.buttonBlue,
                  onRefresh: () async {
                    final refreshed = _loadVehicles();
                    setState(() {
                      _vehiclesFuture = refreshed;
                    });
                    await refreshed;
                  },
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    children: [
                      _BookingStepIndicator(activeStep: _activeStep),
                      const SizedBox(height: 20),
                      if (_selected?.isRentalService == true) ...[
                        const _BookingRentalDeliveryNotice(),
                        const SizedBox(height: 12),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: _DateSelectCard(
                              title: '대여 시작',
                              label: _startDateLabel ?? '날짜를 선택해주세요',
                              onTap: _openStartDayPicker,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _DateSelectCard(
                              title: '반납 일자',
                              label: _returnDateLabel ?? '날짜를 선택해주세요',
                              onTap: _openReturnDayPicker,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _TimeSelectCard(
                        title: _isSameDayBooking
                            ? '대여 시각'
                            : '출고 · 반납 시각',
                        time: _combinedTimeRangeLabel,
                        subtitle: _hasValidHourlyDuration && _isSameDayBooking
                            ? '${_durationLabel} · 10분 단위'
                            : '10분 단위 · 탭하여 선택',
                        subtitleHighlight:
                            _hasValidHourlyDuration && _isSameDayBooking,
                        onTap: _openBookingTimeDrumPicker,
                      ),
                      if (_periodSummaryLine != null) ...[
                        const SizedBox(height: 12),
                        _BookingPeriodSummaryBanner(text: _periodSummaryLine!),
                      ],
                      if (_selected != null && _originalPrice != null) ...[
                        if (_monthlyCapApplied) ...[
                          const SizedBox(height: 12),
                          const _BookingMonthlyCapBanner(),
                        ] else if (_compareStrikethroughPrice != null) ...[
                          const SizedBox(height: 12),
                          _BookingRentalDiscountBanner(
                            rentalType: _rentalType,
                            comparePrice: _compareStrikethroughPrice!,
                            finalPrice: _originalPrice!,
                            formatWon: _formatWon,
                          ),
                        ],
                      ],
                      const SizedBox(height: 24),
                      Text(
                        '이 시간에 예약 가능한 차량',
                        style: const TextStyle(
                          color: DanjiColors.textSecondary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FutureBuilder<List<_BookingVehicleListEntry>>(
                        future: _vehicleListFuture,
                        builder: (context, availSnapshot) {
                          if (availSnapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 32),
                              child: Center(
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }

                          final entries = availSnapshot.data ?? [];
                          if (entries.isEmpty) {
                            if (!_hasValidDuration) {
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 24),
                                child: Text(
                                  _isSameDayBooking
                                      ? '종료 시간을 시작 시간보다 1시간 이상 뒤로 설정해주세요.'
                                      : '반납 일자를 시작일 이후로 선택해주세요.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: DanjiColors.textSecondary,
                                    height: 1.5,
                                  ),
                                ),
                              );
                            }
                            return const _BookingVehiclePoolEmpty(
                              kind: _BookingVehiclePoolEmptyKind.noTypeVehicles,
                            );
                          }

                          final allBlocked =
                              entries.every((entry) => entry.isBlocked);

                          return Column(
                            children: [
                              for (final entry in entries)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _BookingVehicleCard(
                                    vehicle: entry.vehicle,
                                    blockReason: entry.blockReason,
                                    selected: !entry.isBlocked &&
                                        _selected?.id == entry.vehicle.id,
                                    rentalType: _rentalType,
                                    durationHours: _resolvedPeriod?.hours ?? 0,
                                    durationDays: _durationDays,
                                    durationMonths: _durationMonths,
                                    periodStart: _rentalStartTime,
                                    periodEnd: _rentalEndTime,
                                    onTap: entry.isBlocked
                                        ? null
                                        : () =>
                                            _selectVehicle(entry.vehicle),
                                  ),
                                ),
                              if (allBlocked) ...[
                                const SizedBox(height: 8),
                                const _BookingVehiclePoolEmpty(
                                  kind:
                                      _BookingVehiclePoolEmptyKind.allBlocked,
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          style: const TextStyle(color: DanjiColors.accentRed),
                        ),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
              if (_showCheckoutDiscounts)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_dailyOveragePriceLabel != null) ...[
                        _BookingDailyOveragePriceBanner(
                          label: _dailyOveragePriceLabel!,
                        ),
                        const SizedBox(height: 8),
                      ],
                      _BookingCheckoutDiscounts(
                    loading: _loadingCheckoutExtras,
                    coupons: _availableCoupons,
                    selectedUserCouponId: _selectedUserCouponId,
                    originalPrice: _originalPrice ?? 0,
                    couponDiscount: _couponDiscount,
                    pointBalance: _pointBalance,
                    usePoints: _usePoints,
                    pointsToUse: _pointsToUse,
                    maxPointsUsable: _maxPointsUsable,
                    pointsDiscount: _pointsDiscount,
                    onCouponSelected: _onCouponSelected,
                    onPointsToggle: _onPointsToggle,
                    onPointsAmountChanged: _onPointsAmountChanged,
                    formatWon: _formatWon,
                    extrasLoaded: _checkoutExtrasLoaded,
                      ),
                    ],
                  ),
                ),
              _BookingBottomBar(
                vehicleName: _selected?.name,
                durationLabel: _hasValidDuration ? _durationSummary : null,
                originalPrice: _originalPrice,
                couponDiscount: _couponDiscount,
                pointsDiscount: _pointsDiscount,
                finalPrice: _finalPrice,
                loading: _loading,
                canSubmit: _canSubmit,
                onSubmit: _submit,
                formatWon: _formatWon,
                submitLabel: '예약하기',
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BookingStepIndicator extends StatelessWidget {
  final int activeStep;

  const _BookingStepIndicator({required this.activeStep});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StepDot(
            step: 1,
            label: '기간선택',
            state: _stepState(1),
          ),
        ),
        _StepConnector(filled: activeStep > 1),
        Expanded(
          child: _StepDot(
            step: 2,
            label: '차량선택',
            state: _stepState(2),
          ),
        ),
        _StepConnector(filled: activeStep > 2),
        Expanded(
          child: _StepDot(
            step: 3,
            label: '확인/결제',
            state: _stepState(3),
          ),
        ),
      ],
    );
  }

  _StepVisualState _stepState(int step) {
    if (step < activeStep) return _StepVisualState.completed;
    if (step == activeStep) return _StepVisualState.active;
    return _StepVisualState.upcoming;
  }
}

enum _StepVisualState { active, completed, upcoming }

class _StepDot extends StatelessWidget {
  final int step;
  final String label;
  final _StepVisualState state;

  const _StepDot({
    required this.step,
    required this.label,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final active = state == _StepVisualState.active;
    final completed = state == _StepVisualState.completed;
    final color = active || completed
        ? DanjiColors.buttonBlue
        : DanjiColors.textSecondary;

    return Column(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active || completed
                ? DanjiColors.buttonBlue
                : DanjiColors.border,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$step',
            style: TextStyle(
              color: active || completed ? Colors.white : DanjiColors.textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: color,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _StepConnector extends StatelessWidget {
  final bool filled;

  const _StepConnector({required this.filled});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: SizedBox(
        width: 24,
        child: Divider(
          height: 2,
          thickness: 2,
          color: filled ? DanjiColors.buttonBlue : DanjiColors.border,
        ),
      ),
    );
  }
}

class _BookingDailyOveragePriceBanner extends StatelessWidget {
  final String label;

  const _BookingDailyOveragePriceBanner({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: DanjiColors.skyLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DanjiColors.buttonBlue.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.receipt_long_outlined,
            size: 18,
            color: DanjiColors.buttonBlue,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: DanjiColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BookingPeriodSummaryBanner extends StatelessWidget {
  final String text;

  const _BookingPeriodSummaryBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: DanjiColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DanjiColors.border),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: DanjiColors.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          height: 1.45,
        ),
      ),
    );
  }
}

class _DateSelectCard extends StatelessWidget {
  final String title;
  final String label;
  final VoidCallback onTap;

  const _DateSelectCard({
    required this.title,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DanjiColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: DanjiColors.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: DanjiColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: const TextStyle(
                          color: DanjiColors.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: DanjiColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeSelectCard extends StatelessWidget {
  final String title;
  final String time;
  final String subtitle;
  final bool subtitleHighlight;
  final VoidCallback onTap;

  const _TimeSelectCard({
    required this.title,
    required this.time,
    required this.subtitle,
    this.subtitleHighlight = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DanjiColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: DanjiColors.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: DanjiColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  time,
                  style: const TextStyle(
                    color: DanjiColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: subtitleHighlight
                        ? DanjiColors.buttonBlue
                        : DanjiColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

abstract final class _BookingCardColors {
  static const brandBlue = Color(0xFF3182F6);
  static const imageBackground = Color(0xFFF0F4FF);
  static const electricBadgeBg = Color(0xFFE6F1FB);
  static const electricBadgeText = Color(0xFF185FA5);
  static const typeBadgeBg = Color(0xFFF1EFE8);
  static const typeBadgeText = Color(0xFF5F5E5A);
  static const priceBlue = Color(0xFF3182F6);
  static const totalBlack = Color(0xFF191919);
}

bool _isElectricVehicleType(String vehicleType) {
  final t = vehicleType.toLowerCase();
  return t.contains('전기') ||
      t.contains('ev') ||
      t.contains('electric');
}

class _BookingVehicleListEntry {
  final Vehicle vehicle;
  final VehicleBookingBlockReason? blockReason;

  const _BookingVehicleListEntry({
    required this.vehicle,
    this.blockReason,
  });

  bool get isBlocked => blockReason != null;
}

class _BookingRentalDeliveryNotice extends StatelessWidget {
  const _BookingRentalDeliveryNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD6E8FF)),
      ),
      child: const Text(
        '예약하신 단지로 차량을 준비해 드립니다',
        style: TextStyle(
          color: DanjiColors.buttonBlue,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
      ),
    );
  }
}

class _BookingMonthlyCapBanner extends StatelessWidget {
  const _BookingMonthlyCapBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD6E8FF)),
      ),
      child: const Text(
        '일 요금 합산이 월 요금을 초과해 월 요금이 적용됐어요',
        style: TextStyle(
          color: DanjiColors.textSecondary,
          fontSize: 13,
          height: 1.35,
        ),
      ),
    );
  }
}

class _BookingRentalDiscountBanner extends StatelessWidget {
  final RentalType rentalType;
  final int comparePrice;
  final int finalPrice;
  final String Function(int) formatWon;

  const _BookingRentalDiscountBanner({
    required this.rentalType,
    required this.comparePrice,
    required this.finalPrice,
    required this.formatWon,
  });

  @override
  Widget build(BuildContext context) {
    final badgeLabel = rentalType == RentalType.daily
        ? '일 요금 할인'
        : '월 요금 할인';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD6E8FF)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: DanjiColors.buttonBlue,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              badgeLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 13, height: 1.35),
                children: [
                  TextSpan(
                    text: '₩${formatWon(comparePrice)}',
                    style: const TextStyle(
                      color: DanjiColors.textMuted,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                  const TextSpan(text: '  '),
                  TextSpan(
                    text: '₩${formatWon(finalPrice)}',
                    style: const TextStyle(
                      color: DanjiColors.buttonBlue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BookingVehicleCardPriceLines extends StatelessWidget {
  final BookingVehiclePriceLines? priceLines;
  final String unitPriceLabel;
  final RentalType periodType;
  final Color priceColor;
  final Color mutedColor;
  final Color savingsColor;
  final NumberFormat won;

  const _BookingVehicleCardPriceLines({
    required this.priceLines,
    required this.unitPriceLabel,
    required this.periodType,
    required this.priceColor,
    required this.mutedColor,
    required this.savingsColor,
    required this.won,
  });

  TextStyle _priceStyle(Color color, {double size = 13}) => TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w500,
        color: color,
        height: 1.3,
      );

  /// 금액+단위를 한 덩어리로 표시 (₩750,000/월 중간 줄바꿈 방지)
  Widget _amountWithSuffix({
    required int amount,
    required String suffix,
    required Color color,
    double fontSize = 13,
  }) {
    return Text.rich(
      TextSpan(
        style: _priceStyle(color, size: fontSize),
        children: [
          TextSpan(text: '₩${won.format(amount)}'),
          if (suffix.isNotEmpty) TextSpan(text: '\u2060$suffix'),
        ],
      ),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.fade,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lines = priceLines;

    if (lines == null || !lines.showDailyCompare) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lines != null)
            _amountWithSuffix(
              amount: lines.appliedAmount,
              suffix: lines.appliedAmountSuffix(),
              color: priceColor,
            )
          else
            Text(
              unitPriceLabel,
              style: _priceStyle(priceColor),
            ),
          if (lines?.showMonthlyOnlyLabel == true) ...[
            const SizedBox(height: 4),
            Text(
              '월 단위 전용 차량',
              style: _priceStyle(mutedColor, size: 12),
            ),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '일 단가 ₩${won.format(lines.dailyCompareAmount)}',
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.fade,
          style: _priceStyle(mutedColor, size: 12).copyWith(
            decoration: TextDecoration.lineThrough,
          ),
        ),
        const SizedBox(height: 3),
        _amountWithSuffix(
          amount: lines.appliedAmount,
          suffix: lines.appliedAmountSuffix(),
          color: priceColor,
          fontSize: 12,
        ),
        if (lines.showSavings) ...[
          const SizedBox(height: 4),
          Text(
            '일 단가 대비 ₩${won.format(lines.savings!)} 절약',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: savingsColor,
              height: 1.3,
            ),
          ),
        ],
      ],
    );
  }
}

class _BookingVehicleCard extends StatelessWidget {
  static const _disabledBg = Color(0xFFF8F8F8);
  static const _disabledText = Color(0xFFAAAAAA);
  static const _disabledPrice = Color(0xFFCCCCCC);
  static const _disabledHint = Color(0xFFF04452);

  final Vehicle vehicle;
  final VehicleBookingBlockReason? blockReason;
  final bool selected;
  final RentalType rentalType;
  final int durationHours;
  final int durationDays;
  final int durationMonths;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final VoidCallback? onTap;

  const _BookingVehicleCard({
    required this.vehicle,
    this.blockReason,
    required this.selected,
    required this.rentalType,
    required this.durationHours,
    required this.durationDays,
    required this.durationMonths,
    this.periodStart,
    this.periodEnd,
    this.onTap,
  });

  bool get _isBlocked => blockReason != null;

  String? get _blockHint {
    switch (blockReason) {
      case VehicleBookingBlockReason.inUse:
        return '대여중인 차량입니다';
      case VehicleBookingBlockReason.underMaintenance:
        return '점검 중인 차량입니다';
      case VehicleBookingBlockReason.unpublished:
        return '현재 예약을 받지 않는 차량입니다';
      case VehicleBookingBlockReason.insuranceExpired:
        return '보험이 만료된 차량입니다';
      case VehicleBookingBlockReason.timeOverlap:
        return '이 시간에 예약된 차량입니다';
      case null:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final priceLines = periodStart != null && periodEnd != null
        ? buildBookingVehiclePriceLines(
            vehicle,
            rentalType,
            start: periodStart!,
            end: periodEnd!,
          )
        : null;
    final isElectric = _isElectricVehicleType(vehicle.vehicleType);
    final unitPriceLabel =
        RentalPricing.displayUnitPriceLabel(vehicle, rentalType);
    final won = NumberFormat('#,###');
    final plate = vehicle.carNumber?.trim();
    final nameColor =
        _isBlocked ? _disabledText : DanjiColors.textPrimary;
    final plateColor =
        _isBlocked ? _disabledText : Colors.grey.shade600;
    final priceColor =
        _isBlocked ? _disabledPrice : _BookingCardColors.priceBlue;

    final card = Material(
      color: _isBlocked ? _disabledBg : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _isBlocked ? _disabledBg : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? _BookingCardColors.brandBlue
                  : Colors.grey.shade200,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _BookingCarThumbnail(
                      url: vehicle.carImageUrl,
                      muted: _isBlocked,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                vehicle.name,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: nameColor,
                                  height: 1.25,
                                ),
                              ),
                              if (vehicle.isUnderMaintenance)
                                _BookingVehicleBadge(
                                  label: '차량 점검중',
                                  background: _isBlocked
                                      ? const Color(0xFFEEEEEE)
                                      : const Color(0xFFFFF3E8),
                                  textColor: _isBlocked
                                      ? _disabledText
                                      : const Color(0xFFF97316),
                                ),
                              _BookingVehicleBadge(
                                label: vehicle.isRentalService ? '배달' : '단지 픽업',
                                background: _isBlocked
                                    ? const Color(0xFFEEEEEE)
                                    : (vehicle.isRentalService
                                        ? const Color(0xFFE8F1FF)
                                        : const Color(0xFFF3F3F3)),
                                textColor: _isBlocked
                                    ? _disabledText
                                    : (vehicle.isRentalService
                                        ? DanjiColors.buttonBlue
                                        : const Color(0xFF888888)),
                              ),
                              if (isElectric && vehicle.vehicleType.trim().isEmpty)
                                _BookingVehicleBadge(
                                  label: '전기',
                                  background: _isBlocked
                                      ? const Color(0xFFEEEEEE)
                                      : _BookingCardColors.electricBadgeBg,
                                  textColor: _isBlocked
                                      ? _disabledText
                                      : _BookingCardColors.electricBadgeText,
                                ),
                              if (vehicle.vehicleType.isNotEmpty)
                                _BookingVehicleBadge(
                                  label: vehicle.vehicleType,
                                  background: _isBlocked
                                      ? const Color(0xFFEEEEEE)
                                      : _BookingCardColors.typeBadgeBg,
                                  textColor: _isBlocked
                                      ? _disabledText
                                      : _BookingCardColors.typeBadgeText,
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            plate != null && plate.isNotEmpty
                                ? plate
                                : '번호 미등록',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: plateColor,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 6),
                          _BookingVehicleCardPriceLines(
                            priceLines: priceLines,
                            unitPriceLabel: unitPriceLabel,
                            periodType: rentalType,
                            priceColor: priceColor,
                            mutedColor: _isBlocked
                                ? _disabledPrice
                                : DanjiColors.textMuted,
                            savingsColor: _isBlocked
                                ? _disabledText
                                : DanjiColors.buttonBlue,
                            won: won,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (_isBlocked)
                      const _BookingVehicleLockIndicator()
                    else
                      _BookingSelectionIndicator(selected: selected),
                  ],
                ),
                if (_blockHint != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _blockHint!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: _disabledHint,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    if (!_isBlocked) return card;
    return Opacity(opacity: 0.7, child: card);
  }
}

class _BookingVehicleLockIndicator extends StatelessWidget {
  const _BookingVehicleLockIndicator();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: const Color(0xFFEEEEEE),
        borderRadius: BorderRadius.circular(11),
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.lock_outline,
        size: 12,
        color: Color(0xFFBBBBBB),
      ),
    );
  }
}

class _BookingCarThumbnail extends StatelessWidget {
  final String? url;
  final bool muted;

  const _BookingCarThumbnail({this.url, this.muted = false});

  bool get _hasUrl {
    final u = url?.trim();
    return u != null && u.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 80,
        height: 52,
        color: _BookingCardColors.imageBackground,
        alignment: Alignment.center,
        child: _hasUrl
            ? Image.network(
                url!.trim(),
                width: 80,
                height: 52,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.directions_car,
                  color: muted
                      ? const Color(0xFFAAAAAA)
                      : _BookingCardColors.brandBlue,
                  size: 28,
                ),
              )
            : Icon(
                Icons.directions_car,
                color: muted
                    ? const Color(0xFFAAAAAA)
                    : _BookingCardColors.brandBlue,
                size: 28,
              ),
      ),
    );
  }
}

class _BookingVehicleBadge extends StatelessWidget {
  final String label;
  final Color background;
  final Color textColor;

  const _BookingVehicleBadge({
    required this.label,
    required this.background,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textColor,
          height: 1.2,
        ),
      ),
    );
  }
}

class _BookingSelectionIndicator extends StatelessWidget {
  final bool selected;

  const _BookingSelectionIndicator({required this.selected});

  @override
  Widget build(BuildContext context) {
    if (selected) {
      return Container(
        width: 22,
        height: 22,
        decoration: const BoxDecoration(
          color: _BookingCardColors.brandBlue,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.check,
          size: 14,
          color: Colors.white,
        ),
      );
    }

    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.grey.shade300, width: 1.5),
      ),
    );
  }
}

enum _BookingVehiclePoolEmptyKind { noTypeVehicles, allBlocked }

class _BookingVehiclePoolEmpty extends StatelessWidget {
  final _BookingVehiclePoolEmptyKind kind;

  const _BookingVehiclePoolEmpty({required this.kind});

  static const _brandBlue = Color(0xFF3182F6);

  @override
  Widget build(BuildContext context) {
    final isNoType = kind == _BookingVehiclePoolEmptyKind.noTypeVehicles;
    final title = isNoType
        ? '이 기간 대여 가능한 차량이 아직 없습니다'
        : '선택하신 기간에는 예약 가능한 차량이 없습니다';
    final subtitle = isNoType
        ? '다른 기간을 선택하시거나 전화로 문의해 주세요.'
        : '다른 일정을 선택하시거나 전화로 문의해 주세요.';

    return Padding(
      padding: EdgeInsets.symmetric(vertical: isNoType ? 40 : 16),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isNoType)
              const Icon(
                Icons.directions_car_outlined,
                size: 48,
                color: _brandBlue,
              ),
            if (isNoType) const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Color(0xFF333333),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF888888),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: () => launchRentalInquiryPhone(context),
                style: FilledButton.styleFrom(
                  backgroundColor: _brandBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('전화 문의하기'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookingCheckoutDiscounts extends StatefulWidget {
  final bool loading;
  final bool extrasLoaded;
  final List<UserCoupon> coupons;
  final String? selectedUserCouponId;
  final int originalPrice;
  final int couponDiscount;
  final int pointBalance;
  final bool usePoints;
  final int pointsToUse;
  final int maxPointsUsable;
  final int pointsDiscount;
  final ValueChanged<String?> onCouponSelected;
  final ValueChanged<bool> onPointsToggle;
  final ValueChanged<String> onPointsAmountChanged;
  final String Function(int) formatWon;

  const _BookingCheckoutDiscounts({
    required this.loading,
    required this.extrasLoaded,
    required this.coupons,
    required this.selectedUserCouponId,
    required this.originalPrice,
    required this.couponDiscount,
    required this.pointBalance,
    required this.usePoints,
    required this.pointsToUse,
    required this.maxPointsUsable,
    required this.pointsDiscount,
    required this.onCouponSelected,
    required this.onPointsToggle,
    required this.onPointsAmountChanged,
    required this.formatWon,
  });

  @override
  State<_BookingCheckoutDiscounts> createState() =>
      _BookingCheckoutDiscountsState();
}

class _BookingCheckoutDiscountsState extends State<_BookingCheckoutDiscounts> {
  final _pointsController = TextEditingController();

  int? _parsePointsField() =>
      int.tryParse(_pointsController.text.replaceAll(RegExp(r'[^0-9]'), ''));

  @override
  void didUpdateWidget(covariant _BookingCheckoutDiscounts oldWidget) {
    super.didUpdateWidget(oldWidget);
    final parsed = _parsePointsField();
    if (widget.pointsToUse == parsed) return;

    final toggleOn = !oldWidget.usePoints && widget.usePoints;
    final toggleOff = oldWidget.usePoints && !widget.usePoints;
    final couponClamped = oldWidget.maxPointsUsable != widget.maxPointsUsable &&
        widget.pointsToUse <= widget.maxPointsUsable &&
        (parsed ?? 0) > widget.pointsToUse;

    if (toggleOn || toggleOff || couponClamped) {
      _pointsController.text =
          widget.pointsToUse > 0 ? '${widget.pointsToUse}' : '';
    }
  }

  @override
  void dispose() {
    _pointsController.dispose();
    super.dispose();
  }

  String? get _safeCouponDropdownValue {
    final selected = widget.selectedUserCouponId;
    if (selected == null) return null;
    for (final c in widget.coupons) {
      if (c.id == selected &&
          c.canApplyToOrderAmount(widget.originalPrice)) {
        return selected;
      }
    }
    return null;
  }

  /// 쿠폰 할인 후 잔여 결제금액이 0원인 경우 (포인트 사용 불가)
  bool get _isFullyDiscountedByCoupon =>
      widget.originalPrice > 0 &&
      widget.couponDiscount > 0 &&
      widget.originalPrice - widget.couponDiscount <= 0;

  static const _pointsHintStyle = TextStyle(
    fontSize: 12,
    color: DanjiColors.success,
    height: 1.45,
  );

  static const _pointsWarnStyle = TextStyle(
    fontSize: 12,
    color: DanjiColors.accentRed,
    fontWeight: FontWeight.w600,
    height: 1.45,
  );

  bool get _balanceBelowMinUse =>
      !PointPolicy.canUsePoints(widget.pointBalance);

  bool get _pointsAmountBelowMin =>
      widget.usePoints &&
      widget.pointsToUse < PointPolicy.minUseAmount;

  bool get _pointsAmountAboveMax =>
      widget.usePoints &&
      widget.maxPointsUsable > 0 &&
      widget.pointsToUse > widget.maxPointsUsable;

  String? get _pointsErrorText {
    if (_pointsAmountBelowMin) {
      return '최소 5,000원 이상 사용 가능합니다';
    }
    if (_pointsAmountAboveMax) {
      return '사용 가능한 포인트를 초과했습니다';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          '확인 / 결제',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: DanjiColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '쿠폰 또는 포인트 사용 시 포인트가 적립되지 않습니다.',
          style: TextStyle(
            fontSize: 12,
            color: DanjiColors.textSecondary,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 12),
        _checkoutCard(
          title: '쿠폰 선택',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.loading && !widget.extrasLoaded)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else ...[
              DropdownButtonFormField<String?>(
                key: ValueKey('coupon-${widget.coupons.length}-$_safeCouponDropdownValue'),
                initialValue: _safeCouponDropdownValue,
                decoration: InputDecoration(
                  labelText: '쿠폰',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('쿠폰 사용 안 함'),
                  ),
                  for (final c in widget.coupons)
                    DropdownMenuItem<String?>(
                      value: c.id,
                      enabled: c.canApplyToOrderAmount(widget.originalPrice),
                      child: Text(
                        c.displayTitle,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: widget.onCouponSelected,
              ),
              ],
              if (widget.couponDiscount > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '-₩${widget.formatWon(widget.couponDiscount)}',
                  style: const TextStyle(
                    color: DanjiColors.accentRed,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              for (final c in widget.coupons)
                if (!c.canApplyToOrderAmount(widget.originalPrice) &&
                    c.minPaymentAmount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${c.displayTitle}: '
                      '₩${widget.formatWon(c.minPaymentAmount)} 이상 결제 시 사용 가능',
                      style: const TextStyle(
                        fontSize: 12,
                        color: DanjiColors.textSecondary,
                      ),
                    ),
                  ),
              if (widget.coupons.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    '사용 가능한 쿠폰이 없습니다.',
                    style: TextStyle(
                      fontSize: 12,
                      color: DanjiColors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _checkoutCard(
          title: '포인트 사용',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.loading && !widget.extrasLoaded)
                const SizedBox.shrink()
              else ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '보유 ${widget.formatWon(widget.pointBalance)}P',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: DanjiColors.textPrimary,
                      ),
                    ),
                  ),
                  Switch(
                    value: widget.usePoints,
                    onChanged: !_balanceBelowMinUse &&
                            widget.maxPointsUsable > 0
                        ? widget.onPointsToggle
                        : null,
                  ),
                ],
              ),
              if (_balanceBelowMinUse) ...[
                Text(
                  '5,000P 이상부터 사용 가능합니다. '
                  '(보유 ${widget.formatWon(widget.pointBalance)}P)',
                  style: const TextStyle(
                    fontSize: 12,
                    color: DanjiColors.textSecondary,
                    height: 1.45,
                  ),
                ),
              ] else if (widget.maxPointsUsable > 0) ...[
                TextField(
                  controller: _pointsController,
                  keyboardType: TextInputType.number,
                  enabled: widget.usePoints,
                  decoration: InputDecoration(
                    labelText:
                        '사용 포인트 (최소 ${widget.formatWon(PointPolicy.minUseAmount)}P · '
                        '최대 ${widget.maxPointsUsable}P)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    errorText: _pointsErrorText,
                  ),
                  onChanged: widget.onPointsAmountChanged,
                ),
              ] else if (_isFullyDiscountedByCoupon) ...[
                const Text(
                  '쿠폰으로 전액 할인되었습니다 🎉',
                  style: _pointsHintStyle,
                ),
                const SizedBox(height: 4),
                const Text(
                  '포인트는 잔여 결제금액이 있을 때 사용 가능합니다.',
                  style: _pointsHintStyle,
                ),
              ] else
                const Text(
                  '포인트를 사용할 수 없습니다.',
                  style: TextStyle(
                    fontSize: 12,
                    color: DanjiColors.textSecondary,
                  ),
                ),
              if (widget.pointsDiscount > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '-${widget.formatWon(widget.pointsDiscount)}P',
                  style: const TextStyle(
                    color: DanjiColors.accentRed,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _checkoutCard({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DanjiColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: DanjiColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _BookingBottomBar extends StatelessWidget {
  final String? vehicleName;
  final String? durationLabel;
  final int? originalPrice;
  final int couponDiscount;
  final int pointsDiscount;
  final int? finalPrice;
  final bool loading;
  final bool canSubmit;
  final VoidCallback onSubmit;
  final String Function(int) formatWon;
  final String submitLabel;

  const _BookingBottomBar({
    required this.vehicleName,
    required this.durationLabel,
    required this.originalPrice,
    required this.couponDiscount,
    required this.pointsDiscount,
    required this.finalPrice,
    required this.loading,
    required this.canSubmit,
    required this.onSubmit,
    required this.formatWon,
    this.submitLabel = '예약하기',
  });

  @override
  Widget build(BuildContext context) {
    final hasSelection = vehicleName != null && finalPrice != null;
    final summaryLine = hasSelection
        ? '$vehicleName · ${durationLabel ?? ''}'
        : '차량과 기간을 선택해주세요';
    final hasDiscount = couponDiscount > 0 || pointsDiscount > 0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      summaryLine,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
              if (hasSelection && hasDiscount) ...[
                const SizedBox(height: 8),
                if (originalPrice != null)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '주문 금액',
                        style: TextStyle(
                          fontSize: 12,
                          color: DanjiColors.textSecondary,
                        ),
                      ),
                      Text(
                        '₩${formatWon(originalPrice!)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: DanjiColors.textSecondary,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ],
                  ),
                if (couponDiscount > 0)
                  _discountRow('쿠폰', '-₩${formatWon(couponDiscount)}'),
                if (pointsDiscount > 0)
                  _discountRow('포인트', '-${formatWon(pointsDiscount)}P'),
              ],
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '결제 금액',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: DanjiColors.textPrimary,
                    ),
                  ),
                  Text(
                    hasSelection ? '₩${formatWon(finalPrice!)}' : '—',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: hasSelection
                          ? _BookingCardColors.totalBlack
                          : Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                width: double.infinity,
                child: FilledButton(
                  onPressed: canSubmit && !loading ? onSubmit : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: canSubmit
                        ? _BookingCardColors.brandBlue
                        : Colors.grey.shade300,
                    disabledBackgroundColor: Colors.grey.shade300,
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          submitLabel,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _discountRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: DanjiColors.textSecondary,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: DanjiColors.accentRed,
            ),
          ),
        ],
      ),
    );
  }
}

/// 예약 기간 달력 — 시작/종료 진한 원, 중간 옅은 하늘색, 오늘 옅은 원
class _BookingRangeDayCell extends StatelessWidget {
  final DateTime day;
  final bool isToday;
  final bool isRangeStart;
  final bool isRangeEnd;
  final bool isInRange;
  final bool isPast;

  const _BookingRangeDayCell({
    required this.day,
    required this.isToday,
    required this.isRangeStart,
    required this.isRangeEnd,
    required this.isInRange,
    this.isPast = false,
  });

  static const _circleSize = 36.0;

  @override
  Widget build(BuildContext context) {
    final singleDay = isRangeStart && isRangeEnd;
    final showRangeBar = isInRange && !singleDay;
    final isMiddle = showRangeBar && !isRangeStart && !isRangeEnd;

    var textColor = _bookingCalendarDayTextColor(day, isPast: isPast);
    var fontWeight = FontWeight.w500;

    if (isPast) {
      fontWeight = FontWeight.w400;
    } else if (isRangeStart || isRangeEnd) {
      textColor = Colors.white;
      fontWeight = FontWeight.w700;
    } else if (isToday && !isInRange) {
      fontWeight = FontWeight.w800;
    } else if (isMiddle) {
      fontWeight = FontWeight.w600;
    }

    return SizedBox(
      width: double.infinity,
      height: _circleSize,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (isMiddle)
            Positioned.fill(
              child: Container(color: DanjiColors.skyLight),
            ),
          if (showRangeBar && !isMiddle)
            Positioned.fill(
              child: Align(
                alignment: Alignment.center,
                child: Container(
                  height: _circleSize,
                  decoration: BoxDecoration(
                    color: DanjiColors.skyLight,
                    borderRadius: BorderRadius.horizontal(
                      left: isRangeStart
                          ? const Radius.circular(_circleSize / 2)
                          : Radius.zero,
                      right: isRangeEnd
                          ? const Radius.circular(_circleSize / 2)
                          : Radius.zero,
                    ),
                  ),
                ),
              ),
            ),
          if (!isPast && isToday && !isInRange)
            Container(
              width: _circleSize,
              height: _circleSize,
              decoration: const BoxDecoration(
                color: DanjiColors.skyLight,
                shape: BoxShape.circle,
              ),
            ),
          if (!isPast && (isRangeStart || isRangeEnd))
            Container(
              width: _circleSize,
              height: _circleSize,
              decoration: const BoxDecoration(
                color: DanjiColors.buttonBlue,
                shape: BoxShape.circle,
              ),
            ),
          Text(
            '${day.day}',
            style: TextStyle(
              color: textColor,
              fontWeight: fontWeight,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
