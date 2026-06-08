import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/staff_profile.dart';
import '../../services/admin_service.dart';
import '../../utils/admin_conflict.dart' as conflict;
import '../../utils/reservation_display.dart';
import '../../theme/danji_colors.dart';
import '../../utils/danji_snackbar.dart';
import '../../widgets/admin_scaffold.dart';
import '../../widgets/danji_app_bar.dart';
import '../../widgets/admin_reservation_card_extras.dart';
import '../../widgets/section_card.dart';

enum _ReservationFilter { all, inUse, waiting, conflict, completed }

class _AdminReservationLists {
  final List<Map<String, dynamic>> active;
  final List<Map<String, dynamic>> completed;

  const _AdminReservationLists({
    required this.active,
    required this.completed,
  });
}

class AdminReservationListScreen extends StatefulWidget {
  final bool openConflictTab;
  final bool openInUseTab;
  final bool openWaitingTab;

  const AdminReservationListScreen({
    super.key,
    this.openConflictTab = false,
    this.openInUseTab = false,
    this.openWaitingTab = false,
  });

  @override
  State<AdminReservationListScreen> createState() =>
      _AdminReservationListScreenState();
}

class _AdminReservationListScreenState
    extends State<AdminReservationListScreen> {
  final _admin = AdminService();
  final _dateTime = DateFormat('yyyy-MM-dd HH:mm');
  final _timeOnly = DateFormat('HH:mm');
  final _won = NumberFormat('#,###');

  _ReservationFilter _filter = _ReservationFilter.all;
  Future<_AdminReservationLists>? _future;

  late int _year = DateTime.now().year;
  late int _month = DateTime.now().month;
  DateTime? _filterDay;
  static final _dayLabel = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    if (widget.openInUseTab) {
      _filter = _ReservationFilter.inUse;
    } else if (widget.openWaitingTab) {
      _filter = _ReservationFilter.waiting;
    } else if (widget.openConflictTab) {
      _filter = _ReservationFilter.conflict;
    }
    _reload();
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<_AdminReservationLists> _load() async {
    final results = await Future.wait([
      _admin.getAdminReservationsWithConflict(),
      _admin.getAdminCompletedReservations(),
    ]);
    return _AdminReservationLists(
      active: results[0],
      completed: results[1],
    );
  }

  void _syncFilterDayWithMonth() {
    final d = _filterDay;
    if (d == null) return;
    if (d.year != _year || d.month != _month) {
      _filterDay = null;
    }
  }

  void _shiftMonth(int delta) {
    setState(() {
      var m = _month + delta;
      var y = _year;
      while (m < 1) {
        m += 12;
        y--;
      }
      while (m > 12) {
        m -= 12;
        y++;
      }
      _year = y;
      _month = m;
      _syncFilterDayWithMonth();
    });
  }

  Future<void> _pickFilterDay() async {
    final monthStart = DateTime(_year, _month, 1);
    final monthEnd = DateTime(_year, _month + 1, 0);
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterDay ?? monthStart,
      firstDate: monthStart,
      lastDate: monthEnd,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _filterDay = DateTime(picked.year, picked.month, picked.day);
    });
  }

  DateTime? _rowPeriodAnchor(
    Map<String, dynamic> row, {
    required bool completedTab,
  }) {
    if (completedTab) {
      return _parseDate(row['sort_at']) ?? _parseDate(row['start_at']);
    }
    return _parseDate(row['start_at']);
  }

  List<Map<String, dynamic>> _applyPeriodFilter(
    List<Map<String, dynamic>> rows, {
    required bool completedTab,
  }) {
    return rows.where((row) {
      final anchor = _rowPeriodAnchor(row, completedTab: completedTab);
      if (anchor == null) return _filterDay == null;

      final local = anchor.toLocal();
      if (local.year != _year || local.month != _month) return false;

      final day = _filterDay;
      if (day == null) return true;
      return local.year == day.year &&
          local.month == day.month &&
          local.day == day.day;
    }).toList();
  }

  List<Map<String, dynamic>> _applyTabFilter(_AdminReservationLists data) {
    if (_filter == _ReservationFilter.completed) {
      return List<Map<String, dynamic>>.from(data.completed);
    }

    final rows = data.active;
    switch (_filter) {
      case _ReservationFilter.inUse:
        return rows.where(_isInProgressTabRow).toList();
      case _ReservationFilter.waiting:
        return rows.where(_isScheduledTabRow).toList();
      case _ReservationFilter.conflict:
        return rows.where(conflict.isBackToBackConflictRow).toList();
      case _ReservationFilter.all:
      case _ReservationFilter.completed:
        return rows;
    }
  }

  List<Map<String, dynamic>> _applyFilter(_AdminReservationLists data) {
    final tabbed = _applyTabFilter(data);
    return _applyPeriodFilter(
      tabbed,
      completedTab: _filter == _ReservationFilter.completed,
    );
  }

  Widget _buildPeriodFilterBar() {
    final monthTitle = '$_year년 $_month월';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        children: [
          SectionCard(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => _shiftMonth(-1),
                  icon: const Icon(Icons.chevron_left),
                  color: DanjiColors.buttonBlue,
                ),
                Expanded(
                  child: Text(
                    monthTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _shiftMonth(1),
                  icon: const Icon(Icons.chevron_right),
                  color: DanjiColors.buttonBlue,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SectionCard(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickFilterDay,
                    icon: const Icon(Icons.calendar_today_outlined, size: 16),
                    label: Text(
                      _filterDay == null
                          ? '날짜 선택'
                          : _dayLabel.format(_filterDay!),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: DanjiColors.buttonBlue,
                      side: const BorderSide(color: DanjiColors.buttonBlue),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                if (_filterDay != null) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => setState(() => _filterDay = null),
                    child: const Text('초기화'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmForceReturn(Map<String, dynamic> row) async {
    final id = _reservationId(row);
    if (id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('강제 반납'),
        content: const Text(
          '대여 중인 예약을 반납 처리하여 반납 검수 화면으로 이동합니다.\n'
          '계속하시겠습니까?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('닫기'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('강제 반납'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _admin.forceReturnReservation(id);
      if (!mounted) return;
      DanjiSnackBar.show(context, '반납 검수 대기로 이동했습니다');
      _reload();
    } catch (e) {
      if (!mounted) return;
      DanjiSnackBar.show(context, friendlyAdminError(e));
    }
  }

  Future<void> _confirmForcePaymentCancel(Map<String, dynamic> row) async {
    final id = _reservationId(row);
    if (id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('강제결제취소'),
        content: const Text(
          '결제를 환불하고 예약을 취소 상태로 변경합니다.\n'
          '차량은 즉시 이용 가능으로 전환됩니다.\n'
          '계속하시겠습니까?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('닫기'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: DanjiColors.accentRed,
            ),
            child: const Text('강제결제취소'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _admin.forcePaymentCancelReservation(id);
      if (!mounted) return;
      DanjiSnackBar.show(context, '결제 취소 및 환불 처리되었습니다');
      _reload();
    } catch (e) {
      if (!mounted) return;
      DanjiSnackBar.show(context, friendlyAdminError(e));
    }
  }

  int _conflictCount(_AdminReservationLists? data) {
    if (data == null) return 0;
    return conflict.countBackToBackConflicts(data.active);
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      appBar: const DanjiAppBar(title: '대여 관리'),
      body: FutureBuilder<_AdminReservationLists>(
        future: _future,
        builder: (context, snap) {
          final conflictCount = _conflictCount(snap.data);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      children: [
                      _FilterChip(
                        label: '전체',
                        selected: _filter == _ReservationFilter.all,
                        onTap: () =>
                            setState(() => _filter = _ReservationFilter.all),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: '진행중',
                        selected: _filter == _ReservationFilter.inUse,
                        onTap: () =>
                            setState(() => _filter = _ReservationFilter.inUse),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: '예정',
                        selected: _filter == _ReservationFilter.waiting,
                        onTap: () => setState(
                          () => _filter = _ReservationFilter.waiting,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: '충돌위험',
                        selected: _filter == _ReservationFilter.conflict,
                        badgeCount: conflictCount,
                        onTap: () => setState(
                          () => _filter = _ReservationFilter.conflict,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: '완료',
                        selected: _filter == _ReservationFilter.completed,
                        onTap: () => setState(
                          () => _filter = _ReservationFilter.completed,
                        ),
                      ),
                    ],
                    ),
                  ),
                ),
              ),
              _buildPeriodFilterBar(),
              Expanded(
                child: RefreshIndicator(
                  color: DanjiColors.buttonBlue,
                  onRefresh: () async => _reload(),
                  child: _buildReservationList(snap),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildReservationList(
    AsyncSnapshot<_AdminReservationLists> snap,
  ) {
    if (snap.connectionState == ConnectionState.waiting) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (snap.hasError) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          Text(friendlyAdminError(snap.error!)),
        ],
      );
    }
    final filtered = _applyFilter(snap.data!);
    if (filtered.isEmpty) {
      final hasData = snap.data!.active.isNotEmpty ||
          snap.data!.completed.isNotEmpty;
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: hasData ? 80 : 40),
          Center(
            child: Text(
              hasData ? '조건에 맞는 예약이 없습니다.' : '표시할 예약이 없습니다.',
            ),
          ),
        ],
      );
    }
    final isCompletedTab = _filter == _ReservationFilter.completed;

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final row = filtered[index];
        if (isCompletedTab) {
          return _CompletedReservationCard(
            row: row,
            dateTime: _dateTime,
            won: _won,
            admin: _admin,
          );
        }
        final isNoShowSuspect = _isNoShowSuspect(row);
        final isBackToBack = conflict.isBackToBackConflictRow(row);
        final status = _status(row);

        return _ReservationCard(
          row: row,
          dateTime: _dateTime,
          timeOnly: _timeOnly,
          won: _won,
          enableConflictSwipe:
              _filter == _ReservationFilter.conflict && isBackToBack,
          showConflictHighlight: isBackToBack,
          showNoShowSuspect: isNoShowSuspect,
          onForceReturn: () => _confirmForceReturn(row),
          onForcePaymentCancel:
              status == 'confirmed' || status == 'in_use'
                  ? () => _confirmForcePaymentCancel(row)
                  : null,
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badgeCount;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final chip = Material(
      color: selected ? DanjiColors.buttonBlue : DanjiColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            16,
            10,
            badgeCount > 0 ? 22 : 16,
            10,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? DanjiColors.buttonBlue : DanjiColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : DanjiColors.textPrimary,
            ),
          ),
        ),
      ),
    );

    if (badgeCount < 1) return chip;

    final badgeLabel = badgeCount > 99 ? '99+' : '$badgeCount';

    return Stack(
      clipBehavior: Clip.none,
      children: [
        chip,
        Positioned(
          right: 0,
          top: -8,
          child: Container(
            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: DanjiColors.accentRed,
              shape: BoxShape.circle,
              border: Border.all(color: DanjiColors.background, width: 1.5),
            ),
            alignment: Alignment.center,
            child: Text(
              badgeLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CompletedReservationCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final DateFormat dateTime;
  final NumberFormat won;
  final AdminService admin;

  const _CompletedReservationCard({
    required this.row,
    required this.dateTime,
    required this.won,
    required this.admin,
  });

  @override
  Widget build(BuildContext context) {
    final vehicleName = _str(row, 'vehicle_name') ?? '차량';
    final carNumber = _str(row, 'car_number');
    final renterName = AdminReservationRow.resolveRenterDisplayName(
      directRenterName: _str(row, 'renter_name'),
    );
    final start = displayRentalStartFromMap(row);
    final end = displayRentalEndFromMap(row);
    final totalPrice = (row['total_price'] as num?)?.toInt() ?? 0;
    final reservationId = _reservationId(row);
    final secondDriverName = _str(row, 'second_driver_name');
    final secondDriverLicense = _str(row, 'second_driver_license');
    final hasSecondDriver =
        adminHasSecondDriver(secondDriverName: secondDriverName);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SectionCard.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DanjiColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  vehicleName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: DanjiColors.textPrimary,
                  ),
                ),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (hasSecondDriver)
                    GestureDetector(
                      onTap: () => showAdminSecondDriverInfoSheet(
                        context,
                        secondDriverName: secondDriverName,
                        secondDriverLicense: secondDriverLicense,
                      ),
                      child: const AdminSecondDriverBadge(),
                    ),
                  _CompletedTabStatusBadge(row: row),
                ],
              ),
            ],
          ),
          if (carNumber != null && carNumber.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              carNumber,
              style: const TextStyle(color: DanjiColors.textSecondary),
            ),
          ],
          const SizedBox(height: 8),
          _ReservationRenterSummary(
            row: row,
            won: won,
            renterName: renterName,
            totalPrice: totalPrice,
          ),
          AdminSecondDriverSummary(
            secondDriverName: secondDriverName,
            secondDriverLicense: secondDriverLicense,
            padding: const EdgeInsets.only(top: 6),
          ),
          const SizedBox(height: 6),
          Text(
            '${_formatOptionalDateTime(dateTime, start)} ~ '
            '${_formatOptionalDateTime(dateTime, end)}',
            style: const TextStyle(
              color: DanjiColors.textSecondary,
              height: 1.4,
            ),
          ),
          if (reservationId != null) ...[
            const SizedBox(height: 8),
            Text(
              '예약 ${_reservationNumberLabel(row)}',
              style: const TextStyle(
                color: DanjiColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (reservationId != null) ...[
            const SizedBox(height: 12),
            AdminReservationContractButton(
              admin: admin,
              reservationId: reservationId,
              vehicleName: vehicleName,
              renterName: renterName,
              secondDriverName: secondDriverName,
              secondDriverLicense: secondDriverLicense,
              rentalPeriodOverride: formatRentalPeriod(
                formatter: dateTime,
                start: displayRentalStartFromMap(row),
                end: displayRentalEndFromMap(row),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReservationCard extends StatefulWidget {
  final Map<String, dynamic> row;
  final DateFormat dateTime;
  final DateFormat timeOnly;
  final NumberFormat won;
  final bool enableConflictSwipe;
  final bool showConflictHighlight;
  final bool showNoShowSuspect;
  final VoidCallback onForceReturn;
  final VoidCallback? onForcePaymentCancel;

  const _ReservationCard({
    required this.row,
    required this.dateTime,
    required this.timeOnly,
    required this.won,
    this.enableConflictSwipe = false,
    this.showConflictHighlight = false,
    this.showNoShowSuspect = false,
    required this.onForceReturn,
    this.onForcePaymentCancel,
  });

  @override
  State<_ReservationCard> createState() => _ReservationCardState();
}

class _ReservationCardState extends State<_ReservationCard> {
  bool _showNextReservation = false;

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final conflict = widget.showConflictHighlight;
    final canSwipe =
        widget.enableConflictSwipe && _hasNextReservationInfo(row);
    final vehicleName = _str(row, 'vehicle_name') ?? '차량';
    final carNumber = _str(row, 'car_number');
    final status = _status(row);
    final start = displayRentalStartFromMap(row);
    final end = displayRentalEndFromMap(row);
    final nextStart = _parseDate(row['next_start_at']);
    final secondDriverName = _str(row, 'second_driver_name');
    final secondDriverLicense = _str(row, 'second_driver_license');
    final hasSecondDriver =
        adminHasSecondDriver(secondDriverName: secondDriverName);

    final cardBody = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: _showNextReservation && canSwipe
          ? _NextReservationPanel(
              key: const ValueKey('next'),
              row: row,
              dateTime: widget.dateTime,
            )
          : _CurrentReservationPanel(
              key: const ValueKey('current'),
              vehicleName: vehicleName,
              carNumber: carNumber,
              status: status,
              row: row,
              won: widget.won,
              start: start,
              end: end,
              nextStart: nextStart,
              dateTime: widget.dateTime,
              timeOnly: widget.timeOnly,
              conflict: conflict,
              showNoShowSuspect: widget.showNoShowSuspect,
              onForceReturn: widget.onForceReturn,
              onForcePaymentCancel: widget.onForcePaymentCancel,
              secondDriverName: secondDriverName,
              secondDriverLicense: secondDriverLicense,
              hasSecondDriver: hasSecondDriver,
            ),
    );

    return GestureDetector(
      onHorizontalDragEnd: canSwipe
          ? (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity < -120) {
                setState(() => _showNextReservation = true);
              } else if (velocity > 120) {
                setState(() => _showNextReservation = false);
              }
            }
          : null,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: SectionCard.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: conflict ? DanjiColors.accentRed : DanjiColors.border,
            width: conflict ? 2 : 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            cardBody,
            if (canSwipe) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _SwipeDot(active: !_showNextReservation),
                  const SizedBox(width: 6),
                  _SwipeDot(active: _showNextReservation),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                _showNextReservation ? '← 스와이프: 현재 예약' : '스와이프: 다음 예약자 →',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: DanjiColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SwipeDot extends StatelessWidget {
  final bool active;

  const _SwipeDot({required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? DanjiColors.buttonBlue : DanjiColors.border,
      ),
    );
  }
}

class _NoShowSuspectBadge extends StatelessWidget {
  const _NoShowSuspectBadge();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3E0),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: const Color(0xFFFF6D00).withValues(alpha: 0.65),
            width: 1.2,
          ),
        ),
        child: const Text(
          '노쇼의심',
          style: TextStyle(
            color: Color(0xFFE65100),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _CurrentReservationPanel extends StatelessWidget {
  final String vehicleName;
  final String? carNumber;
  final String status;
  final Map<String, dynamic> row;
  final NumberFormat won;
  final DateTime? start;
  final DateTime? end;
  final DateTime? nextStart;
  final DateFormat dateTime;
  final DateFormat timeOnly;
  final bool conflict;
  final bool showNoShowSuspect;
  final VoidCallback onForceReturn;
  final VoidCallback? onForcePaymentCancel;
  final String? secondDriverName;
  final String? secondDriverLicense;
  final bool hasSecondDriver;

  const _CurrentReservationPanel({
    super.key,
    required this.vehicleName,
    required this.carNumber,
    required this.status,
    required this.row,
    required this.won,
    required this.start,
    required this.end,
    required this.nextStart,
    required this.dateTime,
    required this.timeOnly,
    required this.conflict,
    this.showNoShowSuspect = false,
    required this.onForceReturn,
    this.onForcePaymentCancel,
    this.secondDriverName,
    this.secondDriverLicense,
    this.hasSecondDriver = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                vehicleName,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: DanjiColors.textPrimary,
                ),
              ),
            ),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (hasSecondDriver)
                  GestureDetector(
                    onTap: () => showAdminSecondDriverInfoSheet(
                      context,
                      secondDriverName: secondDriverName,
                      secondDriverLicense: secondDriverLicense,
                    ),
                    child: const AdminSecondDriverBadge(),
                  ),
                _StatusBadge(status: status),
                if (showNoShowSuspect) const _NoShowSuspectBadge(),
              ],
            ),
          ],
        ),
        if (carNumber != null && carNumber!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            carNumber!,
            style: const TextStyle(color: DanjiColors.textSecondary),
          ),
        ],
        const SizedBox(height: 8),
        _ReservationRenterSummary(
          row: row,
          won: won,
          renterName: AdminReservationRow.resolveRenterDisplayName(
            directRenterName: _str(row, 'renter_name'),
          ),
          totalPrice: (row['total_price'] as num?)?.toInt() ?? 0,
        ),
        AdminSecondDriverSummary(
          secondDriverName: secondDriverName,
          secondDriverLicense: secondDriverLicense,
          padding: const EdgeInsets.only(top: 6),
        ),
        const SizedBox(height: 6),
        Text(
          '${_formatOptionalDateTime(dateTime, start)} ~ '
          '${_formatOptionalDateTime(dateTime, end)}',
          style: const TextStyle(
            color: DanjiColors.textSecondary,
            height: 1.4,
          ),
        ),
        if (_reservationId(row) != null) ...[
          const SizedBox(height: 8),
          Text(
            '예약 ${_reservationNumberLabel(row)}',
            style: const TextStyle(
              color: DanjiColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (nextStart != null) ...[
          const SizedBox(height: 6),
          Text(
            '다음예약: ${timeOnly.format(nextStart!)}',
            style: const TextStyle(
              color: DanjiColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
        if (conflict) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF0F0),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '⚠️ 충돌위험',
              style: TextStyle(
                color: DanjiColors.accentRed,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton(
                onPressed: status == 'in_use' ? onForceReturn : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFE65100),
                  side: const BorderSide(color: Color(0xFFE65100)),
                  disabledForegroundColor: DanjiColors.textMuted,
                  disabledBackgroundColor: DanjiColors.surface,
                ),
                child: const Text('강제 반납'),
              ),
              if (onForcePaymentCancel != null)
                OutlinedButton(
                  onPressed: onForcePaymentCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: DanjiColors.accentRed,
                    side: const BorderSide(color: DanjiColors.accentRed),
                  ),
                  child: const Text('강제결제취소'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NextReservationPanel extends StatelessWidget {
  final Map<String, dynamic> row;
  final DateFormat dateTime;

  const _NextReservationPanel({
    super.key,
    required this.row,
    required this.dateTime,
  });

  @override
  Widget build(BuildContext context) {
    final nextStart = _parseDate(row['next_start_at']);
    final nextName = AdminReservationRow.resolveRenterDisplayName(
      directRenterName: _str(row, 'next_renter_name'),
    );
    final nextPhone = _renterPhoneLabel(row, phoneKey: 'next_renter_phone');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '다음 예약자',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: DanjiColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '이름: $nextName',
          style: const TextStyle(
            color: DanjiColors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '전화번호: $nextPhone',
          style: const TextStyle(
            color: DanjiColors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '예약 시작: ${_formatOptionalDateTime(dateTime, nextStart)}',
          style: const TextStyle(
            color: DanjiColors.textPrimary,
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _ReservationRenterSummary extends StatelessWidget {
  final Map<String, dynamic> row;
  final NumberFormat won;
  final String renterName;
  final int totalPrice;

  const _ReservationRenterSummary({
    required this.row,
    required this.won,
    required this.renterName,
    required this.totalPrice,
  });

  @override
  Widget build(BuildContext context) {
    final phone = _renterPhoneLabel(row);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '임차인: $renterName',
          style: const TextStyle(
            color: DanjiColors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '전화번호: $phone',
          style: const TextStyle(
            color: DanjiColors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '결제 금액: ₩${won.format(totalPrice)}',
          style: const TextStyle(
            color: DanjiColors.textPrimary,
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _CompletedTabStatusBadge extends StatelessWidget {
  final Map<String, dynamic> row;

  const _CompletedTabStatusBadge({required this.row});

  @override
  Widget build(BuildContext context) {
    if (_isNoShowCompleted(row)) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3E0),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFFFF6D00).withValues(alpha: 0.45),
          ),
        ),
        child: const Text(
          '노쇼완료',
          style: TextStyle(
            color: Color(0xFFE65100),
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      );
    }

    return const _StatusBadge(status: 'completed');
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = _style(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  (String, Color, Color) _style(String status) {
    switch (status) {
      case 'in_use':
        return ('대여중', const Color(0xFFFFF3E0), const Color(0xFFFB8C00));
      case 'returning':
        return ('반납중', const Color(0xFFFFF8E1), const Color(0xFFF9A825));
      case 'returned':
        return ('반납완료', const Color(0xFFE8F5E9), const Color(0xFF43A047));
      case 'confirmed':
        return ('이용대기', DanjiColors.skyLight, DanjiColors.buttonBlue);
      case 'pending':
        return ('대기', const Color(0xFFF2F4F6), DanjiColors.textSecondary);
      case 'completed':
        return ('완료', const Color(0xFFE8F5E9), const Color(0xFF2E7D32));
      case 'cancelled':
        return ('취소', const Color(0xFFF2F4F6), DanjiColors.textSecondary);
      default:
        return (status, const Color(0xFFF2F4F6), DanjiColors.textSecondary);
    }
  }
}

String _formatOptionalDateTime(DateFormat format, DateTime? value) {
  if (value == null) return '-';
  return format.format(value);
}

String _renterPhoneLabel(
  Map<String, dynamic> row, {
  String phoneKey = 'renter_phone',
}) {
  final phone = _str(row, phoneKey);
  if (phone != null && phone != '미등록') return phone;
  return '미등록';
}

bool _hasNextReservationInfo(Map<String, dynamic> row) {
  return _parseDate(row['next_start_at']) != null ||
      _str(row, 'next_renter_name') != null ||
      _str(row, 'next_renter_phone') != null;
}

bool _isNoShowSuspect(Map<String, dynamic> row) {
  if (_status(row) != 'confirmed') return false;
  final start = _parseDate(row['start_at']);
  if (start == null) return false;
  return !start.isAfter(DateTime.now());
}

bool _isInProgressTabRow(Map<String, dynamic> row) {
  final status = _status(row);
  if (status == 'in_use') return true;
  return _isNoShowSuspect(row);
}

bool _isScheduledTabRow(Map<String, dynamic> row) {
  if (_status(row) != 'confirmed') return false;
  final start = _parseDate(row['start_at']);
  if (start == null) return false;
  return start.isAfter(DateTime.now());
}

bool _isNoShowCompleted(Map<String, dynamic> row) {
  return row['is_no_show'] == true;
}

String? _str(Map<String, dynamic> row, String key) {
  final v = row[key];
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

String? _reservationId(Map<String, dynamic> row) =>
    _str(row, 'reservation_id') ?? _str(row, 'id');

String _reservationNumberLabel(Map<String, dynamic> row) {
  final id = _reservationId(row);
  if (id == null) return '—';
  return resolveReservationNumberLabel(
    reservationNumber: _str(row, 'reservation_number'),
    rawId: id,
  );
}

String _status(Map<String, dynamic> row) =>
    _str(row, 'status')?.toLowerCase() ?? '';

DateTime? _parseDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value.toLocal();
  return DateTime.tryParse(value.toString())?.toLocal();
}
