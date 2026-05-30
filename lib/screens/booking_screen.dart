import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../config/payment_config.dart';
import '../models/vehicle.dart';
import '../models/vehicle_query_result.dart';
import '../services/payment_service.dart';
import '../services/reservation_service.dart';
import '../services/vehicle_service.dart';
import '../supabase_client.dart';
import '../theme/danji_colors.dart';
import '../theme/danji_theme.dart';
import '../widgets/danji_app_bar.dart';
import '../widgets/payment_method_sheet.dart';

class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  /// 0~23시 시작·종료. 종료 시각이 시작 이하이면 익일로 처리 (예: 23:00~01:00)
  static const _minHour = 0;
  static const _maxHour = 23;

  final _vehicleService = VehicleService();
  final _reservationService = ReservationService();
  final _paymentService = PaymentService();
  final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');

  Future<VehicleQueryResult>? _vehiclesFuture;
  VehicleQueryResult? _lastResult;
  Vehicle? _selected;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  int _startHour = 9;
  int _endHour = 10;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedDay = _dateOnly(DateTime.now());
    _normalizeHoursForSelectedDay();
    _vehiclesFuture = _loadVehicles();
  }

  DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  Future<VehicleQueryResult> _loadVehicles() async {
    final result = await _vehicleService.fetchVehiclesForMyComplex();
    _lastResult = result;
    return result;
  }

  int get _durationHours {
    final start = _buildStartDateTime(_selectedDay, _startHour);
    final end = _buildEndDateTime(_selectedDay, _endHour);
    if (start == null || end == null) return 0;
    return end.difference(start).inHours;
  }

  bool _isToday(DateTime day) {
    final now = DateTime.now();
    return day.year == now.year &&
        day.month == now.month &&
        day.day == now.day;
  }

  List<int> get _startHourOptions {
    final options = <int>[
      for (var h = _minHour; h <= _maxHour; h++) h,
    ];
    final day = _selectedDay;
    if (day == null || !_isToday(day)) return options;

    final now = DateTime.now();
    return options.where((h) {
      final slot = _buildStartDateTime(day, h);
      if (slot == null) return false;
      // 해당 시간대 시작부터 최소 1시간 예약 가능해야 함
      return slot.add(const Duration(hours: 1)).isAfter(now);
    }).toList();
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

  void _normalizeHoursForSelectedDay() {
    final starts = _startHourOptions;
    if (starts.isEmpty) return;

    if (!starts.contains(_startHour)) {
      _startHour = starts.first;
    }

    final ends = _endHourOptions;
    if (ends.isEmpty) return;
    if (!ends.contains(_endHour)) {
      _endHour = ends.first;
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

  int? get _totalPrice {
    final vehicle = _selected;
    if (vehicle == null || _durationHours < 1) return null;
    return _durationHours * vehicle.pricePerHour;
  }

  void _selectVehicle(Vehicle vehicle) {
    if (!vehicle.isAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('현재 예약할 수 없는 차량입니다.')),
      );
      return;
    }
    setState(() {
      _selected = vehicle;
      _error = null;
    });
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
    final totalPrice = _totalPrice;
    if (startTime == null || endTime == null || totalPrice == null) return;

    if (startTime.isBefore(DateTime.now())) {
      setState(() => _error = '과거 시간은 예약할 수 없습니다.');
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

    final method = await showPaymentMethodSheet(context);
    if (method == null || !mounted) return;

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
        vehicle: vehicle,
        startTime: startTime,
        endTime: endTime,
        totalPrice: totalPrice,
        method: method,
      );
    } catch (e) {
      if (!mounted) return;
      if (e is ReservationOverlapException ||
          e is ReservationPermissionException) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      } else {
        setState(() => _error = friendlyPaymentError(e));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyPaymentError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatWon(int amount) {
    return NumberFormat('#,###').format(amount);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: const DanjiAppBar(title: '차량 예약'),
      body: FutureBuilder<VehicleQueryResult>(
        future: _vehiclesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
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
          final vehicles = result?.vehicles ?? [];

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

          return RefreshIndicator(
            color: DanjiColors.buttonBlue,
            onRefresh: () async {
              setState(() {
                _vehiclesFuture = _loadVehicles();
              });
              await _vehiclesFuture;
            },
            child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              if (result?.complexName != null) ...[
                Text(
                  '${result!.complexName} 공용차',
                  style: const TextStyle(
                    color: DanjiColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (result.inviteCode != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 12),
                    child: Text(
                      '초대코드 ${result.inviteCode} · 다른 단지 차량은 표시되지 않습니다',
                      style: TextStyle(
                        color: DanjiColors.textSecondary.withValues(alpha: 0.9),
                        fontSize: 13,
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 12),
              ] else ...[
                const Text(
                  '차량 선택',
                  style: TextStyle(
                    color: DanjiColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              ...vehicles.map((v) => _VehicleTile(
                    vehicle: v,
                    selected: _selected?.id == v.id,
                    onTap: () => _selectVehicle(v),
                  )),
              if (_selected != null) ...[
                const SizedBox(height: 20),
                _VehicleDetailCard(vehicle: _selected!),
                const SizedBox(height: 16),
                _SectionCard(
                  child: TableCalendar<void>(
                    firstDay: _dateOnly(DateTime.now()),
                    lastDay: _dateOnly(DateTime.now()).add(const Duration(days: 365)),
                    focusedDay: _focusedDay,
                    selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                    locale: 'ko_KR',
                    startingDayOfWeek: StartingDayOfWeek.monday,
                    headerStyle: const HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                      titleTextStyle: TextStyle(
                        color: DanjiColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                      leftChevronIcon: const Icon(
                        Icons.chevron_left,
                        color: DanjiColors.textPrimary,
                      ),
                      rightChevronIcon: const Icon(
                        Icons.chevron_right,
                        color: DanjiColors.textPrimary,
                      ),
                    ),
                    calendarStyle: CalendarStyle(
                      outsideDaysVisible: false,
                      defaultTextStyle:
                          const TextStyle(color: DanjiColors.textPrimary),
                      weekendTextStyle:
                          const TextStyle(color: DanjiColors.textSecondary),
                      todayTextStyle: const TextStyle(
                        color: DanjiColors.buttonBlue,
                        fontWeight: FontWeight.w800,
                      ),
                      todayDecoration: BoxDecoration(
                        color: DanjiColors.skyLight,
                        shape: BoxShape.circle,
                      ),
                      selectedDecoration: const BoxDecoration(
                        color: DanjiColors.buttonBlue,
                        shape: BoxShape.circle,
                      ),
                      selectedTextStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    enabledDayPredicate: (day) =>
                        !day.isBefore(_dateOnly(DateTime.now())),
                    onDaySelected: (selectedDay, focusedDay) {
                      setState(() {
                        _selectedDay = _dateOnly(selectedDay);
                        _focusedDay = focusedDay;
                        _error = null;
                        _normalizeHoursForSelectedDay();
                      });
                    },
                    onPageChanged: (focusedDay) => _focusedDay = focusedDay,
                  ),
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  child: Column(
                    children: [
                      _HourDropdown(
                        label: '시작 (1시간 단위)',
                        value: _startHour,
                        hours: _startHourOptions,
                        labelBuilder: _formatHourLabel,
                        onChanged: (hour) {
                          if (hour == null) return;
                          setState(() {
                            _startHour = hour;
                            _normalizeHoursForSelectedDay();
                            _error = null;
                          });
                        },
                      ),
                      const Divider(height: 24, color: DanjiColors.border),
                      _HourDropdown(
                        label: '종료 (1시간 단위)',
                        value: _endHour,
                        hours: _endHourOptions,
                        labelBuilder: _formatEndHourLabel,
                        onChanged: (hour) {
                          if (hour == null) return;
                          setState(() {
                            _endHour = hour;
                            _error = null;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                if (_selectedDay != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    '예약: ${_dateFormat.format(_buildStartDateTime(_selectedDay!, _startHour)!)}'
                    ' ~ ${_dateFormat.format(_buildEndDateTime(_selectedDay!, _endHour)!)}'
                    ' (${_durationHours}시간)',
                    style: const TextStyle(
                      color: DanjiColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
                if (_totalPrice != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '총 요금: ₩${_formatWon(_totalPrice!)}',
                    style: const TextStyle(
                      color: DanjiColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: DanjiColors.accentRed),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  height: 52,
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _loading ? null : _submit,
                    style: DanjiTheme.primaryButton,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            '예약하기',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ),
              ],
            ],
          ),
          );
        },
      ),
    );
  }
}

class _VehicleTile extends StatelessWidget {
  final Vehicle vehicle;
  final bool selected;
  final VoidCallback onTap;

  const _VehicleTile({
    required this.vehicle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? DanjiColors.skyLight : DanjiColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: selected ? DanjiColors.buttonBlue : DanjiColors.border,
                width: selected ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(
                    Icons.directions_car_filled_outlined,
                    color: vehicle.isAvailable
                        ? DanjiColors.textPrimary
                        : DanjiColors.textSecondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          vehicle.name,
                          style: const TextStyle(
                            color: DanjiColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '${vehicle.vehicleType} · ${vehicle.priceLabel}',
                          style: const TextStyle(
                            color: DanjiColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selected)
                    const Icon(
                      Icons.check_circle,
                      color: DanjiColors.buttonBlue,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VehicleDetailCard extends StatelessWidget {
  final Vehicle vehicle;

  const _VehicleDetailCard({required this.vehicle});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            vehicle.name,
            style: const TextStyle(
              color: DanjiColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          _DetailRow(label: '종류', value: vehicle.vehicleType),
          _DetailRow(label: '시간당', value: vehicle.priceLabel),
          if (vehicle.parkingLocation != null)
            _DetailRow(label: '주차', value: vehicle.parkingLocation!),
          if (vehicle.carNumber != null)
            _DetailRow(label: '번호', value: vehicle.carNumber!),
          _DetailRow(
            label: '상태',
            value: vehicle.isAvailable ? '예약 가능' : '예약 불가',
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: const TextStyle(color: DanjiColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: DanjiColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
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
      width: double.infinity,
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

class _HourDropdown extends StatelessWidget {
  final String label;
  final int value;
  final List<int> hours;
  final String Function(int hour) labelBuilder;
  final ValueChanged<int?> onChanged;

  const _HourDropdown({
    required this.label,
    required this.value,
    required this.hours,
    required this.labelBuilder,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: DanjiColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (hours.isEmpty)
          const Text(
            '선택 가능한 시간 없음',
            style: TextStyle(color: DanjiColors.accentRed, fontSize: 13),
          )
        else
          DropdownButton<int>(
            value: hours.contains(value) ? value : null,
            dropdownColor: DanjiColors.surface,
            style: const TextStyle(color: DanjiColors.textPrimary),
            underline: const SizedBox.shrink(),
            items: hours
                .map(
                  (h) => DropdownMenuItem(
                    value: h,
                    child: Text(labelBuilder(h)),
                  ),
                )
                .toList(),
            onChanged: onChanged,
          ),
      ],
    );
  }
}
