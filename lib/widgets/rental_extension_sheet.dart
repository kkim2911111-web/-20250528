import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/reservation.dart';
import '../models/vehicle.dart';
import '../services/next_reservation_service.dart';
import '../theme/danji_colors.dart';
import '../theme/danji_typography.dart';
import '../utils/rental_extension_pricing.dart';
import '../utils/rental_pricing.dart';
import '../widgets/booking_time_drum_picker.dart';

/// 연장 바텀시트 — 프리셋·직접 선택·요금 미리보기
class RentalExtensionSheet extends StatefulWidget {
  final Reservation reservation;
  final Vehicle vehicle;
  final NextBlockingReservation? nextReservation;

  const RentalExtensionSheet({
    super.key,
    required this.reservation,
    required this.vehicle,
    this.nextReservation,
  });

  @override
  State<RentalExtensionSheet> createState() => _RentalExtensionSheetState();
}

class _RentalExtensionSheetState extends State<RentalExtensionSheet> {
  final _nextService = NextReservationService();
  late final RentalType _rentalType;
  late final DateTime _currentEnd;
  DateTime? _selectedNewEnd;
  final Map<int, bool> _presetConflictCache = {};

  @override
  void initState() {
    super.initState();
    _rentalType = widget.reservation.rentalType ?? RentalType.hourly;
    _currentEnd = widget.reservation.endAt ?? DateTime.now();
    _warmPresetCache();
  }

  Future<void> _warmPresetCache() async {
    for (final value in RentalExtensionPricing.presetValuesFor(_rentalType)) {
      final newEnd = RentalExtensionPricing.newEndForPreset(
        rentalType: _rentalType,
        currentEnd: _currentEnd,
        presetValue: value,
      );
      final conflicts = await _nextService.extensionConflictsWithOthers(
        vehicleId: widget.reservation.vehicleId,
        currentEnd: _currentEnd,
        newEnd: newEnd,
        excludeReservationId: widget.reservation.id,
      );
      if (!mounted) return;
      setState(() => _presetConflictCache[value] = conflicts);
    }
  }

  DateTime? get _maxEnd {
    final next = widget.nextReservation;
    if (next == null) return null;
    return next.startAt;
  }

  int get _addedPrice {
    final newEnd = _selectedNewEnd;
    if (newEnd == null) return 0;
    return RentalExtensionPricing.addedPrice(
      rentalType: _rentalType,
      currentEnd: _currentEnd,
      newEnd: newEnd,
      vehicle: widget.vehicle,
    );
  }

  bool _isPresetDisabled(int value) => _presetConflictCache[value] == true;

  Future<void> _selectPreset(int value) async {
    if (_isPresetDisabled(value)) return;
    final newEnd = RentalExtensionPricing.newEndForPreset(
      rentalType: _rentalType,
      currentEnd: _currentEnd,
      presetValue: value,
    );
    setState(() => _selectedNewEnd = newEnd);
  }

  Future<void> _openCustomPicker() async {
    var options = RentalExtensionPricing.customEndOptions(
      rentalType: _rentalType,
      currentEnd: _currentEnd,
      maxEnd: _maxEnd,
    );

    if (options.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('선택 가능한 연장 시간이 없습니다.')),
      );
      return;
    }

    // 충돌 옵션 제외
    final filtered = <DateTime>[];
    for (final dt in options) {
      final conflicts = await _nextService.extensionConflictsWithOthers(
        vehicleId: widget.reservation.vehicleId,
        currentEnd: _currentEnd,
        newEnd: dt,
        excludeReservationId: widget.reservation.id,
      );
      if (!conflicts) filtered.add(dt);
    }
    options = filtered;

    if (options.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('다음 예약 때문에 선택 가능한 시간이 없습니다.')),
      );
      return;
    }

    final catalog = RentalExtensionPricing.drumCatalogForEnds(
      options,
      _currentEnd,
    );
    if (catalog.isEmpty) return;

    final initial = _selectedNewEnd ?? options.first;
    final indices = catalog.indicesFor(
      hour: initial.hour,
      minute: initial.minute,
    );

    var draftHour = initial.hour;
    var draftMinute = initial.minute;
    var draftNextDay = false;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: DanjiColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
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
                const SizedBox(height: 16),
                Text(
                  '연장 종료 시각',
                  style: DanjiTypography.subtitleLarge,
                ),
                const SizedBox(height: 8),
                BookingDrumTimePicker(
                  catalog: catalog,
                  initialHourIndex: indices.$1,
                  initialMinuteIndex: indices.$2,
                  onChanged: (slot) {
                    draftHour = slot.hour;
                    draftMinute = slot.minute;
                    draftNextDay = slot.isNextDay;
                  },
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: DanjiColors.buttonBlue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '확인',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final picked = RentalExtensionPricing.endFromDrumSlot(
      endOptions: options,
      hour: draftHour,
      minute: draftMinute,
      isNextDay: draftNextDay,
    );
    if (picked != null) {
      setState(() => _selectedNewEnd = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeFmt = DateFormat('HH:mm');
    final dateTimeFmt = DateFormat('yyyy-MM-dd HH:mm');
    final won = NumberFormat('#,###');
    final presets = RentalExtensionPricing.presetValuesFor(_rentalType);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 8,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: DanjiColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '연장하기',
              style: DanjiTypography.subtitleLarge.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '현재 종료: ${timeFmt.format(_currentEnd)}',
              style: DanjiTypography.body.copyWith(
                color: DanjiColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              RentalExtensionPricing.sectionTitle(_rentalType),
              style: DanjiTypography.subtitle.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in presets)
                  _PresetChip(
                    label: RentalExtensionPricing.presetLabel(
                      _rentalType,
                      value,
                    ),
                    selected: _selectedNewEnd ==
                        RentalExtensionPricing.newEndForPreset(
                          rentalType: _rentalType,
                          currentEnd: _currentEnd,
                          presetValue: value,
                        ),
                    disabled: _isPresetDisabled(value),
                    onTap: () => _selectPreset(value),
                  ),
                _CustomSelectChip(onTap: _openCustomPicker),
              ],
            ),
            const SizedBox(height: 20),
            if (_selectedNewEnd != null) ...[
              Text(
                '종료 시각: ${dateTimeFmt.format(_selectedNewEnd!)}',
                style: DanjiTypography.body.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '추가 요금: ₩${won.format(_addedPrice)}',
                style: DanjiTypography.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: DanjiColors.buttonBlue,
                ),
              ),
              const SizedBox(height: 20),
            ],
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _selectedNewEnd == null
                    ? null
                    : () => Navigator.pop(context, _selectedNewEnd),
                style: FilledButton.styleFrom(
                  backgroundColor: DanjiColors.buttonBlue,
                  disabledBackgroundColor: DanjiColors.border,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  '연장 결제하기',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  const _PresetChip({
    required this.label,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = disabled
        ? DanjiColors.border.withValues(alpha: 0.35)
        : selected
            ? DanjiColors.buttonBlue.withValues(alpha: 0.12)
            : DanjiColors.surface;
    final fg = disabled
        ? DanjiColors.textSecondary.withValues(alpha: 0.5)
        : selected
            ? DanjiColors.buttonBlue
            : DanjiColors.textPrimary;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected && !disabled
                  ? DanjiColors.buttonBlue
                  : DanjiColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomSelectChip extends StatelessWidget {
  final VoidCallback onTap;

  const _CustomSelectChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DanjiColors.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: DanjiColors.border),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '직접 선택',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
