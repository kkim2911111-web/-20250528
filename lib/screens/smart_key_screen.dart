import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/reservation.dart';
import '../services/rental_service.dart';
import '../theme/danji_colors.dart';
import '../utils/rental_navigation.dart';
import 'booking_screen.dart';

/// 스마트키 — 현재 예약 차량 도어 제어
class SmartKeyScreen extends StatefulWidget {
  final bool isActive;

  const SmartKeyScreen({super.key, this.isActive = true});

  @override
  State<SmartKeyScreen> createState() => SmartKeyScreenState();
}

class SmartKeyScreenState extends State<SmartKeyScreen> {
  static const _lockRed = DanjiColors.danger;

  final _service = RentalService();
  final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');

  Future<List<Reservation>>? _future;
  final Set<String> _doorLoading = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(SmartKeyScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _reload();
    }
  }

  void reload() => _reload();

  void _reload() {
    setState(() {
      _future = _service.fetchSmartKeyReservations();
    });
  }

  bool _canUnlock(Reservation r) =>
      r.status == 'in_use' ||
      r.pickupPhotos.length >= 10 ||
      r.isOperating;

  void _onUnlock(Reservation r) async {
    if (!_canUnlock(r)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('운행 전 사진 10장 등록 후 문열림이 가능합니다.'),
          action: SnackBarAction(
            label: '등록하기',
            onPressed: () => _openRentalFlow(r),
          ),
        ),
      );
      return;
    }
    await _setDoor(r, unlocked: true);
  }

  void _onLock(Reservation r) async {
    await _setDoor(r, unlocked: false);
  }

  Future<void> _setDoor(Reservation r, {required bool unlocked}) async {
    if (_doorLoading.contains(r.id)) return;
    setState(() => _doorLoading.add(r.id));
    try {
      await _service.setDoorLock(
        reservationId: r.id,
        unlocked: unlocked,
      );
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            unlocked
                ? '${r.vehicle?.name ?? '차량'} 문이 열렸습니다.'
                : '${r.vehicle?.name ?? '차량'} 문이 잠겼습니다.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _doorLoading.remove(r.id));
    }
  }

  void _openBooking() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BookingScreen()),
    );
  }

  void _openRentalFlow(Reservation r) {
    openRentalOrUseScreen(context, r);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: AppBar(
        backgroundColor: DanjiColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          '스마트키',
          style: TextStyle(
            color: DanjiColors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: DanjiColors.textPrimary),
            tooltip: '새로고침',
            onPressed: _reload,
          ),
        ],
      ),
      body: FutureBuilder<List<Reservation>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      snap.error.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _lockRed),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _reload, child: const Text('다시 시도')),
                  ],
                ),
              ),
            );
          }

          final reservations = snap.data ?? [];

          if (reservations.isEmpty) {
            return _EmptyState(onBook: _openBooking);
          }

          final operating =
              reservations.where((r) => r.isOperating || r.status == 'in_use').toList();
          final waiting = reservations.where((r) => r.isWaiting).toList();

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                if (operating.isNotEmpty) ...[
                  const _SectionTitle(
                    title: '대여 중',
                    icon: Icons.local_shipping_outlined,
                    color: Color(0xFFFFB84D),
                  ),
                  const SizedBox(height: 10),
                  ...operating.map(
                    (r) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _SmartKeyCard(
                        reservation: r,
                        dateFormat: _dateFormat,
                        isUnlocked: r.doorUnlocked,
                        isLoading: _doorLoading.contains(r.id),
                        canUnlock: _canUnlock(r),
                        onUnlock: () => _onUnlock(r),
                        onLock: () => _onLock(r),
                        onOpenDetail: () => _openRentalFlow(r),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (waiting.isNotEmpty) ...[
                  const _SectionTitle(
                    title: '이용 대기',
                    icon: Icons.schedule_outlined,
                    color: Color(0xFF4DA3FF),
                  ),
                  const SizedBox(height: 10),
                  ...waiting.map(
                    (r) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _SmartKeyCard(
                        reservation: r,
                        dateFormat: _dateFormat,
                        isUnlocked: r.doorUnlocked,
                        isLoading: _doorLoading.contains(r.id),
                        canUnlock: _canUnlock(r),
                        onUnlock: () => _onUnlock(r),
                        onLock: () => _onLock(r),
                        onOpenDetail: () => _openRentalFlow(r),
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

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;

  const _SectionTitle({
    required this.title,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onBook;

  const _EmptyState({required this.onBook});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.vpn_key_outlined,
              size: 64,
              color: DanjiColors.textSecondary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 20),
            const Text(
              '예약 진행 후 이용 가능합니다',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: DanjiColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '차량을 예약하면 이 화면에서\n스마트키로 문을 열고 닫을 수 있습니다.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: DanjiColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: onBook,
              icon: const Icon(Icons.event_available_outlined),
              label: const Text('예약하기'),
              style: FilledButton.styleFrom(
                backgroundColor: DanjiColors.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmartKeyCard extends StatelessWidget {
  final Reservation reservation;
  final DateFormat dateFormat;
  final bool isUnlocked;
  final bool isLoading;
  final bool canUnlock;
  final VoidCallback onUnlock;
  final VoidCallback onLock;
  final VoidCallback onOpenDetail;

  const _SmartKeyCard({
    required this.reservation,
    required this.dateFormat,
    required this.isUnlocked,
    required this.isLoading,
    required this.canUnlock,
    required this.onUnlock,
    required this.onLock,
    required this.onOpenDetail,
  });

  static const _unlockBlue = DanjiColors.rentalBlue;
  static const _lockRed = DanjiColors.accentRed;
  static const _textPrimary = DanjiColors.textPrimary;
  static const _textSecondary = DanjiColors.textSecondary;
  static const _waitingBlue = DanjiColors.primaryBlue;

  @override
  Widget build(BuildContext context) {
    final vehicle = reservation.vehicle;
    final start = reservation.startAt;
    final end = reservation.endAt;
    final operating = reservation.isOperating || reservation.status == 'in_use';
    final badgeColor = operating ? const Color(0xFFFFB84D) : _waitingBlue;
    final badgeLabel = reservation.status == 'in_use'
        ? '대여 중'
        : operating
            ? '운행 중'
            : '이용 대기';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DanjiColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DanjiColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onOpenDetail,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: DanjiColors.background,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.directions_car_filled_outlined,
                      color: DanjiColors.primaryBlue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                vehicle?.name ?? '차량',
                                style: const TextStyle(
                                  color: _textPrimary,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: badgeColor.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                badgeLabel,
                                style: TextStyle(
                                  color: badgeColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          vehicle?.vehicleType ?? '-',
                          style: const TextStyle(
                            color: _textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        if (start != null && end != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${dateFormat.format(start)} ~ ${dateFormat.format(end)}',
                            style: const TextStyle(
                              color: _textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        if (vehicle?.parkingLocation != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            '주차: ${vehicle!.parkingLocation}',
                            style: const TextStyle(
                              color: _textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (isUnlocked)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _unlockBlue.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '열림',
                        style: TextStyle(
                          color: _unlockBlue,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (!canUnlock) ...[
            const Text(
              '운행 전 사진 등록 후 문열림이 가능합니다. (문닫힘은 바로 사용 가능)',
              style: TextStyle(color: _lockRed, fontSize: 12, height: 1.35),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: _DoorBtn(
                  label: '문열림',
                  icon: Icons.lock_open_rounded,
                  color: _unlockBlue,
                  enabled: canUnlock && !isLoading,
                  loading: isLoading,
                  onPressed: onUnlock,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DoorBtn(
                  label: '문닫힘',
                  icon: Icons.lock_rounded,
                  color: _lockRed,
                  enabled: !isLoading,
                  loading: isLoading,
                  onPressed: onLock,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DoorBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool enabled;
  final bool loading;
  final VoidCallback onPressed;

  const _DoorBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.enabled,
    this.loading = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: FilledButton.icon(
        onPressed: enabled && !loading ? onPressed : null,
        icon: loading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: color.withValues(alpha: 0.9),
                ),
              )
            : Icon(icon, size: 22),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: enabled ? color : color.withValues(alpha: 0.35),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}
