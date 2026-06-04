import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../config/payment_config.dart';
import '../models/coupon.dart';
import '../models/vehicle.dart';
import '../models/vehicle_query_result.dart';
import '../services/coupon_service.dart';
import '../services/payment_service.dart';
import '../services/point_service.dart';
import '../utils/point_policy.dart';
import '../services/reservation_service.dart';
import '../services/vehicle_service.dart';
import '../supabase_client.dart';
import '../theme/danji_colors.dart';
import '../theme/danji_typography.dart';
import '../utils/rental_inquiry_flow.dart';
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
  static const _minHour = 0;
  static const _maxHour = 23;

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

  Future<VehicleQueryResult>? _vehiclesFuture;
  Future<List<_BookingVehicleListEntry>>? _vehicleListFuture;
  VehicleQueryResult? _lastResult;
  List<Vehicle> _allVehicles = [];
  Vehicle? _selected;
  late DateTime _focusedDay;
  DateTime? _selectedDay;
  int _startHour = 9;
  int _endHour = 10;
  bool _endHourManuallySet = false;
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
    _vehiclesFuture = _loadVehicles();
  }

  /// 23:00 이전 — 오늘·현재시+1h / 23:00 이후 — 내일 00:00 시작
  void _applyInitialDateTime() {
    final now = DateTime.now();
    if (now.hour >= 23) {
      final tomorrow = _todayCalendarDate.add(const Duration(days: 1));
      _selectedDay = tomorrow;
      _focusedDay = tomorrow;
      _startHour = 0;
      _endHour = 1;
    } else {
      final today = _todayCalendarDate;
      _selectedDay = today;
      _focusedDay = today;
      _startHour = (now.hour + 1).clamp(_minHour, _maxHour);
      _endHour = _startHour + 1;
    }
    _endHourManuallySet = false;
    _normalizeHoursForSelectedDay();
    if (!_endHourManuallySet) {
      _syncEndHourFromStart(force: true);
    }
  }

  DateTime get _tomorrowCalendarDate =>
      _todayCalendarDate.add(const Duration(days: 1));

  bool get _isTomorrowMidnightSlot {
    final day = _selectedDay;
    if (day == null) return false;
    return isSameDay(day, _tomorrowCalendarDate) && _startHour == 0;
  }

  void _applyTomorrowMidnightSlot() {
    _selectedDay = _tomorrowCalendarDate;
    _focusedDay = _tomorrowCalendarDate;
    _startHour = 0;
    _endHour = 1;
    _endHourManuallySet = false;
    _normalizeHoursForSelectedDay();
    if (!_endHourManuallySet) {
      _syncEndHourFromStart(force: true);
    }
  }

  DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  /// 달력·선택용 오늘 (시간 제거, 로컬 연월일)
  DateTime get _todayCalendarDate {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  DateTime _calendarDateOnly(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day);

  /// 오늘 이전 날짜만 비활성 (오늘 포함 이후는 선택 가능)
  bool _isCalendarDayBeforeToday(DateTime day) {
    return _calendarDateOnly(day).isBefore(_todayCalendarDate);
  }

  bool _isCalendarDayEnabled(DateTime day) =>
      !_isCalendarDayBeforeToday(day);

  Future<VehicleQueryResult> _loadVehicles() async {
    final result = await _vehicleService.fetchVehiclesForMyComplex();
    _lastResult = result;
    _allVehicles = result.vehicles;

    _refreshAvailability();
    return result;
  }

  int get _activeStep {
    if (_selected == null) return 1;
    if (_durationHours >= 1 && _originalPrice != null) return 3;
    return 2;
  }

  /// 3단계 확인/결제 — 차량 선택 후 쿠폰·포인트 패널 표시
  bool get _showCheckoutDiscounts =>
      _selected != null && _durationHours >= 1 && _originalPrice != null;

  int get _durationHours {
    final start = _buildStartDateTime(_selectedDay, _startHour);
    final end = _buildEndDateTime(_selectedDay, _endHour);
    if (start == null || end == null) return 0;
    return end.difference(start).inHours;
  }

  DateTime? get _rangeStartDay => _selectedDay;

  DateTime? get _rangeEndDay {
    final day = _selectedDay;
    if (day == null) return null;
    final end = _buildEndDateTime(day, _endHour);
    return end == null ? null : _dateOnly(end);
  }

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

  bool _isToday(DateTime day) => isSameDay(day, DateTime.now());

  /// 오늘이면 시작 시각(시간 단위)이 현재 시각보다 뒤인지
  bool _isStartTimeInFuture(DateTime startTime) =>
      startTime.isAfter(DateTime.now());

  bool _isStartHourSelectable(DateTime day, int hour) {
    final slot = _buildStartDateTime(day, hour);
    if (slot == null) return false;
    if (!_isToday(day)) return true;
    return _isStartTimeInFuture(slot);
  }

  List<int> get _startHourOptions {
    final options = <int>[
      for (var h = _minHour; h <= _maxHour; h++) h,
    ];
    final day = _selectedDay;
    if (day == null) return const [];
    if (!_isToday(day)) return options;

    return options.where((h) => _isStartHourSelectable(day, h)).toList();
  }

  List<int> get _endHourOptions {
    final day = _selectedDay;
    if (day == null) return const [];

    return [
      for (var h = _minHour; h <= _maxHour; h++)
        if (_isValidEndHour(day, h)) h,
    ];
  }

  bool _isValidEndHour(DateTime day, int endHour) {
    final start = _buildStartDateTime(day, _startHour);
    final end = _buildEndDateTime(day, endHour);
    if (start == null || end == null) return false;
    return end.difference(start).inHours >= 1;
  }

  /// 종료 시각 = 시작 + 1시간 (유효한 종료 시각 목록 기준)
  void _syncEndHourFromStart({bool force = false}) {
    if (!force && _endHourManuallySet) return;

    final day = _selectedDay;
    if (day == null) return;

    final start = _buildStartDateTime(day, _startHour);
    if (start == null) return;

    final targetEnd = start.add(const Duration(hours: 1));
    var candidate = targetEnd.hour;

    final ends = _endHourOptions;
    if (ends.isEmpty) return;

    if (ends.contains(candidate)) {
      _endHour = candidate;
      return;
    }

    for (final h in ends) {
      final end = _buildEndDateTime(day, h);
      if (end != null && end.difference(start).inHours == 1) {
        _endHour = h;
        return;
      }
    }

    _endHour = ends.first;
  }

  void _normalizeHoursForSelectedDay() {
    final starts = _startHourOptions;
    if (starts.isEmpty) return;

    if (!starts.contains(_startHour)) {
      _startHour = starts.first;
    }

    _syncEndHourFromStart();

    final ends = _endHourOptions;
    if (ends.isEmpty) return;
    if (!ends.contains(_endHour)) {
      _endHour = ends.first;
      _endHourManuallySet = false;
    }
  }

  DateTime? _buildStartDateTime(DateTime? day, int hour) {
    if (day == null) return null;
    return DateTime(day.year, day.month, day.day, hour);
  }

  DateTime? _buildEndDateTime(DateTime? day, int hour) {
    if (day == null) return null;
    var end = DateTime(day.year, day.month, day.day, hour);
    final start = _buildStartDateTime(day, _startHour);
    if (start != null && !end.isAfter(start)) {
      end = end.add(const Duration(days: 1));
    }
    return end;
  }

  String _formatHourLabel(int hour) =>
      '${hour.toString().padLeft(2, '0')}:00';

  String _formatEndHourLabel(int hour) {
    final day = _selectedDay;
    if (day == null) return _formatHourLabel(hour);

    final start = _buildStartDateTime(day, _startHour);
    final end = _buildEndDateTime(day, hour);
    if (start != null &&
        end != null &&
        _dateOnly(end).isAfter(_dateOnly(start))) {
      return '${_formatHourLabel(hour)} (익일)';
    }
    return _formatHourLabel(hour);
  }

  int? get _originalPrice {
    final vehicle = _selected;
    if (vehicle == null || _durationHours < 1) return null;
    return _durationHours * vehicle.pricePerHour;
  }

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
    final amount = _pointsToUse.clamp(0, _maxPointsUsable);
    if (!PointPolicy.isValidUseAmount(amount)) return 0;
    return amount;
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
    if (_durationHours < 1) return false;
    final start = _buildStartDateTime(_selectedDay, _startHour);
    if (start == null) return false;
    if (_selectedDay != null &&
        _isToday(_selectedDay!) &&
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
    if (_pointsToUse > max) _pointsToUse = max;
    if (_pointsToUse < 0) _pointsToUse = 0;
    if (max == 0) {
      _usePoints = false;
      _pointsToUse = 0;
    }
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
    setState(() {
      _pointsToUse = parsed.clamp(0, _maxPointsUsable);
      _usePoints = _pointsToUse > 0;
    });
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
    final day = _selectedDay;

    if (day == null || _durationHours < 1) {
      return [];
    }

    final startTime = _buildStartDateTime(day, _startHour);
    final endTime = _buildEndDateTime(day, _endHour);
    if (startTime == null || endTime == null) {
      return [];
    }

    if (_isToday(day) && !_isStartTimeInFuture(startTime)) {
      return [];
    }

    final residentComplexId = complexId?.trim();
    final entries = <_BookingVehicleListEntry>[];

    for (final vehicle in vehicles) {
      if (!vehicle.isAvailable) {
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
        _durationHours >= 1 &&
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

    if (entries.isEmpty && _durationHours >= 1) {
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
      _normalizeHoursForSelectedDay();
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
      _error = null;
      _validateCouponForCurrentPrice();
      _clampPointsToUse();
    });
    _scheduleCheckoutExtrasLoad();
  }

  Future<void> _openDatePicker() async {
    final day = _selectedDay;
    if (day == null) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: DanjiColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            var focused = _calendarDateOnly(_focusedDay);
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
                    Text('날짜 선택', style: DanjiTypography.subtitleLarge),
                    const SizedBox(height: 8),
                    TableCalendar<void>(
                      firstDay: _todayCalendarDate,
                      lastDay: _todayCalendarDate.add(const Duration(days: 365)),
                      focusedDay: focused,
                      currentDay: _todayCalendarDate,
                      selectedDayPredicate: (d) =>
                          _selectedDay != null && isSameDay(d, _selectedDay!),
                      locale: 'ko_KR',
                      startingDayOfWeek: StartingDayOfWeek.monday,
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
                        disabledBuilder: (context, cellDay, _) {
                          return _BookingRangeDayCell(
                            day: cellDay,
                            isToday: _isToday(cellDay),
                            isRangeStart: false,
                            isRangeEnd: false,
                            isInRange: false,
                            isPast: true,
                          );
                        },
                        defaultBuilder: (context, cellDay, _) {
                          return _BookingRangeDayCell(
                            day: cellDay,
                            isToday: _isToday(cellDay),
                            isRangeStart: _isRangeStart(cellDay),
                            isRangeEnd: _isRangeEnd(cellDay),
                            isInRange: _isInBookingRange(cellDay),
                          );
                        },
                      ),
                      enabledDayPredicate: _isCalendarDayEnabled,
                      onDaySelected: (selectedDay, newFocused) {
                        if (!_isCalendarDayEnabled(selectedDay)) return;
                        Navigator.pop(sheetContext);
                        setState(() {
                          _selectedDay = _calendarDateOnly(selectedDay);
                          _focusedDay = _calendarDateOnly(newFocused);
                        });
                        _onDateTimeChanged();
                      },
                      onPageChanged: (newFocused) {
                        final d = _calendarDateOnly(newFocused);
                        _focusedDay = d;
                        setSheetState(() => focused = d);
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

  Future<void> _openHourPicker({
    required String title,
    required List<int> hours,
    required int current,
    required String Function(int) labelBuilder,
    required ValueChanged<int> onSelected,
  }) async {
    if (hours.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('선택 가능한 시간이 없습니다.')),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: DanjiColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Text(title, style: DanjiTypography.subtitleLarge),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.45,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: hours.length,
                  itemBuilder: (context, index) {
                    final hour = hours[index];
                    final selected = hour == current;
                    return ListTile(
                      title: Text(
                        labelBuilder(hour),
                        style: TextStyle(
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected
                              ? DanjiColors.buttonBlue
                              : DanjiColors.textPrimary,
                        ),
                      ),
                      trailing: selected
                          ? const Icon(
                              Icons.check,
                              color: DanjiColors.buttonBlue,
                            )
                          : null,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        onSelected(hour);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _submit() async {
    final vehicle = _selected;
    final day = _selectedDay;
    if (vehicle == null) {
      setState(() => _error = '예약할 차량을 선택해주세요.');
      return;
    }
    if (day == null) {
      setState(() => _error = '예약 날짜를 선택해주세요.');
      return;
    }
    if (_durationHours < 1) {
      setState(() => _error = '최소 1시간 이상 선택해주세요.');
      return;
    }

    final startTime = _buildStartDateTime(day, _startHour);
    final endTime = _buildEndDateTime(day, _endHour);
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

  String? get _selectedDateLabel {
    final day = _selectedDay;
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
                      _DateSelectCard(
                        label: _selectedDateLabel ?? '날짜를 선택해주세요',
                        onTap: _openDatePicker,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _TimeSelectCard(
                              title: '시작 시간',
                              time: _formatHourLabel(_startHour),
                              subtitle: '1시간 단위',
                              onTap: () => _openHourPicker(
                                title: '시작 시간',
                                hours: _startHourOptions,
                                current: _startHour,
                                labelBuilder: _formatHourLabel,
                                onSelected: (hour) {
                                  setState(() {
                                    _startHour = hour;
                                    _syncEndHourFromStart();
                                  });
                                  _onDateTimeChanged();
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _TimeSelectCard(
                              title: '종료 시간',
                              time: _formatHourLabel(_endHour),
                              subtitle: _durationHours >= 1
                                  ? '${_durationHours}시간 선택됨'
                                  : '1시간 이상 선택',
                              subtitleHighlight: _durationHours >= 1,
                              onTap: () => _openHourPicker(
                                title: '종료 시간',
                                hours: _endHourOptions,
                                current: _endHour,
                                labelBuilder: _formatEndHourLabel,
                                onSelected: (hour) {
                                  setState(() {
                                    _endHour = hour;
                                    _endHourManuallySet = true;
                                  });
                                  _onDateTimeChanged();
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
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
                            if (_durationHours < 1) {
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 24),
                                child: Text(
                                  '종료 시간을 시작 시간보다 1시간 이상 뒤로 설정해주세요.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: DanjiColors.textSecondary,
                                    height: 1.5,
                                  ),
                                ),
                              );
                            }
                            return const _BookingNoAvailableVehiclesEmpty();
                          }

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
                                    durationHours: _durationHours,
                                    onTap: entry.isBlocked
                                        ? null
                                        : () =>
                                            _selectVehicle(entry.vehicle),
                                  ),
                                ),
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
                  child: _BookingCheckoutDiscounts(
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
                ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: _BookingLongTermRentalInquiryLink(),
              ),
              _BookingBottomBar(
                vehicleName: _selected?.name,
                durationHours: _durationHours,
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
            label: '날짜/시간',
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

class _DateSelectCard extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _DateSelectCard({required this.label, required this.onTap});

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
                      const Text(
                        '날짜',
                        style: TextStyle(
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

class _BookingVehicleCard extends StatelessWidget {
  static const _disabledBg = Color(0xFFF8F8F8);
  static const _disabledText = Color(0xFFAAAAAA);
  static const _disabledPrice = Color(0xFFCCCCCC);
  static const _disabledHint = Color(0xFFF04452);

  final Vehicle vehicle;
  final VehicleBookingBlockReason? blockReason;
  final bool selected;
  final int durationHours;
  final VoidCallback? onTap;

  const _BookingVehicleCard({
    required this.vehicle,
    this.blockReason,
    required this.selected,
    required this.durationHours,
    this.onTap,
  });

  bool get _isBlocked => blockReason != null;

  String? get _blockHint {
    switch (blockReason) {
      case VehicleBookingBlockReason.inUse:
        return '대여중인 차량입니다';
      case VehicleBookingBlockReason.timeOverlap:
        return '이 시간에 예약된 차량입니다';
      case null:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hours = durationHours < 1 ? 1 : durationHours;
    final lineTotal = hours * vehicle.pricePerHour;
    final isElectric = _isElectricVehicleType(vehicle.vehicleType);
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
                              if (isElectric)
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
                          Text(
                            '${vehicle.priceLabel} · ₩${NumberFormat('#,###').format(lineTotal)}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: priceColor,
                              height: 1.3,
                            ),
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

class _BookingNoAvailableVehiclesEmpty extends StatelessWidget {
  const _BookingNoAvailableVehiclesEmpty();

  static const _brandBlue = Color(0xFF3182F6);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.directions_car_outlined,
              size: 48,
              color: _brandBlue,
            ),
            const SizedBox(height: 16),
            const Text(
              '현재 대여 가능한 차량이 없습니다.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Color(0xFF333333),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '다른 시간대를 선택하거나 일반렌트로 문의해보세요.',
              textAlign: TextAlign.center,
              style: TextStyle(
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
                child: const Text('일반렌트 문의하기'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 24시간 이상 장기 대여 — 일반렌트 문의 전화
class _BookingLongTermRentalInquiryLink extends StatelessWidget {
  const _BookingLongTermRentalInquiryLink();

  Future<void> _showLongTermRentalDialog(BuildContext context) async {
    final call = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DanjiColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actionsAlignment: MainAxisAlignment.center,
        title: SizedBox(
          width: double.infinity,
          child: Text(
            '1일이상 대여문의',
            textAlign: TextAlign.center,
            style: DanjiTypography.subtitleLarge.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        content: SizedBox(
          width: double.infinity,
          child: Text(
            '24시간 이상은 일반렌트로 문의해주세요.',
            textAlign: TextAlign.center,
            style: DanjiTypography.bodyRegular.copyWith(
              color: DanjiColors.textSecondary,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: DanjiColors.textSecondary,
              textStyle: DanjiTypography.body.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: DanjiColors.primaryBlue,
              foregroundColor: Colors.white,
              textStyle: DanjiTypography.body.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('대여 문의'),
          ),
        ],
      ),
    );

    if (call != true || !context.mounted) return;
    await launchRentalInquiryPhone(context);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showLongTermRentalDialog(context),
      behavior: HitTestBehavior.opaque,
      child: const Text.rich(
        TextSpan(
          style: TextStyle(
            fontSize: 13,
            color: Color(0xFF888888),
            height: 1.45,
          ),
          children: [
            TextSpan(text: '24시간 이상 대여가 필요하신가요?  '),
            TextSpan(
              text: '전화 문의',
              style: TextStyle(
                color: Color(0xFF3182F6),
                decoration: TextDecoration.underline,
                decorationColor: Color(0xFF3182F6),
              ),
            ),
          ],
        ),
        textAlign: TextAlign.center,
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

  @override
  void didUpdateWidget(covariant _BookingCheckoutDiscounts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pointsToUse != int.tryParse(_pointsController.text)) {
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
      widget.pointsToUse > 0 &&
      widget.pointsToUse < PointPolicy.minUseAmount;

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
                    value: widget.usePoints &&
                        widget.maxPointsUsable > 0 &&
                        !_balanceBelowMinUse,
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
                    errorText: _pointsAmountBelowMin
                        ? '최소 ${widget.formatWon(PointPolicy.minUseAmount)}P 이상 입력해주세요.'
                        : null,
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
  final int durationHours;
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
    required this.durationHours,
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
        ? '$vehicleName · ${durationHours}시간'
        : '차량과 시간을 선택해주세요';
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
