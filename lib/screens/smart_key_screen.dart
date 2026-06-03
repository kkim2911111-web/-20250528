import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/reservation.dart';
import '../services/rental_service.dart';
import '../theme/danji_colors.dart';
import '../theme/danji_typography.dart';
import '../utils/rental_navigation.dart';
import '../widgets/smart_key_door_buttons.dart';

/// 스마트키 — 대여 중(in_use) 차량 도어 제어
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
        title: Text(
          '스마트키',
          style: DanjiTypography.subtitleLarge.copyWith(
            fontWeight: FontWeight.w700,
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
            return const _EmptyState();
          }

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                const _SectionTitle(
                  title: '대여 중',
                  icon: Icons.local_shipping_outlined,
                  color: DanjiColors.toneRed,
                ),
                const SizedBox(height: 10),
                ...reservations.map(
                  (r) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _SmartKeyCard(
                      reservation: r,
                      dateFormat: _dateFormat,
                      isUnlocked: r.doorUnlocked,
                      onOpenDetail: () => _openRentalFlow(r),
                      onDoorChanged: _reload,
                      service: _service,
                    ),
                  ),
                ),
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
          style: DanjiTypography.buttonPrimary.copyWith(color: color),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4FF),
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.vpn_key_outlined,
                size: 32,
                color: Color(0xFF3182F6),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '대여 중인 차량이 없어요',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF333333),
                letterSpacing: -0.3,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '예약 후 대여를 시작해보세요',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFFAAAAAA),
                height: 1.35,
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
  final VoidCallback onOpenDetail;
  final VoidCallback onDoorChanged;
  final RentalService service;

  const _SmartKeyCard({
    required this.reservation,
    required this.dateFormat,
    required this.isUnlocked,
    required this.onOpenDetail,
    required this.onDoorChanged,
    required this.service,
  });

  static const _unlockBlue = DanjiColors.brandBlue;
  static const _textSecondary = DanjiColors.textSecondary;

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
                                style: DanjiTypography.subtitle,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: DanjiColors.tagRentingBg,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                '대여 중',
                                style: TextStyle(
                                  color: DanjiColors.tagRentingText,
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
                          style: DanjiTypography.secondary,
                        ),
                        if (start != null && end != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${dateFormat.format(start)} ~ ${dateFormat.format(end)}',
                            style: DanjiTypography.caption.copyWith(
                              color: _textSecondary,
                            ),
                          ),
                        ],
                        if (vehicle?.parkingLocation != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            '주차: ${vehicle!.parkingLocation}',
                            style: DanjiTypography.caption.copyWith(
                              color: _textSecondary,
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
          SmartKeyDoorButtons(
            reservation: reservation,
            service: service,
            onChanged: onDoorChanged,
          ),
        ],
      ),
    );
  }
}
