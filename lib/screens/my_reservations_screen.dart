import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/reservation.dart';
import '../services/rental_service.dart';
import '../widgets/danji_app_bar.dart';
import 'rental_return_screen.dart';
import 'rental_start_screen.dart';

class MyReservationsScreen extends StatefulWidget {
  const MyReservationsScreen({super.key});

  @override
  State<MyReservationsScreen> createState() => _MyReservationsScreenState();
}

class _MyReservationsScreenState extends State<MyReservationsScreen> {
  static const _bg = Color(0xFF071826);
  static const _textSecondary = Color(0xFF9AB3C9);

  final _service = RentalService();
  final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');
  final _won = NumberFormat('#,###');

  Future<List<Reservation>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = _service.fetchMyReservations();
    });
  }

  Future<void> _openRentalStart(Reservation reservation) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RentalStartScreen(reservationId: reservation.id),
      ),
    );
    if (result == true) _reload();
  }

  Future<void> _openReturn(Reservation reservation) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RentalReturnScreen(reservationId: reservation.id),
      ),
    );
    if (result == true) _reload();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'confirmed':
        return const Color(0xFF4DA3FF);
      case 'in_use':
        return const Color(0xFFFFB84D);
      case 'returned':
      case 'completed':
        return const Color(0xFF7EE2A8);
      default:
        return _textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: const DanjiAppBar(title: '내 예약'),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<Reservation>>(
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
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _reload, child: const Text('다시 시도')),
                ],
              );
            }

            final reservations = snap.data ?? [];
            if (reservations.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: const [
                  SizedBox(height: 80),
                  Icon(Icons.event_busy, color: _textSecondary, size: 48),
                  SizedBox(height: 12),
                  Text(
                    '예약 내역이 없습니다.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _textSecondary),
                  ),
                ],
              );
            }

            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              itemCount: reservations.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = reservations[index];
                return _ReservationCard(
                  reservation: item,
                  dateFormat: _dateFormat,
                  won: _won,
                  statusColor: _statusColor(item.status),
                  onStartRental: item.canStartRental
                      ? () => _openRentalStart(item)
                      : null,
                  onReturn: item.canReturn ? () => _openReturn(item) : null,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ReservationCard extends StatelessWidget {
  final Reservation reservation;
  final DateFormat dateFormat;
  final NumberFormat won;
  final Color statusColor;
  final VoidCallback? onStartRental;
  final VoidCallback? onReturn;

  const _ReservationCard({
    required this.reservation,
    required this.dateFormat,
    required this.won,
    required this.statusColor,
    this.onStartRental,
    this.onReturn,
  });

  static const _card = Color(0xFF0B2235);
  static const _textPrimary = Color(0xFFEAF2FF);
  static const _textSecondary = Color(0xFF9AB3C9);

  @override
  Widget build(BuildContext context) {
    final vehicle = reservation.vehicle;
    final start = reservation.startAt;
    final end = reservation.endAt;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  reservation.statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          if (start != null && end != null) ...[
            const SizedBox(height: 8),
            Text(
              '${dateFormat.format(start)} ~ ${dateFormat.format(end)}',
              style: const TextStyle(color: _textSecondary, height: 1.4),
            ),
          ],
          if (reservation.totalPrice > 0) ...[
            const SizedBox(height: 4),
            Text(
              '₩${won.format(reservation.totalPrice)}',
              style: const TextStyle(
                color: _textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (reservation.rentalStartedAt != null) ...[
            const SizedBox(height: 4),
            Text(
              '대여 시작: ${dateFormat.format(reservation.rentalStartedAt!)}',
              style: const TextStyle(color: _textSecondary, fontSize: 13),
            ),
          ],
          if (reservation.returnedAt != null) ...[
            const SizedBox(height: 4),
            Text(
              '반납: ${dateFormat.format(reservation.returnedAt!)}',
              style: const TextStyle(color: _textSecondary, fontSize: 13),
            ),
          ],
          if (onStartRental != null || onReturn != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                if (onStartRental != null)
                  Expanded(
                    child: FilledButton(
                      onPressed: onStartRental,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF0B2235),
                      ),
                      child: const Text('대여 시작'),
                    ),
                  ),
                if (onStartRental != null && onReturn != null)
                  const SizedBox(width: 8),
                if (onReturn != null)
                  Expanded(
                    child: FilledButton(
                      onPressed: onReturn,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF4DA3FF),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('반납하기'),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
