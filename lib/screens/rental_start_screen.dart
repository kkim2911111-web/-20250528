import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/fuel_level.dart';
import '../models/reservation.dart';
import '../theme/danji_colors.dart';
import '../services/rental_service.dart';
import '../widgets/danji_app_bar.dart';
import '../widgets/fuel_level_selector.dart';
import '../widgets/photo_upload_grid.dart';
import '../widgets/section_card.dart';

class RentalStartScreen extends StatefulWidget {
  final String reservationId;

  const RentalStartScreen({super.key, required this.reservationId});

  @override
  State<RentalStartScreen> createState() => _RentalStartScreenState();
}

class _RentalStartScreenState extends State<RentalStartScreen> {
  final _service = RentalService();
  final _mileageController = TextEditingController();
  final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');

  Reservation? _reservation;
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  List<Uint8List> _photos = [];
  FuelLevel? _fuelLevel;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _mileageController.dispose();
    super.dispose();
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
          _error = '대여를 시작할 수 없는 예약입니다. (상태: ${reservation.statusLabel})';
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
    final mileage = int.tryParse(_mileageController.text.trim());
    if (_photos.isEmpty) {
      setState(() => _error = '차량 사진을 1장 이상 등록해주세요.');
      return;
    }
    if (mileage == null || mileage < 0) {
      setState(() => _error = '주행거리(km)를 입력해주세요.');
      return;
    }
    if (_fuelLevel == null) {
      setState(() => _error = '주유 상태를 선택해주세요.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await _service.startRental(
        reservationId: widget.reservationId,
        photos: _photos,
        mileageStart: mileage,
        fuelLevelStart: _fuelLevel!,
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
                              style: const TextStyle(color: DanjiColors.textSecondary),
                            ),
                          ],
                          if (vehicle?.parkingLocation != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              '주차: ${vehicle!.parkingLocation}',
                              style: const TextStyle(color: DanjiColors.textSecondary),
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
                      child: PhotoUploadGrid(
                        photos: _photos,
                        onChanged: (photos) => setState(() => _photos = photos),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '주행거리 (km)',
                            style: TextStyle(
                              color: DanjiColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _mileageController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            style: const TextStyle(color: DanjiColors.textPrimary),
                            decoration: InputDecoration(
                              hintText: '예: 12345',
                              hintStyle: TextStyle(
                                color: DanjiColors.textSecondary.withValues(alpha: 0.7),
                              ),
                              filled: true,
                              fillColor: DanjiColors.skyLight,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: DanjiColors.border),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SectionCard(
                      child: FuelLevelSelector(
                        value: _fuelLevel,
                        onChanged: (level) => setState(() => _fuelLevel = level),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: const TextStyle(color: DanjiColors.accentRed),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: _submitting ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: DanjiColors.rentalBlue,
                          foregroundColor: Colors.white,
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
                                child: CircularProgressIndicator(strokeWidth: 2),
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
