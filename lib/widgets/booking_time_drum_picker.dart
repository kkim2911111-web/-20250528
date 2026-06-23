import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/danji_colors.dart';
import '../theme/danji_typography.dart';
import '../utils/booking_time_slots.dart';

/// 쏘카 스타일 시·분 드럼 피커 (단일 시각)
class BookingDrumTimePicker extends StatefulWidget {
  final BookingDrumTimeCatalog catalog;
  final int initialHourIndex;
  final int initialMinuteIndex;
  final ValueChanged<({int hour, int minute, bool isNextDay})> onChanged;

  const BookingDrumTimePicker({
    super.key,
    required this.catalog,
    required this.initialHourIndex,
    required this.initialMinuteIndex,
    required this.onChanged,
  });

  @override
  State<BookingDrumTimePicker> createState() => _BookingDrumTimePickerState();
}

class _BookingDrumTimePickerState extends State<BookingDrumTimePicker> {
  late FixedExtentScrollController _hourController;
  late FixedExtentScrollController _minuteController;
  late int _hourIndex;
  late int _minuteIndex;
  bool _readyForCallbacks = false;

  @override
  void initState() {
    super.initState();
    _hourIndex = widget.initialHourIndex.clamp(
      0,
      (widget.catalog.hourOptions.length - 1).clamp(0, 999),
    );
    _minuteIndex = _clampMinuteIndex(_hourIndex, widget.initialMinuteIndex);
    _hourController = FixedExtentScrollController(initialItem: _hourIndex);
    _minuteController = FixedExtentScrollController(initialItem: _minuteIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _readyForCallbacks = true;
    });
  }

  @override
  void didUpdateWidget(covariant BookingDrumTimePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.catalog != widget.catalog) {
      _hourIndex = _hourIndex.clamp(0, widget.catalog.hourOptions.length - 1);
      _minuteIndex = _clampMinuteIndex(_hourIndex, _minuteIndex);
      _hourController.jumpToItem(_hourIndex);
      _minuteController.jumpToItem(_minuteIndex);
    }
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  int _clampMinuteIndex(int hourIndex, int minuteIndex) {
    final mins = widget.catalog.minutesPerHour[hourIndex];
    if (mins.isEmpty) return 0;
    return minuteIndex.clamp(0, mins.length - 1);
  }

  void _emit() {
    if (!_readyForCallbacks) return;
    final minute = widget.catalog.minutesPerHour[_hourIndex][_minuteIndex];
    final slot = widget.catalog.slotAt(_hourIndex, minute);
    if (slot != null) widget.onChanged(slot);
  }

  void _onHourChanged(int index) {
    setState(() {
      _hourIndex = index;
      _minuteIndex = _clampMinuteIndex(index, _minuteIndex);
    });
    _minuteController.jumpToItem(_minuteIndex);
    _emit();
  }

  void _onMinuteChanged(int index) {
    setState(() => _minuteIndex = index);
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.catalog.isEmpty) {
      return const SizedBox(
        height: 180,
        child: Center(child: Text('선택 가능한 시간이 없습니다')),
      );
    }

    return SizedBox(
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: 40,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: DanjiColors.buttonBlue.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: CupertinoPicker(
                  scrollController: _hourController,
                  magnification: 1.08,
                  squeeze: 1.05,
                  useMagnifier: true,
                  itemExtent: 40,
                  onSelectedItemChanged: _onHourChanged,
                  children: [
                    for (final h in widget.catalog.hourOptions)
                      Center(
                        child: Text(
                          BookingTimeSlots.formatDrumHourLabel(
                            h.hour,
                            isNextDay: h.isNextDay,
                          ),
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: CupertinoPicker(
                  scrollController: _minuteController,
                  magnification: 1.08,
                  squeeze: 1.05,
                  useMagnifier: true,
                  itemExtent: 40,
                  onSelectedItemChanged: _onMinuteChanged,
                  children: [
                    for (final m
                        in widget.catalog.minutesPerHour[_hourIndex])
                      Center(
                        child: Text(
                          m.toString().padLeft(2, '0'),
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 출고·반납(종료) 드럼 피커 바텀시트
class BookingTimeRangeDrumSheet extends StatefulWidget {
  final String leftTitle;
  final String rightTitle;
  final BookingDrumTimeCatalog startCatalog;
  final BookingDrumTimeCatalog Function(int startHour, int startMinute)
      endCatalogBuilder;
  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;
  final bool endIsNextDay;

  const BookingTimeRangeDrumSheet({
    super.key,
    required this.leftTitle,
    required this.rightTitle,
    required this.startCatalog,
    required this.endCatalogBuilder,
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
    this.endIsNextDay = false,
  });

  @override
  State<BookingTimeRangeDrumSheet> createState() =>
      _BookingTimeRangeDrumSheetState();
}

class _BookingTimeRangeDrumSheetState extends State<BookingTimeRangeDrumSheet> {
  late int _startHour;
  late int _startMinute;
  late int _endHour;
  late int _endMinute;
  late bool _endIsNextDay;

  late BookingDrumTimeCatalog _endCatalog;

  @override
  void initState() {
    super.initState();
    _applyInitialStartTime();
    _endHour = widget.endHour;
    _endMinute = widget.endMinute;
    _endIsNextDay = widget.endIsNextDay;
    _endCatalog = widget.endCatalogBuilder(_startHour, _startMinute);
    _refreshEndCatalog();
  }

  /// 카탈로그에 없는 시작 시각이면 현재 시각 10분 올림 슬롯으로 맞춤
  void _applyInitialStartTime() {
    final catalog = widget.startCatalog;
    if (catalog.isEmpty) {
      _startHour = widget.startHour;
      _startMinute = widget.startMinute;
      return;
    }

    if (catalog.containsSlot(
      hour: widget.startHour,
      minute: widget.startMinute,
    )) {
      _startHour = widget.startHour;
      _startMinute = widget.startMinute;
      return;
    }

    final ceiled = BookingTimeSlots.ceilToNextSlot(DateTime.now());
    if (catalog.containsSlot(hour: ceiled.hour, minute: ceiled.minute)) {
      _startHour = ceiled.hour;
      _startMinute = ceiled.minute;
      return;
    }

    final h0 = catalog.hourOptions.first;
    _startHour = h0.hour;
    _startMinute = catalog.minutesPerHour.first.first;
  }

  void _onStartChanged(({int hour, int minute, bool isNextDay}) slot) {
    if (slot.hour == _startHour && slot.minute == _startMinute) return;
    setState(() {
      _startHour = slot.hour;
      _startMinute = slot.minute;
      _refreshEndCatalog();
    });
  }

  void _onEndChanged(({int hour, int minute, bool isNextDay}) slot) {
    if (slot.hour == _endHour &&
        slot.minute == _endMinute &&
        slot.isNextDay == _endIsNextDay) {
      return;
    }
    setState(() {
      _endHour = slot.hour;
      _endMinute = slot.minute;
      _endIsNextDay = slot.isNextDay;
    });
  }

  void _refreshEndCatalog() {
    _endCatalog = widget.endCatalogBuilder(_startHour, _startMinute);
    if (_endCatalog.isEmpty) return;
    if (!_endCatalog.containsSlot(
      hour: _endHour,
      minute: _endMinute,
      isNextDay: _endIsNextDay,
    )) {
      final h0 = _endCatalog.hourOptions.first;
      _endHour = h0.hour;
      _endMinute = _endCatalog.minutesPerHour.first.first;
      _endIsNextDay = h0.isNextDay;
    }
  }

  (int, int) get _startIndices {
    final i = widget.startCatalog.indicesFor(
      hour: _startHour,
      minute: _startMinute,
    );
    return i;
  }

  (int, int) get _endIndices {
    final i = _endCatalog.indicesFor(
      hour: _endHour,
      minute: _endMinute,
      isNextDay: _endIsNextDay,
    );
    return i;
  }

  @override
  Widget build(BuildContext context) {
    final startIdx = _startIndices;
    final endIdx = _endIndices;

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
            Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        widget.leftTitle,
                        style: DanjiTypography.subtitle.copyWith(fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      BookingDrumTimePicker(
                        key: ValueKey(
                          'start-${_startHour}:${_startMinute}',
                        ),
                        catalog: widget.startCatalog,
                        initialHourIndex: startIdx.$1,
                        initialMinuteIndex: startIdx.$2,
                        onChanged: _onStartChanged,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        widget.rightTitle,
                        style: DanjiTypography.subtitle.copyWith(fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      BookingDrumTimePicker(
                        key: ValueKey(
                          'end-$_endHour:$_endMinute:$_endIsNextDay',
                        ),
                        catalog: _endCatalog,
                        initialHourIndex: endIdx.$1,
                        initialMinuteIndex: endIdx.$2,
                        onChanged: _onEndChanged,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _endCatalog.isEmpty
                    ? null
                    : () {
                        Navigator.pop(context, (
                          startHour: _startHour,
                          startMinute: _startMinute,
                          endHour: _endHour,
                          endMinute: _endMinute,
                          endIsNextDay: _endIsNextDay,
                        ));
                      },
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
  }
}

Future<
    ({
      int startHour,
      int startMinute,
      int endHour,
      int endMinute,
      bool endIsNextDay,
    })?> showBookingTimeRangeDrumPicker({
  required BuildContext context,
  required String leftTitle,
  required String rightTitle,
  required BookingDrumTimeCatalog startCatalog,
  required BookingDrumTimeCatalog Function(int startHour, int startMinute)
      endCatalogBuilder,
  required int startHour,
  required int startMinute,
  required int endHour,
  required int endMinute,
  bool endIsNextDay = false,
}) {
  return showModalBottomSheet<
      ({
        int startHour,
        int startMinute,
        int endHour,
        int endMinute,
        bool endIsNextDay,
      })?>(
    context: context,
    backgroundColor: DanjiColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => BookingTimeRangeDrumSheet(
      leftTitle: leftTitle,
      rightTitle: rightTitle,
      startCatalog: startCatalog,
      endCatalogBuilder: endCatalogBuilder,
      startHour: startHour,
      startMinute: startMinute,
      endHour: endHour,
      endMinute: endMinute,
      endIsNextDay: endIsNextDay,
    ),
  );
}

/// 출고 시각만 (단일 컬럼 드럼)
Future<({int hour, int minute})?> showBookingStartDrumPicker({
  required BuildContext context,
  required BookingDrumTimeCatalog startCatalog,
  required int startHour,
  required int startMinute,
}) async {
  final indices = startCatalog.indicesFor(
    hour: startHour,
    minute: startMinute,
  );
  var draftHour = startHour;
  var draftMinute = startMinute;

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
              Text('출고 시각', style: DanjiTypography.subtitleLarge),
              const SizedBox(height: 8),
              BookingDrumTimePicker(
                catalog: startCatalog,
                initialHourIndex: indices.$1,
                initialMinuteIndex: indices.$2,
                onChanged: (slot) {
                  draftHour = slot.hour;
                  draftMinute = slot.minute;
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

  if (confirmed != true) return null;
  return (hour: draftHour, minute: draftMinute);
}
