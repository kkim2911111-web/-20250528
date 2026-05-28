import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../config/payment_config.dart';
import '../models/vehicle.dart';
import '../models/vehicle_query_result.dart';
import '../services/payment_service.dart';
import '../services/reservation_service.dart';
import '../services/vehicle_service.dart';
import '../widgets/danji_app_bar.dart';
import '../widgets/payment_method_sheet.dart';

class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  static const _bg = Color(0xFF071826);
  static const _textPrimary = Color(0xFFEAF2FF);
  static const _textSecondary = Color(0xFF9AB3C9);
  static const _hours = [6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22];

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
    _vehiclesFuture = _loadVehicles();
  }

  DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  Future<VehicleQueryResult> _loadVehicles() async {
    final result = await _vehicleService.fetchVehiclesForMyComplex();
    _lastResult = result;
    return result;
  }

  int get _durationHours => _endHour - _startHour;

  int? get _totalPrice {
    final vehicle = _selected;
    if (vehicle == null || _durationHours < 1) return null;
    return _durationHours * vehicle.pricePerHour;
  }

  DateTime? _buildDateTime(DateTime day, int hour) {
    return DateTime(day.year, day.month, day.day, hour);
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

    final startTime = _buildDateTime(day, _startHour);
    final endTime = _buildDateTime(day, _endHour);
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
      backgroundColor: _bg,
      appBar: const DanjiAppBar(title: '차량 예약'),
      body: FutureBuilder<VehicleQueryResult>(
        future: _vehiclesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _textPrimary),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                '차량 목록 오류: ${snapshot.error}',
                style: const TextStyle(color: Colors.redAccent),
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
                  style: const TextStyle(color: _textSecondary, height: 1.5),
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (result?.complexName != null) ...[
                Text(
                  '${result!.complexName} 공용차',
                  style: const TextStyle(
                    color: _textPrimary,
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
                        color: _textSecondary.withValues(alpha: 0.9),
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
                    color: _textPrimary,
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
                        color: _textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                      leftChevronIcon: Icon(Icons.chevron_left, color: _textPrimary),
                      rightChevronIcon: Icon(Icons.chevron_right, color: _textPrimary),
                    ),
                    calendarStyle: CalendarStyle(
                      outsideDaysVisible: false,
                      defaultTextStyle: const TextStyle(color: _textPrimary),
                      todayDecoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      selectedDecoration: const BoxDecoration(
                        color: Color(0xFF4DA3FF),
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
                        hours: _hours.where((h) => h < 22).toList(),
                        onChanged: (hour) {
                          if (hour == null) return;
                          setState(() {
                            _startHour = hour;
                            if (_endHour <= _startHour) {
                              _endHour = _startHour + 1;
                            }
                            _error = null;
                          });
                        },
                      ),
                      const Divider(height: 24, color: Color(0xFF1A3348)),
                      _HourDropdown(
                        label: '종료 (1시간 단위)',
                        value: _endHour,
                        hours: _hours.where((h) => h > _startHour).toList(),
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
                    '예약: ${_dateFormat.format(_buildDateTime(_selectedDay!, _startHour)!)}'
                    ' ~ ${_dateFormat.format(_buildDateTime(_selectedDay!, _endHour)!)}'
                    ' (${_durationHours}시간)',
                    style: const TextStyle(color: _textSecondary, height: 1.4),
                  ),
                ],
                if (_totalPrice != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '총 요금: ₩${_formatWon(_totalPrice!)}',
                    style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  height: 52,
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _loading ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF0B2235),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
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
    const primary = Color(0xFFEAF2FF);
    const secondary = Color(0xFF9AB3C9);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? const Color(0xFF16324A) : const Color(0xFF0B2235),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(
                  Icons.directions_car_filled_outlined,
                  color: vehicle.isAvailable ? primary : secondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vehicle.name,
                        style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '${vehicle.vehicleType} · ${vehicle.priceLabel}',
                        style: const TextStyle(color: secondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_circle, color: Color(0xFF4DA3FF)),
              ],
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
              color: Color(0xFFEAF2FF),
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
              style: const TextStyle(color: Color(0xFF9AB3C9)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFFEAF2FF),
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
        color: const Color(0xFF0B2235),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: child,
    );
  }
}

class _HourDropdown extends StatelessWidget {
  final String label;
  final int value;
  final List<int> hours;
  final ValueChanged<int?> onChanged;

  const _HourDropdown({
    required this.label,
    required this.value,
    required this.hours,
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
              color: Color(0xFF9AB3C9),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        DropdownButton<int>(
          value: hours.contains(value) ? value : null,
          dropdownColor: const Color(0xFF0B2235),
          style: const TextStyle(color: Color(0xFFEAF2FF)),
          underline: const SizedBox.shrink(),
          items: hours
              .map(
                (h) => DropdownMenuItem(
                  value: h,
                  child: Text('${h.toString().padLeft(2, '0')}:00'),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
