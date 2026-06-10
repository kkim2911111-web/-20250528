import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/admin_timeline.dart';
import '../models/staff_profile.dart';
import '../models/vehicle.dart';
import '../screens/admin/admin_reservation_detail_screen.dart';
import '../screens/reservation_screen.dart';
import '../theme/danji_colors.dart';
import '../utils/phone_launcher.dart';
import '../utils/rental_pricing.dart';
import '../utils/reservation_display.dart';
import '../utils/reservation_status_badge.dart';
import '../widgets/month_filter_bar.dart';
import '../widgets/reservation_times_panel.dart';

enum _TimelineDisplayMode { month, day }

class AdminReservationTimelineLayout {
  static const dayColumnWidth = 48.0;
  static const hourColumnWidth = 56.0;
  static const vehicleLabelWidth = 116.0;
  static const rowHeight = 56.0;
  static const headerHeight = 40.0;
  static const minMonthBarWidth = 12.0;
  static const todayHighlight = Color(0xFFE8F4FE);

  static double monthWidth(int daysInMonth) => daysInMonth * dayColumnWidth;

  static double dayWidth() => hourColumnWidth * 24;

  static bool isCurrentMonth(int year, int month) {
    final now = DateTime.now();
    return year == now.year && month == now.month;
  }

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static ({double left, double width}) blockRect({
    required DateTime start,
    required DateTime end,
    required int year,
    required int month,
    required int daysInMonth,
  }) {
    final monthStart = DateTime(year, month, 1);
    final monthEnd = DateTime(year, month + 1, 1);
    var effectiveStart = start.isBefore(monthStart) ? monthStart : start;
    var effectiveEnd = end.isAfter(monthEnd) ? monthEnd : end;
    if (!effectiveEnd.isAfter(effectiveStart)) {
      return (left: 0.0, width: 0.0);
    }

    final totalMinutes = daysInMonth * 24 * 60;
    final startOffset = effectiveStart.difference(monthStart).inMinutes;
    final duration = effectiveEnd.difference(effectiveStart).inMinutes;
    final width = monthWidth(daysInMonth);
    return (
      left: (startOffset / totalMinutes) * width,
      width: math.max(minMonthBarWidth, (duration / totalMinutes) * width),
    );
  }

  static ({double left, double width}) dayBlockRect({
    required DateTime start,
    required DateTime end,
    required DateTime day,
  }) {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    var effectiveStart = start.isBefore(dayStart) ? dayStart : start;
    var effectiveEnd = end.isAfter(dayEnd) ? dayEnd : end;
    if (!effectiveEnd.isAfter(effectiveStart)) {
      return (left: 0.0, width: 0.0);
    }

    const totalMinutes = 24 * 60;
    final totalWidth = dayWidth();
    final startOffset = effectiveStart.difference(dayStart).inMinutes;
    final duration = effectiveEnd.difference(effectiveStart).inMinutes;
    return (
      left: (startOffset / totalMinutes) * totalWidth,
      width: math.max(4, (duration / totalMinutes) * totalWidth),
    );
  }

  static bool overlapsRange(
    DateTime aStart,
    DateTime aEnd,
    DateTime bStart,
    DateTime bEnd,
  ) =>
      aStart.isBefore(bEnd) && bStart.isBefore(aEnd);

  static Map<String, ({int lane, int laneCount})> assignLanes(
    List<AdminTimelineReservation> reservations,
  ) {
    final items = reservations
        .where((r) => r.startAt != null && r.endAt != null)
        .toList()
      ..sort((a, b) => a.startAt!.compareTo(b.startAt!));

    if (items.isEmpty) return {};

    final laneEndTimes = <DateTime>[];
    final laneById = <String, int>{};

    for (final reservation in items) {
      var lane = 0;
      while (lane < laneEndTimes.length &&
          laneEndTimes[lane].isAfter(reservation.startAt!)) {
        lane++;
      }
      if (lane == laneEndTimes.length) {
        laneEndTimes.add(reservation.endAt!);
      } else {
        laneEndTimes[lane] = reservation.endAt!;
      }
      laneById[reservation.id] = lane;
    }

    final laneCount = math.max(1, laneEndTimes.length);
    return {
      for (final reservation in items)
        reservation.id: (
          lane: laneById[reservation.id]!,
          laneCount: laneCount,
        ),
    };
  }

  static List<AdminTimelineReservation> reservationsOnDay(
    List<AdminTimelineReservation> reservations,
    DateTime day,
  ) {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    return reservations.where((r) {
      final start = r.startAt;
      final end = r.endAt;
      if (start == null || end == null) return false;
      return start.isBefore(dayEnd) && end.isAfter(dayStart);
    }).toList();
  }
}

class AdminReservationTimelineView extends StatefulWidget {
  final AdminReservationTimelineData data;
  final int year;
  final int month;
  final bool canGoNextMonth;
  final VoidCallback onPreviousMonth;
  final VoidCallback? onNextMonth;

  const AdminReservationTimelineView({
    super.key,
    required this.data,
    required this.year,
    required this.month,
    required this.canGoNextMonth,
    required this.onPreviousMonth,
    this.onNextMonth,
  });

  @override
  State<AdminReservationTimelineView> createState() =>
      _AdminReservationTimelineViewState();
}

class _AdminReservationTimelineViewState
    extends State<AdminReservationTimelineView> {
  final _horizontalScroll = ScrollController();
  final _verticalScroll = ScrollController();
  final _monthHeaderFormat = DateFormat('yyyy년 M월');
  final _dayHeaderFormat = DateFormat('M월 d일 (E)', 'ko_KR');
  final _dateTime = DateFormat('yyyy.MM.dd HH:mm');
  final _timeOnly = DateFormat('HH:mm');
  final _won = NumberFormat('#,###');

  _TimelineDisplayMode _mode = _TimelineDisplayMode.month;
  DateTime? _selectedDay;
  int? _lastScrollKeyYear;
  int? _lastScrollKeyMonth;
  _TimelineDisplayMode? _lastScrollKeyMode;
  DateTime? _lastScrollKeyDay;

  @override
  void initState() {
    super.initState();
    _scheduleInitialScroll();
  }

  @override
  void didUpdateWidget(covariant AdminReservationTimelineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.year != widget.year || oldWidget.month != widget.month) {
      if (_mode == _TimelineDisplayMode.day && _selectedDay != null) {
        final day = _selectedDay!;
        if (day.year != widget.year || day.month != widget.month) {
          setState(() {
            _mode = _TimelineDisplayMode.month;
            _selectedDay = null;
          });
        }
      }
      _scheduleInitialScroll(force: true);
    }
  }

  @override
  void dispose() {
    _horizontalScroll.dispose();
    _verticalScroll.dispose();
    super.dispose();
  }

  int get _daysInMonth => DateTime(widget.year, widget.month + 1, 0).day;

  bool get _isCurrentMonth =>
      AdminReservationTimelineLayout.isCurrentMonth(widget.year, widget.month);

  double get _timelineWidth => _mode == _TimelineDisplayMode.month
      ? AdminReservationTimelineLayout.monthWidth(_daysInMonth)
      : AdminReservationTimelineLayout.dayWidth();

  List<AdminTimelineReservation> _reservationsForVehicle(String vehicleId) {
    return widget.data.reservations
        .where((r) => r.vehicleId == vehicleId)
        .toList();
  }

  Vehicle _toBookingVehicle(AdminVehicleDetail vehicle) {
    return Vehicle(
      id: vehicle.id,
      complexId: vehicle.complexId,
      name: vehicle.name,
      vehicleType: vehicle.vehicleType,
      serviceType: RentalPricing.parseServiceType(
        vehicle.vehicleType,
        rentalTypes: vehicle.rentalTypes,
      ),
      pricePerHour: vehicle.pricePerHour,
      dailyPrice: vehicle.dailyPrice,
      monthlyPrice: vehicle.monthlyPrice,
      rentalTypes: vehicle.rentalTypes,
      carNumber: vehicle.carNumber,
      isPublished: vehicle.isPublished,
      isAvailable: vehicle.isAvailable,
      isUnderMaintenance: vehicle.isUnderMaintenance,
      maintenanceMemo: vehicle.maintenanceMemo,
    );
  }

  void _openBooking(AdminVehicleDetail vehicle, DateTime day) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReservationScreen(
          vehicle: _toBookingVehicle(vehicle),
          initialDay: day,
        ),
      ),
    );
  }

  void _scheduleInitialScroll({bool force = false, int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_horizontalScroll.hasClients) {
        if (attempt < 8) {
          _scheduleInitialScroll(force: force, attempt: attempt + 1);
        }
        return;
      }

      final mode = _mode;
      final day = _selectedDay;
      if (!force &&
          _lastScrollKeyYear == widget.year &&
          _lastScrollKeyMonth == widget.month &&
          _lastScrollKeyMode == mode &&
          _lastScrollKeyDay == day) {
        return;
      }

      double target = 0;
      if (mode == _TimelineDisplayMode.month) {
        if (_isCurrentMonth) {
          final today = DateTime.now().day;
          final columnIndex = (today - 2).clamp(0, _daysInMonth - 1);
          target = columnIndex * AdminReservationTimelineLayout.dayColumnWidth;
        }
      } else if (day != null) {
        final now = DateTime.now();
        if (AdminReservationTimelineLayout.isSameDay(day, now)) {
          final hourIndex = (now.hour - 1).clamp(0, 23);
          target = hourIndex * AdminReservationTimelineLayout.hourColumnWidth;
        }
      }

      final max = _horizontalScroll.position.maxScrollExtent;
      _horizontalScroll.jumpTo(target.clamp(0, max));

      _lastScrollKeyYear = widget.year;
      _lastScrollKeyMonth = widget.month;
      _lastScrollKeyMode = mode;
      _lastScrollKeyDay = day;
    });
  }

  void _openDayView(int day) {
    setState(() {
      _selectedDay = DateTime(widget.year, widget.month, day);
      _mode = _TimelineDisplayMode.day;
    });
    _lastScrollKeyMode = null;
    _scheduleInitialScroll(force: true);
  }

  void _returnToMonthView() {
    setState(() {
      _mode = _TimelineDisplayMode.month;
      _selectedDay = null;
    });
    _lastScrollKeyMode = null;
    _scheduleInitialScroll(force: true);
  }

  void _shiftSelectedDay(int delta) {
    final day = _selectedDay;
    if (day == null) return;
    final next = day.add(Duration(days: delta));
    if (next.year != widget.year || next.month != widget.month) return;
    setState(() => _selectedDay = next);
    _lastScrollKeyDay = null;
    _scheduleInitialScroll(force: true);
  }

  Future<void> _showReservationPopup(AdminTimelineReservation reservation) async {
    final phone = reservation.renterPhone.trim();
    final canCall = phone.isNotEmpty && phone != '미등록';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: DanjiColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.viewInsetsOf(ctx).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      reservation.vehicleName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  ReservationStatusBadge(
                    status:
                        reservation.isNoShow ? 'completed' : reservation.status,
                    isNoShow: reservation.isNoShow,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _PopupRow(
                label: '예약번호',
                value: reservation.reservationNumberLabel,
              ),
              _PopupRow(label: '임차인', value: reservation.renterName),
              if (canCall)
                InkWell(
                  onTap: () => launchPhoneCall(phone),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(
                          width: 72,
                          child: Text(
                            '전화번호',
                            style: TextStyle(
                              color: DanjiColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            phone,
                            style: const TextStyle(
                              color: DanjiColors.buttonBlue,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.phone_outlined,
                          size: 18,
                          color: DanjiColors.buttonBlue,
                        ),
                      ],
                    ),
                  ),
                )
              else
                _PopupRow(label: '전화번호', value: '미등록'),
              const SizedBox(height: 4),
              if (reservation.startAt != null)
                _PopupRow(
                  label: '예약 시작',
                  value: _dateTime.format(reservation.startAt!),
                ),
              if (reservation.endAt != null)
                _PopupRow(
                  label: '예약 종료',
                  value: _dateTime.format(reservation.endAt!),
                ),
              ReservationTimesPanel(
                formatter: _dateTime,
                mode: ReservationTimesMode.admin,
                scheduledStartAt: reservation.startAt,
                scheduledEndAt: reservation.endAt,
                rentalStartedAt: reservation.rentalStartedAt,
                returnedAt: reservation.returnedAt,
              ),
              const SizedBox(height: 8),
              _PopupRow(
                label: '결제 금액',
                value: '₩${_won.format(reservation.totalPrice)}',
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AdminReservationDetailScreen(
                        reservation: reservation,
                      ),
                    ),
                  );
                },
                child: const Text('예약 상세 보기'),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _blockColor(AdminTimelineReservation reservation) {
    if (reservation.isNoShow) return const Color(0xFFFF9800);
    switch (reservation.status) {
      case 'confirmed':
        return const Color(0xFF3182F6);
      case 'in_use':
        return const Color(0xFF22C55E);
      case 'returned':
        return const Color(0xFFB0B8C1);
      case 'completed':
        return const Color(0xFF4B5563);
      default:
        return const Color(0xFF9CA3AF);
    }
  }

  String? _monthBlockLabel(AdminTimelineReservation reservation, double width) {
    if (width < 28) return null;
    final name = reservation.renterName.trim();
    if (name.isEmpty) return null;
    if (width < 44) return name.substring(0, 1);
    return name.length > 4 ? name.substring(0, 4) : name;
  }

  String? _dayBlockLabel(AdminTimelineReservation reservation, double width) {
    final start = reservation.startAt;
    if (start == null) return null;
    final name = reservation.renterName.trim();
    final time = _timeOnly.format(start);
    if (width < 28) return null;
    if (width < 52) {
      if (name.isEmpty) return time;
      return name.length > 2 ? name.substring(0, 2) : name;
    }
    if (name.isEmpty) return time;
    final shortName = name.length > 4 ? name.substring(0, 4) : name;
    if (width < 80) return shortName;
    return '$shortName $time';
  }

  Widget _buildReservationBlock({
    required AdminTimelineReservation reservation,
    required double left,
    required double width,
    required int lane,
    required int laneCount,
    required String? label,
  }) {
    if (width <= 0) return const SizedBox.shrink();

    final color = _blockColor(reservation);
    final inset = 4.0;
    final laneHeight =
        (AdminReservationTimelineLayout.rowHeight - inset * 2) / laneCount;
    final top = inset + lane * laneHeight;
    final height = math.max(8.0, laneHeight - 2);

    return Positioned(
      left: left,
      width: width,
      top: top,
      height: height,
      child: GestureDetector(
        onTap: () => _showReservationPopup(reservation),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: label == null
              ? null
              : Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: reservation.status == 'returned'
                        ? DanjiColors.textPrimary
                        : Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildMonthDayHeader() {
    final weekdayLabels = ['', '월', '화', '수', '목', '금', '토', '일'];
    final today = DateTime.now();
    final highlightToday = _isCurrentMonth;

    return SizedBox(
      height: AdminReservationTimelineLayout.headerHeight,
      width: _timelineWidth,
      child: Row(
        children: List.generate(_daysInMonth, (index) {
          final day = index + 1;
          final date = DateTime(widget.year, widget.month, day);
          final isToday = highlightToday &&
              today.year == date.year &&
              today.month == date.month &&
              today.day == date.day;
          final isWeekend =
              date.weekday == DateTime.saturday ||
              date.weekday == DateTime.sunday;

          return GestureDetector(
            onTap: () => _openDayView(day),
            child: Container(
              width: AdminReservationTimelineLayout.dayColumnWidth,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isToday
                    ? AdminReservationTimelineLayout.todayHighlight
                    : null,
                border: Border(
                  right: BorderSide(
                    color: DanjiColors.border.withValues(alpha: 0.7),
                  ),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$day',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: isToday
                          ? DanjiColors.buttonBlue
                          : (isWeekend
                              ? DanjiColors.accentRed
                              : DanjiColors.textPrimary),
                    ),
                  ),
                  Text(
                    weekdayLabels[date.weekday],
                    style: TextStyle(
                      fontSize: 10,
                      color: isToday
                          ? DanjiColors.buttonBlue
                          : (isWeekend
                              ? DanjiColors.accentRed.withValues(alpha: 0.85)
                              : DanjiColors.textMuted),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildHourHeader() {
    return SizedBox(
      height: AdminReservationTimelineLayout.headerHeight,
      width: _timelineWidth,
      child: Row(
        children: List.generate(24, (hour) {
          return Container(
            width: AdminReservationTimelineLayout.hourColumnWidth,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: DanjiColors.border.withValues(alpha: 0.7),
                ),
              ),
            ),
            child: Text(
              hour % 3 == 0 ? '$hour' : '',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: DanjiColors.textMuted,
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildVehicleLabel(AdminVehicleDetail vehicle) {
    return SizedBox(
      height: AdminReservationTimelineLayout.rowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              vehicle.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            if (vehicle.carNumber != null &&
                vehicle.carNumber!.trim().isNotEmpty)
              Text(
                vehicle.carNumber!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  color: DanjiColors.textMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthTimelineTrack(AdminVehicleDetail vehicle) {
    final reservations = _reservationsForVehicle(vehicle.id);
    final lanes = AdminReservationTimelineLayout.assignLanes(reservations);
    final today = DateTime.now();

    return SizedBox(
      height: AdminReservationTimelineLayout.rowHeight,
      width: _timelineWidth,
      child: Stack(
        children: [
          Row(
            children: List.generate(_daysInMonth, (index) {
              final day = DateTime(widget.year, widget.month, index + 1);
              final isToday = _isCurrentMonth &&
                  AdminReservationTimelineLayout.isSameDay(day, today);
              final bg = isToday
                  ? AdminReservationTimelineLayout.todayHighlight
                  : (index.isEven
                      ? const Color(0xFFF9FAFB)
                      : Colors.white);
              return GestureDetector(
                onTap: () => _openBooking(vehicle, day),
                child: Container(
                  width: AdminReservationTimelineLayout.dayColumnWidth,
                  height: AdminReservationTimelineLayout.rowHeight,
                  decoration: BoxDecoration(
                    color: bg,
                    border: Border(
                      right: BorderSide(
                        color: DanjiColors.border.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          ...reservations.map((reservation) {
            final start = reservation.startAt;
            final end = reservation.endAt;
            if (start == null || end == null) {
              return const SizedBox.shrink();
            }
            final rect = AdminReservationTimelineLayout.blockRect(
              start: start,
              end: end,
              year: widget.year,
              month: widget.month,
              daysInMonth: _daysInMonth,
            );
            final laneInfo = lanes[reservation.id];
            if (rect.width <= 0 || laneInfo == null) {
              return const SizedBox.shrink();
            }
            return _buildReservationBlock(
              reservation: reservation,
              left: rect.left,
              width: rect.width,
              lane: laneInfo.lane,
              laneCount: laneInfo.laneCount,
              label: _monthBlockLabel(reservation, rect.width),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildDayTimelineTrack(AdminVehicleDetail vehicle, DateTime day) {
    final reservations = AdminReservationTimelineLayout.reservationsOnDay(
      _reservationsForVehicle(vehicle.id),
      day,
    );
    final lanes = AdminReservationTimelineLayout.assignLanes(reservations);

    return SizedBox(
      height: AdminReservationTimelineLayout.rowHeight,
      width: _timelineWidth,
      child: Stack(
        children: [
          Row(
            children: List.generate(24, (hour) {
              final bg = hour.isEven ? const Color(0xFFF9FAFB) : Colors.white;
              return Container(
                width: AdminReservationTimelineLayout.hourColumnWidth,
                height: AdminReservationTimelineLayout.rowHeight,
                decoration: BoxDecoration(
                  color: bg,
                  border: Border(
                    right: BorderSide(
                      color: DanjiColors.border.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              );
            }),
          ),
          ...reservations.map((reservation) {
            final start = reservation.startAt;
            final end = reservation.endAt;
            if (start == null || end == null) {
              return const SizedBox.shrink();
            }
            final rect = AdminReservationTimelineLayout.dayBlockRect(
              start: start,
              end: end,
              day: day,
            );
            final laneInfo = lanes[reservation.id];
            if (rect.width <= 0 || laneInfo == null) {
              return const SizedBox.shrink();
            }
            return _buildReservationBlock(
              reservation: reservation,
              left: rect.left,
              width: rect.width,
              lane: laneInfo.lane,
              laneCount: laneInfo.laneCount,
              label: _dayBlockLabel(reservation, rect.width),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildDayViewHeader() {
    final day = _selectedDay;
    if (day == null) return const SizedBox.shrink();

    final canGoPrev = day.day > 1;
    final canGoNext = day.day < _daysInMonth;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: canGoPrev ? () => _shiftSelectedDay(-1) : null,
            icon: const Icon(Icons.chevron_left),
            tooltip: '이전 날',
          ),
          Expanded(
            child: Text(
              _dayHeaderFormat.format(day),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ),
          IconButton(
            onPressed: canGoNext ? () => _shiftSelectedDay(1) : null,
            icon: const Icon(Icons.chevron_right),
            tooltip: '다음 날',
          ),
          TextButton(
            onPressed: _returnToMonthView,
            child: const Text('월 보기'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = _monthHeaderFormat.format(
      DateTime(widget.year, widget.month),
    );
    final vehicles = widget.data.vehicles;
    final selectedDay = _selectedDay;
    final isDayMode =
        _mode == _TimelineDisplayMode.day && selectedDay != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isDayMode)
          _buildDayViewHeader()
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: GestureDetector(
              onHorizontalDragEnd: (details) {
                final velocity = details.primaryVelocity ?? 0;
                if (velocity < -180 && widget.canGoNextMonth) {
                  widget.onNextMonth?.call();
                } else if (velocity > 180) {
                  widget.onPreviousMonth();
                }
              },
              child: MonthFilterBar(
                label: monthLabel,
                canGoNext: widget.canGoNextMonth,
                onPrevious: widget.onPreviousMonth,
                onNext: widget.onNextMonth,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 10,
            runSpacing: 6,
            children: const [
              _LegendDot(color: Color(0xFF3182F6), label: '예약확정'),
              _LegendDot(color: Color(0xFF22C55E), label: '이용중'),
              _LegendDot(color: Color(0xFFB0B8C1), label: '반납'),
              _LegendDot(color: Color(0xFF4B5563), label: '완료'),
              _LegendDot(color: Color(0xFFFF9800), label: '노쇼'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (vehicles.isEmpty)
          const Expanded(
            child: Center(child: Text('등록된 차량이 없습니다.')),
          )
        else
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: AdminReservationTimelineLayout.vehicleLabelWidth,
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context)
                        .copyWith(scrollbars: false),
                    child: ListView(
                      controller: _verticalScroll,
                      physics: const ClampingScrollPhysics(),
                      children: [
                        SizedBox(
                          height: AdminReservationTimelineLayout.headerHeight,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text(
                                isDayMode ? '차량 · 시간' : '차량',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                  color: DanjiColors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                        ...vehicles.expand((vehicle) sync* {
                          yield _buildVehicleLabel(vehicle);
                          yield const Divider(height: 1);
                        }),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _horizontalScroll,
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    child: SizedBox(
                      width: _timelineWidth,
                      child: ScrollConfiguration(
                        behavior: ScrollConfiguration.of(context)
                            .copyWith(scrollbars: false),
                        child: ListView(
                          controller: _verticalScroll,
                          physics: const ClampingScrollPhysics(),
                          children: [
                            if (isDayMode)
                              _buildHourHeader()
                            else
                              _buildMonthDayHeader(),
                            const Divider(height: 1),
                            ...vehicles.expand((vehicle) sync* {
                              if (isDayMode) {
                                yield _buildDayTimelineTrack(
                                  vehicle,
                                  selectedDay,
                                );
                              } else {
                                yield _buildMonthTimelineTrack(vehicle);
                              }
                              yield const Divider(height: 1);
                            }),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: DanjiColors.textSecondary),
        ),
      ],
    );
  }
}

class _PopupRow extends StatelessWidget {
  final String label;
  final String value;

  const _PopupRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                color: DanjiColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
