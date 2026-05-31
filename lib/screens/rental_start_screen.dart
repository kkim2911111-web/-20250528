import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/reservation.dart';
import '../theme/danji_colors.dart';
import '../services/rental_service.dart';
import '../widgets/danji_app_bar.dart';
import '../widgets/rental_start_photo_section.dart';
import '../widgets/section_card.dart';

class RentalStartScreen extends StatefulWidget {
  final String reservationId;

  const RentalStartScreen({super.key, required this.reservationId});

  @override
  State<RentalStartScreen> createState() => _RentalStartScreenState();
}

class _RentalStartScreenState extends State<RentalStartScreen> {
  final _service = RentalService();
  final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');

  Reservation? _reservation;
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  List<Uint8List> _photos = [];

  bool get _canSubmit =>
      _photos.length >= RentalStartPhotoSection.minPhotos && !_submitting;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final reservation = await _service.fetchReservation(widget.reservationId);
      if (!mounted) return;
      if (!reservation.canStartRental) {
        setState(() {
          _loading = false;
          _error = reservation.isTooEarlyForRentalStart
              ? RentalStartMessages.tooEarly
              : '대여를 시작할 수 없는 예약입니다. (상태: ${reservation.statusLabel})';
        });
        return;
      }
      setState(() {
        _reservation = reservation;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await _service.startRental(
        reservationId: widget.reservationId,
        photos: _photos,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('대여가 시작되었습니다.')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString().replaceFirst('RentalException: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final reservation = _reservation;
    final vehicle = reservation?.vehicle;

    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: const DanjiAppBar(title: '운행 시작', light: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : reservation == null
              ? _ErrorBody(message: _error ?? '예약 정보를 불러올 수 없습니다.')
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            vehicle?.name ?? '차량',
                            style: const TextStyle(
                              color: DanjiColors.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (vehicle?.carNumber != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              '번호: ${vehicle!.carNumber}',
                              style: const TextStyle(
                                color: DanjiColors.textSecondary,
                              ),
                            ),
                          ],
                          if (vehicle?.parkingLocation != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              '주차: ${vehicle!.parkingLocation}',
                              style: const TextStyle(
                                color: DanjiColors.textSecondary,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          if (reservation.startAt != null &&
                              reservation.endAt != null)
                            Text(
                              '예약: ${_dateFormat.format(reservation.startAt!)} ~ '
                              '${_dateFormat.format(reservation.endAt!)}',
                              style: const TextStyle(
                                color: DanjiColors.textSecondary,
                                height: 1.4,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SectionCard(
                      child: RentalStartPhotoSection(
                        photos: _photos,
                        onChanged: (photos) => setState(() => _photos = photos),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: const TextStyle(color: DanjiColors.accentRed),
                      ),
                    ],
                    if (_photos.length < RentalStartPhotoSection.minPhotos) ...[
                      const SizedBox(height: 12),
                      const Text(
                        '최소 6장 이상 등록해 주세요',
                        style: TextStyle(
                          color: DanjiColors.textMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: _canSubmit ? _submit : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: DanjiColors.rentalBlue,
                          disabledBackgroundColor: DanjiColors.textMuted,
                          foregroundColor: Colors.white,
                          disabledForegroundColor: Colors.white70,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        child: _submitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('운행 시작'),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final String message;

  const _ErrorBody({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.redAccent),
        ),
      ),
    );
  }
}
