import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/grouped_reservations.dart';
import '../models/reservation.dart';
import '../services/rental_service.dart';
import '../services/reservation_refresh_bus.dart';
import '../theme/danji_colors.dart';
import '../theme/danji_theme.dart';
import '../theme/danji_typography.dart';
import '../widgets/danji_app_bar.dart';
import '../utils/cancel_refund_policy.dart';
import '../widgets/reservation_cancel_dialog.dart';
import 'support_pages.dart';
import '../widgets/reservation_price_display.dart';
import '../utils/rental_navigation.dart';
import '../utils/reservation_display.dart';
import 'rental_contract_screen.dart';
import '../models/reservation_payment_pricing.dart';
class MyReservationsScreen extends StatefulWidget {
  /// true: 마이페이지 이용내역 (종료된 예약만)
  final bool historyOnly;

  /// true: 화면 진입 시 목록을 await까지 포함해 강제 새로고침
  final bool forceRefreshOnOpen;

  const MyReservationsScreen({
    super.key,
    this.historyOnly = false,
    this.forceRefreshOnOpen = false,
  });

  @override
  State<MyReservationsScreen> createState() => _MyReservationsScreenState();
}

enum _HistoryTab { all, completed, cancelled }

class _MyReservationsScreenState extends State<MyReservationsScreen> {
  final _service = RentalService();
  final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');
  final _monthHeaderFormat = DateFormat('yyyy년 M월');
  final _won = NumberFormat('#,###');

  Future<GroupedReservations>? _future;
  int _listKey = 0;
  final _hiddenIds = <String>{};
  late DateTime _selectedMonth;
  _HistoryTab _historyTab = _HistoryTab.all;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
    ReservationRefreshBus.instance.version.addListener(_onExternalRefresh);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reloadAndWait());
  }

  bool get _canGoNextMonth {
    final now = DateTime.now();
    return _selectedMonth.year < now.year ||
        (_selectedMonth.year == now.year &&
            _selectedMonth.month < now.month);
  }

  void _shiftMonth(int delta) {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + delta,
      );
    });
  }

  DateTime? _historyAnchorDate(Reservation reservation) {
    if (reservation.isCancelled) {
      return reservation.cancelledAt ??
          reservation.startAt ??
          reservation.endAt;
    }
    return reservation.startAt ??
        reservation.endAt ??
        reservation.returnedAt;
  }

  bool _reservationInSelectedMonth(Reservation reservation) {
    final dt = _historyAnchorDate(reservation);
    if (dt == null) return false;
    return dt.year == _selectedMonth.year &&
        dt.month == _selectedMonth.month;
  }

  List<Reservation> _filterHistoryByTab(List<Reservation> list) {
    switch (_historyTab) {
      case _HistoryTab.all:
        return list;
      case _HistoryTab.completed:
        return list.where((r) => r.isUsageHistoryCompleted).toList();
      case _HistoryTab.cancelled:
        return list.where((r) => r.isCancelled).toList();
    }
  }

  ReservationPaymentPricing? _pricingFor(
    GroupedReservations grouped,
    Reservation item,
  ) {
    final map = grouped.paymentPricing;
    final byId = map[item.id];
    if (byId != null) return byId;
    final oid = item.orderId?.trim();
    if (oid != null && oid.isNotEmpty) {
      return map[oid];
    }
    return null;
  }

  GroupedReservations _filterFinishedByMonth(GroupedReservations grouped) {
    final finished = _filterHistoryByTab(grouped.finished)
        .where(_reservationInSelectedMonth)
        .toList();
    return GroupedReservations(
      operating: grouped.operating,
      waiting: grouped.waiting,
      finished: finished,
      paymentPricing: grouped.paymentPricing,
    );
  }

  @override
  void dispose() {
    ReservationRefreshBus.instance.version.removeListener(_onExternalRefresh);
    super.dispose();
  }

  void _onExternalRefresh() {
    if (!mounted) return;
    _reload();
  }

  void _reload() {
    setState(() {
      _listKey++;
      _future = _service.fetchGroupedReservations(
        historyOnly: widget.historyOnly,
        forceRefresh: true,
      );
    });
  }

  GroupedReservations _visible(GroupedReservations grouped) {
    if (_hiddenIds.isEmpty) return grouped;
    bool show(Reservation r) => !_hiddenIds.contains(r.id);
    return GroupedReservations(
      operating: grouped.operating.where(show).toList(),
      waiting: grouped.waiting.where(show).toList(),
      finished: grouped.finished.where(show).toList(),
      paymentPricing: grouped.paymentPricing,
    );
  }

  Future<void> _reloadAndWait() async {
    final next = _service.fetchGroupedReservations(
      historyOnly: widget.historyOnly,
      forceRefresh: widget.forceRefreshOnOpen,
    );
    setState(() {
      _listKey++;
      _future = next;
    });
    await next;
  }

  Future<void> _openStartRental(Reservation reservation) async {
    if (reservation.status != 'in_use' && reservation.isTooEarlyForRentalStart) {
      _showCancelSnack(RentalStartMessages.tooEarly);
      return;
    }
    final result = await openRentalOrUseScreen<bool>(context, reservation);
    if (result == true) _reload();
  }

  bool _showsRentalStartButton(Reservation item) =>
      item.showRentalStartButton || item.canUseVehicle;

  /// 이용완료(finished) 카드 — 취소 제외 항상 표시
  bool _showContractOnFinishedCard(Reservation item) =>
      item.status != 'cancelled';

  /// returned / completed / in_use
  bool _showContractByStatus(Reservation item) {
    if (item.status == 'cancelled') return false;
    const allowed = {'returned', 'completed', 'in_use'};
    return allowed.contains(item.status);
  }

  bool _showContractButton(Reservation item, {_CardVariant? variant}) {
    if (variant == _CardVariant.finished) {
      return _showContractOnFinishedCard(item);
    }
    return _showContractByStatus(item);
  }

  Future<void> _openContract(Reservation reservation) async {
    var content = reservation.hasContractContent
        ? reservation.contractContent!.trim()
        : null;

    if (content == null || content.isEmpty) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      try {
        content = await _service.ensureContractContent(reservation.id);
      } catch (e) {
        if (!mounted) return;
        Navigator.of(context).pop();
        _showCancelSnack(
          e.toString().replaceFirst('RentalException: ', ''),
        );
        return;
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    }

    if (!mounted) return;
    if (content == null || content.isEmpty) {
      _showCancelSnack('계약서를 불러오지 못했습니다.');
      return;
    }

    final period = formatRentalPeriod(
      formatter: DateFormat('yyyy-MM-dd HH:mm'),
      start: reservation.displayRentalStartAt,
      end: reservation.displayRentalEndAt,
    );

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RentalContractScreen(
          reservationId: reservation.id,
          vehicleName: reservation.vehicle?.name,
          initialContent: content,
          secondDriverName: reservation.secondDriverName,
          secondDriverLicense: reservation.secondDriverLicense,
          rentalPeriodOverride: period,
        ),
      ),
    );
  }

  Future<void> _openReturn(Reservation reservation) async {
    final result = await openRentalReturn<bool>(context, reservation);
    if (result == true) _reload();
  }

  Future<void> _onCancelTap(Reservation reservation) async {
    if (!reservation.canCancel) {
      _showCancelSnack('취소할 수 없는 예약입니다.');
      return;
    }
    await _cancelReservation(reservation);
  }

  void _showCancelSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(message),
      ),
    );
  }

  Future<void> _cancelReservation(Reservation reservation) async {
    CancelRefundQuote quote;
    try {
      quote = await _service.previewCancelRefund(reservation.id);
    } catch (e) {
      if (!mounted) return;
      _showCancelSnack(e.toString().replaceFirst('RentalException: ', ''));
      return;
    }

    if (!mounted) return;
    final confirmed = await showReservationCancelConfirmDialog(
      context,
      quote: quote,
    );
    if (!confirmed || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      setState(() {
        _hiddenIds.add(reservation.id);
      });
      final result = await _service.cancelReservation(reservation.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      await _reloadAndWait();
      if (!mounted) return;
      setState(() {
        _hiddenIds.remove(reservation.id);
      });
      final message = result['alreadyCancelled'] == true
          ? ReservationCancelMessages.alreadyCancelled
          : ReservationCancelMessages.success;
      _showCancelSnack(message);
    } catch (e) {
      if (isReservationAlreadyGoneError(e)) {
        if (!mounted) return;
        Navigator.of(context).pop();
        await _reloadAndWait();
        if (!mounted) return;
        setState(() => _hiddenIds.remove(reservation.id));
        _showCancelSnack(ReservationCancelMessages.alreadyCancelled);
        return;
      }
      if (mounted) {
        setState(() {
          _hiddenIds.remove(reservation.id);
        });
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      final msg = e.toString().replaceFirst('RentalException: ', '');
      _showCancelSnack(msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: DanjiAppBar(
        title: widget.historyOnly ? '이용내역' : '내 예약',
      ),
      body: RefreshIndicator(
        color: DanjiColors.buttonBlue,
        onRefresh: _reloadAndWait,
        child: FutureBuilder<GroupedReservations>(
          key: ValueKey(_listKey),
          future: _future,
          builder: (context, snap) {
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
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    snap.error.toString(),
                    style: const TextStyle(color: DanjiColors.accentRed),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _reload, child: const Text('다시 시도')),
                ],
              );
            }

            final groupedRaw = snap.data;
            if (groupedRaw == null) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  const Text(
                    '예약 목록을 불러오지 못했습니다.',
                    style: TextStyle(color: DanjiColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _reload, child: const Text('다시 시도')),
                ],
              );
            }

            final grouped = widget.historyOnly
                ? _filterFinishedByMonth(_visible(groupedRaw))
                : _visible(groupedRaw);

            if (widget.historyOnly) {
              return _buildHistoryList(groupedRaw, grouped);
            }

            if (grouped.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: const [
                  SizedBox(height: 80),
                  Icon(
                    Icons.event_busy,
                    color: DanjiColors.textSecondary,
                    size: 48,
                  ),
                  SizedBox(height: 12),
                  Text(
                    '진행 중인 예약이 없습니다.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: DanjiColors.textSecondary),
                  ),
                ],
              );
            }

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                if (grouped.operating.isNotEmpty) ...[
                  const _SectionHeader(
                    title: '대여 중',
                    icon: Icons.local_shipping_outlined,
                    color: DanjiColors.sectionOperating,
                  ),
                  const SizedBox(height: 10),
                  ...grouped.operating.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ReservationCard(
                        reservation: item,
                        pricing: _pricingFor(groupedRaw, item),
                        dateFormat: _dateFormat,
                        won: _won,
                        variant: _CardVariant.operating,
                        onUseVehicle: _showsRentalStartButton(item)
                            ? () => _openStartRental(item)
                            : null,
                        onReturn: item.canReturn && item.isOperating
                            ? () => _openReturn(item)
                            : null,
                        showContractButton: _showContractButton(
                          item,
                          variant: _CardVariant.operating,
                        ),
                        onContractTap: _showContractButton(
                          item,
                          variant: _CardVariant.operating,
                        )
                            ? () => _openContract(item)
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (grouped.waiting.isNotEmpty) ...[
                  const _SectionHeader(
                    title: '이용 대기',
                    icon: Icons.schedule_outlined,
                    color: DanjiColors.sectionWaiting,
                  ),
                  const SizedBox(height: 10),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: _WaitingRefundGuideLine(),
                  ),
                  ...grouped.waiting.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ReservationCard(
                        reservation: item,
                        pricing: _pricingFor(groupedRaw, item),
                        dateFormat: _dateFormat,
                        won: _won,
                        variant: _CardVariant.waiting,
                        onUseVehicle: _showsRentalStartButton(item)
                            ? () => _openStartRental(item)
                            : null,
                        useVehicleEnabled: item.canStartRental ||
                            item.canUseVehicle ||
                            item.status == 'in_use',
                        onReturn: null,
                        showCancelButton: item.shouldShowCancelButton,
                        onCancelTap: item.shouldShowCancelButton
                            ? () => _onCancelTap(item)
                            : null,
                        showContractButton: _showContractButton(
                          item,
                          variant: _CardVariant.waiting,
                        ),
                        onContractTap: _showContractButton(
                          item,
                          variant: _CardVariant.waiting,
                        )
                            ? () => _openContract(item)
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (grouped.finished.isNotEmpty) ...[
                  const _SectionHeader(
                    title: '이용 완료',
                    icon: Icons.check_circle_outline,
                    color: DanjiColors.sectionFinished,
                  ),
                  const SizedBox(height: 10),
                  ...grouped.finished.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ReservationCard(
                        reservation: item,
                        pricing: _pricingFor(groupedRaw, item),
                        dateFormat: _dateFormat,
                        won: _won,
                        variant: _CardVariant.finished,
                        showReservationId: true,
                        showContractButton: _showContractOnFinishedCard(item),
                        onContractTap: _showContractOnFinishedCard(item)
                            ? () => _openContract(item)
                            : null,
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  String _emptyHistoryMessage(String monthLabel) {
    switch (_historyTab) {
      case _HistoryTab.all:
        return '$monthLabel 이용내역이 없습니다.';
      case _HistoryTab.completed:
        return '$monthLabel 이용완료 내역이 없습니다.';
      case _HistoryTab.cancelled:
        return '$monthLabel 취소 내역이 없습니다.';
    }
  }

  Widget _buildHistoryList(
    GroupedReservations groupedRaw,
    GroupedReservations grouped,
  ) {
    final hasAnyHistory = groupedRaw.finished.isNotEmpty;
    final monthLabel = _monthHeaderFormat.format(_selectedMonth);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      children: [
        _HistoryTabBar(
          selected: _historyTab,
          onChanged: (tab) => setState(() => _historyTab = tab),
        ),
        const SizedBox(height: 12),
        _MonthFilterBar(
          label: monthLabel,
          canGoNext: _canGoNextMonth,
          onPrevious: () => _shiftMonth(-1),
          onNext: _canGoNextMonth ? () => _shiftMonth(1) : null,
        ),
        const SizedBox(height: 16),
        if (!hasAnyHistory) ...[
          const SizedBox(height: 60),
          const Icon(
            Icons.receipt_long_outlined,
            color: DanjiColors.textSecondary,
            size: 48,
          ),
          const SizedBox(height: 12),
          const Text(
            '이용내역이 없습니다.',
            textAlign: TextAlign.center,
            style: TextStyle(color: DanjiColors.textSecondary),
          ),
        ] else if (grouped.finished.isEmpty) ...[
          const SizedBox(height: 60),
          Text(
            _emptyHistoryMessage(monthLabel),
            textAlign: TextAlign.center,
            style: const TextStyle(color: DanjiColors.textSecondary),
          ),
        ] else ...[
          if (_historyTab != _HistoryTab.cancelled &&
              grouped.finished.any((r) => !r.isCancelled)) ...[
            if (_historyTab == _HistoryTab.all)
              const _SectionHeader(
                title: '이용 완료',
                icon: Icons.check_circle_outline,
                color: DanjiColors.sectionFinished,
              ),
            if (_historyTab == _HistoryTab.all) const SizedBox(height: 10),
            ...grouped.finished.where((r) => !r.isCancelled).map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ReservationCard(
                  reservation: item,
                  pricing: _pricingFor(groupedRaw, item),
                  dateFormat: _dateFormat,
                  won: _won,
                  variant: _CardVariant.finished,
                  showReservationId: true,
                  showContractButton: _showContractOnFinishedCard(item),
                  onContractTap: _showContractOnFinishedCard(item)
                      ? () => _openContract(item)
                      : null,
                ),
              ),
            ),
          ],
          if (_historyTab != _HistoryTab.completed &&
              grouped.finished.any((r) => r.isCancelled)) ...[
            if (_historyTab == _HistoryTab.all) const SizedBox(height: 8),
            if (_historyTab == _HistoryTab.all)
              const _SectionHeader(
                title: '예약 취소',
                icon: Icons.event_busy_outlined,
                color: DanjiColors.textMuted,
              ),
            if (_historyTab == _HistoryTab.all) const SizedBox(height: 10),
            ...grouped.finished.where((r) => r.isCancelled).map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ReservationCard(
                  reservation: item,
                  pricing: _pricingFor(groupedRaw, item),
                  dateFormat: _dateFormat,
                  won: _won,
                  variant: _CardVariant.cancelled,
                  showReservationId: true,
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _HistoryTabBar extends StatelessWidget {
  final _HistoryTab selected;
  final ValueChanged<_HistoryTab> onChanged;

  const _HistoryTabBar({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: DanjiColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DanjiColors.border),
      ),
      child: SegmentedButton<_HistoryTab>(
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          textStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
        segments: const [
          ButtonSegment(value: _HistoryTab.all, label: Text('전체')),
          ButtonSegment(value: _HistoryTab.completed, label: Text('이용완료')),
          ButtonSegment(value: _HistoryTab.cancelled, label: Text('취소')),
        ],
        selected: {selected},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}

class _MonthFilterBar extends StatelessWidget {
  final String label;
  final bool canGoNext;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;

  const _MonthFilterBar({
    required this.label,
    required this.canGoNext,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: DanjiColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DanjiColors.border),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left_rounded),
            color: DanjiColors.buttonBlue,
          ),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: DanjiTypography.subtitle.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
            color: canGoNext
                ? DanjiColors.buttonBlue
                : DanjiColors.textMuted,
          ),
        ],
      ),
    );
  }
}

enum _CardVariant { operating, waiting, finished, cancelled }

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;

  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: DanjiTypography.subtitle.copyWith(color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 1,
            color: color.withValues(alpha: 0.25),
          ),
        ),
      ],
    );
  }
}

class _ReservationCard extends StatelessWidget {
  final Reservation reservation;
  final ReservationPaymentPricing? pricing;
  final DateFormat dateFormat;
  final NumberFormat won;
  final _CardVariant variant;
  final VoidCallback? onUseVehicle;
  final VoidCallback? onReturn;
  final VoidCallback? onCancelTap;
  final bool showCancelButton;
  final bool useVehicleEnabled;
  final bool showContractButton;
  final VoidCallback? onContractTap;
  final bool showReservationId;

  const _ReservationCard({
    required this.reservation,
    this.pricing,
    required this.dateFormat,
    required this.won,
    required this.variant,
    this.onUseVehicle,
    this.onReturn,
    this.onCancelTap,
    this.showCancelButton = false,
    this.useVehicleEnabled = true,
    this.showContractButton = false,
    this.onContractTap,
    this.showReservationId = false,
  });

  Color get _accentColor {
    switch (variant) {
      case _CardVariant.operating:
        return DanjiColors.sectionOperating;
      case _CardVariant.waiting:
        return DanjiColors.sectionWaiting;
      case _CardVariant.finished:
        return DanjiColors.sectionFinished;
      case _CardVariant.cancelled:
        return DanjiColors.textMuted;
    }
  }

  String get _statusBadgeLabel {
    if (variant == _CardVariant.cancelled) return '예약취소';
    return reservation.displayStatusLabel;
  }

  int get _refundAmount {
    if (reservation.refundAmount > 0) return reservation.refundAmount;
    if (pricing != null && pricing!.finalPrice > 0) {
      return pricing!.finalPrice;
    }
    return reservation.totalPrice;
  }

  String? get _guideMessage {
    if (variant == _CardVariant.finished) return null;
    if (reservation.status == 'in_use') return null;
    if (variant == _CardVariant.waiting || variant == _CardVariant.operating) {
      return '사진 등록 후 대여를 시작하세요.';
    }
    return null;
  }

  bool get _showStartActivationHint =>
      variant == _CardVariant.waiting &&
      reservation.showRentalStartButton &&
      reservation.isTooEarlyForRentalStart;

  static const _inUseRentalButtonColor = Color(0xFFCCCCCC);

  ButtonStyle _rentalStartButtonStyle(Reservation reservation) {
    final base = DanjiTheme.primaryButton.copyWith(
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(vertical: 14),
      ),
    );
    if (!reservation.isInUse) return base;
    return base.copyWith(
      backgroundColor: const WidgetStatePropertyAll(_inUseRentalButtonColor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vehicle = reservation.vehicle;
    final start = reservation.displayRentalStartAt;
    final end = reservation.displayRentalEndAt;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DanjiColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: variant == _CardVariant.finished
              ? DanjiColors.border
              : variant == _CardVariant.cancelled
                  ? DanjiColors.border
                  : _accentColor.withValues(alpha: 0.35),
          width: variant == _CardVariant.operating ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: DanjiColors.buttonBlue.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (variant == _CardVariant.operating)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: _accentColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _accentColor.withValues(alpha: 0.6),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: Text(
                  vehicle?.name ?? '차량',
                  style: DanjiTypography.subtitle,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _statusBadgeLabel,
                  style: DanjiTypography.caption.copyWith(
                    color: variant == _CardVariant.cancelled
                        ? DanjiColors.accentRed
                        : _accentColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (showReservationId) ...[
            const SizedBox(height: 6),
            Text(
              '예약번호 ${reservation.reservationNumberLabel}',
              style: DanjiTypography.caption.copyWith(
                color: DanjiColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (variant == _CardVariant.cancelled &&
              reservation.cancelledAt != null) ...[
            const SizedBox(height: 8),
            Text(
              '취소일 ${dateFormat.format(reservation.cancelledAt!)}',
              style: DanjiTypography.secondary.copyWith(
                color: DanjiColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _refundAmount > 0
                  ? '환불금액 ₩${won.format(_refundAmount)}'
                  : '환불금액 ₩0',
              style: DanjiTypography.caption.copyWith(
                color: DanjiColors.accentRed,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (start != null && end != null) ...[
            const SizedBox(height: 8),
            Text(
              '${dateFormat.format(start)} ~ ${dateFormat.format(end)}',
              style: DanjiTypography.secondary.copyWith(height: 1.4),
            ),
            if (reservation.rentalDurationLabel != null) ...[
              const SizedBox(height: 4),
              Text(
                reservation.rentalDurationLabel!,
                style: DanjiTypography.caption.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (variant == _CardVariant.waiting) ...[
              const SizedBox(height: 4),
              Text(
                reservation.timeUntilStartLabel,
                style: DanjiTypography.caption.copyWith(
                  color: DanjiColors.buttonBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
          if (vehicle?.parkingLocation != null) ...[
            const SizedBox(height: 4),
            Text(
              '주차: ${vehicle!.parkingLocation}',
              style: DanjiTypography.secondary,
            ),
          ],
          if (variant != _CardVariant.cancelled &&
              (reservation.totalPrice > 0 ||
                  (pricing != null && pricing!.finalPrice > 0))) ...[
            const SizedBox(height: 4),
            ReservationPriceDisplay(
              reservationTotalPrice: reservation.totalPrice,
              pricing: pricing,
              won: won,
            ),
          ],
          if (onUseVehicle != null || onReturn != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                if (onUseVehicle != null)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: useVehicleEnabled ? onUseVehicle : null,
                      icon: const Icon(Icons.directions_car_outlined, size: 18),
                      label: const Text('대여하기'),
                      style: _rentalStartButtonStyle(reservation),
                    ),
                  ),
                if (onUseVehicle != null && onReturn != null)
                  const SizedBox(width: 8),
                if (onReturn != null)
                  Expanded(
                    child: FilledButton(
                      onPressed: onReturn,
                      style: DanjiTheme.primaryButton.copyWith(
                        minimumSize: const WidgetStatePropertyAll(
                          Size.fromHeight(48),
                        ),
                        padding: const WidgetStatePropertyAll(
                          EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                      child: const Text('반납하기'),
                    ),
                  ),
              ],
            ),
          ],
          if (showContractButton) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onContractTap,
                icon: const Icon(Icons.description_outlined, size: 18),
                label: const Text('계약서 보기'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: DanjiColors.buttonBlue,
                  side: const BorderSide(color: DanjiColors.border),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
          if (showCancelButton) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onCancelTap,
                icon: const Icon(
                  Icons.event_busy_outlined,
                  size: 18,
                  color: DanjiColors.accentRed,
                ),
                label: const Text('예약취소'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: DanjiColors.accentRed,
                  side: BorderSide(
                    color: DanjiColors.accentRed.withValues(alpha: 0.6),
                  ),
                  backgroundColor: DanjiColors.surface,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
          if (_guideMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              _guideMessage!,
              style: const TextStyle(
                color: DanjiColors.sectionOperating,
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (_showStartActivationHint) ...[
              const SizedBox(height: 4),
              Text(
                RentalStartMessages.startButtonActivationHint,
                style: const TextStyle(
                  color: DanjiColors.sectionOperating,
                  fontSize: 12,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _WaitingRefundGuideLine extends StatelessWidget {
  const _WaitingRefundGuideLine();

  void _openCancelRefundFaq(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FaqScreen(
          initialExpandedQuestion: CancelRefundDisplay.faqCancelQuestion,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const baseStyle = TextStyle(
      color: Color(0xFF888888),
      fontSize: 13,
      height: 1.45,
    );
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text(CancelRefundDisplay.waitingGuidePrefix, style: baseStyle),
        GestureDetector(
          onTap: () => _openCancelRefundFaq(context),
          child: const Text(
            CancelRefundDisplay.waitingGuideLink,
            style: TextStyle(
              color: DanjiColors.buttonBlue,
              fontSize: 13,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
