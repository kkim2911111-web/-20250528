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
import '../utils/rental_navigation.dart';
import '../utils/reservation_change_flow.dart';

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

class _MyReservationsScreenState extends State<MyReservationsScreen> {
  final _service = RentalService();
  final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');
  final _won = NumberFormat('#,###');

  Future<GroupedReservations>? _future;
  int _listKey = 0;
  final _hiddenIds = <String>{};

  @override
  void initState() {
    super.initState();
    ReservationRefreshBus.instance.version.addListener(_onExternalRefresh);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reloadAndWait());
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

  Future<void> _openReturn(Reservation reservation) async {
    final result = await openRentalReturn<bool>(context, reservation);
    if (result == true) _reload();
  }

  Future<void> _onCancelTap(Reservation reservation) async {
    if (!reservation.canCancel) {
      if (reservation.isCancelBlocked) {
        _showCancelSnack(ReservationCancelMessages.tooLate);
      }
      return;
    }
    await _cancelReservation(reservation);
  }

  Future<void> _onChangeTap(Reservation reservation) async {
    if (!reservation.canChangeReservation) {
      if (reservation.isChangeBlocked) {
        _showCancelSnack(ReservationCancelMessages.changeTooLate);
      }
      return;
    }
    final changed = await openReservationChange(context, reservation);
    if (changed) await _reloadAndWait();
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DanjiColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '예약 취소',
          style: TextStyle(
            color: DanjiColors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: const Text(
          '정말 취소하시겠습니까? 결제하신 금액은 전액 환불됩니다.',
          style: TextStyle(color: DanjiColors.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('닫기'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: DanjiTheme.dangerButton,
            child: const Text('예약취소'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      setState(() {
        _hiddenIds.add(reservation.id);
      });
      await _service.cancelReservation(reservation.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      await _reloadAndWait();
      if (!mounted) return;
      setState(() {
        _hiddenIds.remove(reservation.id);
      });
      _showCancelSnack(ReservationCancelMessages.success);
    } catch (e) {
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

            final grouped = _visible(groupedRaw);
            if (grouped.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 80),
                  Icon(
                    widget.historyOnly
                        ? Icons.receipt_long_outlined
                        : Icons.event_busy,
                    color: DanjiColors.textSecondary,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.historyOnly
                        ? '이용내역이 없습니다.'
                        : '진행 중인 예약이 없습니다.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: DanjiColors.textSecondary),
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
                        dateFormat: _dateFormat,
                        won: _won,
                        variant: _CardVariant.operating,
                        onUseVehicle: _showsRentalStartButton(item)
                            ? () => _openStartRental(item)
                            : null,
                        onReturn: item.canReturn && item.isOperating
                            ? () => _openReturn(item)
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
                    child: Text(
                      ReservationCancelMessages.waitingGuide,
                      style: TextStyle(
                        color: Color(0xFF888888),
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ),
                  ...grouped.waiting.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ReservationCard(
                        reservation: item,
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
                        showChangeButton: item.shouldShowChangeButton,
                        cancelBlocked: item.isCancelBlocked,
                        changeBlocked: item.isChangeBlocked,
                        onCancelTap: item.shouldShowCancelButton
                            ? () => _onCancelTap(item)
                            : null,
                        onChangeTap: item.shouldShowChangeButton
                            ? () => _onChangeTap(item)
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
                        dateFormat: _dateFormat,
                        won: _won,
                        variant: _CardVariant.finished,
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
}

enum _CardVariant { operating, waiting, finished }

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
  final DateFormat dateFormat;
  final NumberFormat won;
  final _CardVariant variant;
  final VoidCallback? onUseVehicle;
  final VoidCallback? onReturn;
  final VoidCallback? onCancelTap;
  final VoidCallback? onChangeTap;
  final bool showCancelButton;
  final bool showChangeButton;
  final bool cancelBlocked;
  final bool changeBlocked;
  final bool useVehicleEnabled;

  const _ReservationCard({
    required this.reservation,
    required this.dateFormat,
    required this.won,
    required this.variant,
    this.onUseVehicle,
    this.onReturn,
    this.onCancelTap,
    this.onChangeTap,
    this.showCancelButton = false,
    this.showChangeButton = false,
    this.cancelBlocked = false,
    this.changeBlocked = false,
    this.useVehicleEnabled = true,
  });

  Color get _accentColor {
    switch (variant) {
      case _CardVariant.operating:
        return DanjiColors.sectionOperating;
      case _CardVariant.waiting:
        return DanjiColors.sectionWaiting;
      case _CardVariant.finished:
        return DanjiColors.sectionFinished;
    }
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
    final start = reservation.startAt;
    final end = reservation.endAt;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DanjiColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: variant == _CardVariant.finished
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
                  reservation.displayStatusLabel,
                  style: DanjiTypography.caption.copyWith(
                    color: _accentColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (start != null && end != null) ...[
            const SizedBox(height: 8),
            Text(
              '${dateFormat.format(start)} ~ ${dateFormat.format(end)}',
              style: DanjiTypography.secondary.copyWith(height: 1.4),
            ),
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
          if (reservation.totalPrice > 0) ...[
            const SizedBox(height: 4),
            Text(
              '₩${won.format(reservation.totalPrice)}',
              style: DanjiTypography.body.copyWith(
                fontWeight: FontWeight.w600,
              ),
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
          if (showCancelButton || showChangeButton) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (showChangeButton)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          changeBlocked ? null : onChangeTap,
                      icon: Icon(
                        Icons.edit_calendar_outlined,
                        size: 18,
                        color: changeBlocked
                            ? DanjiColors.textMuted
                            : DanjiColors.buttonBlue,
                      ),
                      label: const Text('예약변경'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: DanjiColors.buttonBlue,
                        side: BorderSide(
                          color: changeBlocked
                              ? DanjiColors.border
                              : DanjiColors.buttonBlue.withValues(alpha: 0.6),
                        ),
                        backgroundColor: DanjiColors.surface,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                if (showChangeButton && showCancelButton)
                  const SizedBox(width: 8),
                if (showCancelButton)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: cancelBlocked ? null : onCancelTap,
                      icon: Icon(
                        Icons.event_busy_outlined,
                        size: 18,
                        color: cancelBlocked
                            ? DanjiColors.textMuted
                            : DanjiColors.accentRed,
                      ),
                      label: const Text('예약취소'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: DanjiColors.accentRed,
                        side: BorderSide(
                          color: cancelBlocked
                              ? DanjiColors.border
                              : DanjiColors.accentRed.withValues(alpha: 0.6),
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
            ),
            if (changeBlocked) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 14,
                    color: DanjiColors.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      ReservationCancelMessages.changeTooLate,
                      style: TextStyle(
                        color: DanjiColors.textSecondary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ] else if (cancelBlocked) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 14,
                    color: DanjiColors.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      ReservationCancelMessages.tooLate,
                      style: TextStyle(
                        color: DanjiColors.textSecondary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ],
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
