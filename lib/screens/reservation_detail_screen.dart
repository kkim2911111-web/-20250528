import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/reservation.dart';
import '../services/rental_service.dart';
import '../theme/danji_colors.dart';
import '../theme/danji_theme.dart';
import '../utils/rental_navigation.dart';
import '../widgets/danji_app_bar.dart';
import '../widgets/reservation_price_display.dart';

/// FCM 알림 탭 등 — 예약 ID로 상세 진입
class ReservationDetailScreen extends StatefulWidget {
  final String reservationId;

  const ReservationDetailScreen({super.key, required this.reservationId});

  @override
  State<ReservationDetailScreen> createState() =>
      _ReservationDetailScreenState();
}

class _ReservationDetailScreenState extends State<ReservationDetailScreen> {
  final _service = RentalService();
  final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');
  final _won = NumberFormat('#,###');

  Future<Reservation>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = _service.fetchReservation(widget.reservationId);
    });
  }

  Future<void> _openRental(Reservation reservation) async {
    final result = await openRentalOrUseScreen<bool>(context, reservation);
    if (result == true) _reload();
  }

  Future<void> _openReturn(Reservation reservation) async {
    final result = await openRentalReturn<bool>(context, reservation);
    if (result == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: const DanjiAppBar(title: '예약 상세', showBack: true),
      body: FutureBuilder<Reservation>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          }
          if (snap.hasError) {
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  snap.error.toString().replaceFirst('RentalException: ', ''),
                  style: const TextStyle(color: DanjiColors.accentRed),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _reload,
                  child: const Text('다시 시도'),
                ),
              ],
            );
          }

          final reservation = snap.data!;
          final vehicleName = reservation.vehicle?.name ?? '차량';
          final start = reservation.displayRentalStartAt;
          final end = reservation.displayRentalEndAt;

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                vehicleName,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: DanjiColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              _InfoChip(label: reservation.statusLabel),
              const SizedBox(height: 20),
              _InfoRow(
                label: '예약 번호',
                value: reservation.id,
              ),
              if (start != null)
                _InfoRow(
                  label: '시작',
                  value: _dateFormat.format(start.toLocal()),
                ),
              if (end != null)
                _InfoRow(
                  label: '종료',
                  value: _dateFormat.format(end.toLocal()),
                ),
              const SizedBox(height: 8),
              ReservationPriceDisplay(
                reservationTotalPrice: reservation.totalPrice,
                pricing: null,
                won: _won,
              ),
              const SizedBox(height: 24),
              if (reservation.showRentalStartButton ||
                  reservation.canUseVehicle) ...[
                FilledButton(
                  onPressed: () => _openRental(reservation),
                  style: DanjiTheme.primaryButton.copyWith(
                    minimumSize: const WidgetStatePropertyAll(
                      Size.fromHeight(52),
                    ),
                  ),
                  child: Text(
                    reservation.status == 'in_use' ? '대여 이용하기' : '대여하기',
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (reservation.canReturn && reservation.isOperating) ...[
                OutlinedButton(
                  onPressed: () => _openReturn(reservation),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    foregroundColor: DanjiColors.buttonBlue,
                    side: const BorderSide(color: DanjiColors.buttonBlue),
                  ),
                  child: const Text('반납하기'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;

  const _InfoChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: DanjiColors.skyLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: DanjiColors.buttonBlue,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                color: DanjiColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: DanjiColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
