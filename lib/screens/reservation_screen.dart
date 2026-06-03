import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../models/reservation.dart';
import '../models/vehicle.dart';
import '../services/reservation_service.dart';
import '../theme/danji_colors.dart';
import '../theme/danji_theme.dart';
import '../theme/danji_typography.dart';
import '../widgets/danji_app_bar.dart';

class ReservationScreen extends StatefulWidget {
  final Vehicle vehicle;
  final Reservation? existingReservation;

  const ReservationScreen({
    super.key,
    required this.vehicle,
    this.existingReservation,
  });

  bool get isEditMode => existingReservation != null;

  @override
  State<ReservationScreen> createState() => _ReservationScreenState();
}

class _ReservationScreenState extends State<ReservationScreen> {
  final _service = ReservationService();
  final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');
  final _won = NumberFormat('#,###');

  late DateTime _focusedDay;
  DateTime? _selectedDay;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;

  bool _loading = false;
  String? _error;

  bool get _isEditMode => widget.isEditMode;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingReservation;
    if (existing != null) {
      final start = existing.startAt ?? DateTime.now();
      final end = existing.endAt ?? start.add(const Duration(hours: 2));
      _selectedDay = _dateOnly(start);
      _focusedDay = _selectedDay!;
      _startTime = TimeOfDay(hour: start.hour, minute: start.minute);
      _endTime = TimeOfDay(hour: end.hour, minute: end.minute);
    } else {
      _selectedDay = _dateOnly(DateTime.now());
      _focusedDay = _selectedDay!;
      _startTime = const TimeOfDay(hour: 9, minute: 0);
      _endTime = const TimeOfDay(hour: 11, minute: 0);
    }
  }

  DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  DateTime? _buildDateTime(DateTime day, TimeOfDay time) {
    return DateTime(day.year, day.month, day.day, time.hour, time.minute);
  }

  int _computeTotalPrice(DateTime startAt, DateTime endAt) {
    final hours = endAt.difference(startAt).inMinutes / 60.0;
    final billableHours = hours < 1 ? 1 : hours.ceil();
    return billableHours * widget.vehicle.pricePerHour;
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: DanjiColors.buttonBlue,
              surface: DanjiColors.surface,
              onSurface: DanjiColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
      _error = null;
    });
  }

  Future<void> _submit() async {
    final day = _selectedDay;
    if (day == null) {
      setState(() => _error = '예약 날짜를 선택해주세요.');
      return;
    }

    final startAt = _buildDateTime(day, _startTime);
    final endAt = _buildDateTime(day, _endTime);
    if (startAt == null || endAt == null) return;

    if (!endAt.isAfter(startAt)) {
      setState(() => _error = '종료 시간은 시작 시간보다 뒤여야 합니다.');
      return;
    }

    if (endAt.difference(startAt).inMinutes < 60) {
      setState(() => _error = '최소 1시간 이상 예약해야 합니다.');
      return;
    }

    if (startAt.isBefore(DateTime.now())) {
      setState(() => _error = '과거 시간은 예약할 수 없습니다.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_isEditMode) {
        final reservation = widget.existingReservation!;
        final totalPrice = _computeTotalPrice(startAt, endAt);
        await _service.updateReservationForMe(
          reservationId: reservation.id,
          startAt: startAt,
          endAt: endAt,
          totalPrice: totalPrice,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('예약이 변경되었습니다.'),
          ),
        );
        Navigator.of(context).pop(true);
      } else {
        await _service.createReservation(
          vehicleId: widget.vehicle.id,
          startAt: startAt,
          endAt: endAt,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('예약이 접수되었습니다. (대기)')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (e is ReservationOverlapException ||
          e is ReservationPermissionException ||
          e is ReservationChangeException) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
        return;
      }
      setState(() => _error = friendlyReservationError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vehicle = widget.vehicle;
    final day = _selectedDay;
    final startAt = day != null ? _buildDateTime(day, _startTime) : null;
    final endAt = day != null ? _buildDateTime(day, _endTime) : null;
    final previewPrice =
        startAt != null && endAt != null && endAt.isAfter(startAt)
            ? _computeTotalPrice(startAt, endAt)
            : null;

    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: DanjiAppBar(title: _isEditMode ? '예약 변경' : '예약하기'),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vehicle.name,
                  style: DanjiTypography.subtitleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  '${vehicle.vehicleType} · ${vehicle.priceLabel}',
                  style: DanjiTypography.secondary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            child: TableCalendar<void>(
              firstDay: _dateOnly(DateTime.now()),
              lastDay: _dateOnly(DateTime.now()).add(const Duration(days: 365)),
              focusedDay: _focusedDay,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              locale: 'ko_KR',
              startingDayOfWeek: StartingDayOfWeek.monday,
              calendarFormat: CalendarFormat.month,
              availableCalendarFormats: const {
                CalendarFormat.month: '월',
              },
              headerStyle: const HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                titleTextStyle: TextStyle(
                  color: DanjiColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
                leftChevronIcon:
                    Icon(Icons.chevron_left, color: DanjiColors.textPrimary),
                rightChevronIcon:
                    Icon(Icons.chevron_right, color: DanjiColors.textPrimary),
              ),
              daysOfWeekStyle: const DaysOfWeekStyle(
                weekdayStyle: TextStyle(color: DanjiColors.textSecondary),
                weekendStyle: TextStyle(color: DanjiColors.textSecondary),
              ),
              calendarStyle: CalendarStyle(
                outsideDaysVisible: false,
                defaultTextStyle:
                    const TextStyle(color: DanjiColors.textPrimary),
                weekendTextStyle:
                    const TextStyle(color: DanjiColors.textPrimary),
                todayDecoration: BoxDecoration(
                  color: DanjiColors.skySoft.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                todayTextStyle: const TextStyle(
                  color: DanjiColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
                selectedDecoration: const BoxDecoration(
                  color: DanjiColors.buttonBlue,
                  shape: BoxShape.circle,
                ),
                selectedTextStyle: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
                disabledTextStyle: TextStyle(
                  color: DanjiColors.textMuted.withValues(alpha: 0.6),
                ),
              ),
              enabledDayPredicate: (day) {
                return !day.isBefore(_dateOnly(DateTime.now()));
              },
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDay = _dateOnly(selectedDay);
                  _focusedDay = focusedDay;
                  _error = null;
                });
              },
              onPageChanged: (focusedDay) {
                _focusedDay = focusedDay;
              },
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            child: Column(
              children: [
                _TimeRow(
                  label: '시작',
                  value: _startTime.format(context),
                  onTap: () => _pickTime(isStart: true),
                ),
                const Divider(height: 24, color: DanjiColors.border),
                _TimeRow(
                  label: '종료',
                  value: _endTime.format(context),
                  onTap: () => _pickTime(isStart: false),
                ),
              ],
            ),
          ),
          if (startAt != null && endAt != null) ...[
            const SizedBox(height: 12),
            Text(
              '예약 시간: ${_dateFormat.format(startAt)} ~ ${_dateFormat.format(endAt)}',
              style: const TextStyle(
                color: DanjiColors.textSecondary,
                height: 1.4,
              ),
            ),
            if (previewPrice != null) ...[
              const SizedBox(height: 4),
              Text(
                '예상 요금: ₩${_won.format(previewPrice)}',
                style: const TextStyle(
                  color: DanjiColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: DanjiColors.accentRed),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _loading ? null : _submit,
              style: DanjiTheme.primaryButton,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isEditMode ? '변경 저장' : '예약하기'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final Widget child;

  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DanjiColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DanjiColors.border),
      ),
      child: child,
    );
  }
}

class _TimeRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _TimeRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: DanjiColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                color: DanjiColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.schedule,
                color: DanjiColors.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }
}
