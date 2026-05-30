import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/fuel_level.dart';
import '../models/reservation.dart';
import '../services/rental_service.dart';
import '../widgets/danji_app_bar.dart';
import '../widgets/fuel_level_selector.dart';
import '../widgets/photo_upload_grid.dart';
import '../theme/danji_colors.dart';
import '../theme/danji_theme.dart';
import '../widgets/section_card.dart';

class RentalReturnScreen extends StatefulWidget {
  final String reservationId;
  final bool isEarlyReturn;
  final bool earlyReturnAcknowledged;

  const RentalReturnScreen({
    super.key,
    required this.reservationId,
    this.isEarlyReturn = false,
    this.earlyReturnAcknowledged = false,
  });

  @override
  State<RentalReturnScreen> createState() => _RentalReturnScreenState();
}

class _RentalReturnScreenState extends State<RentalReturnScreen> {
  final _service = RentalService();
  final _mileageController = TextEditingController();
  final _accidentNoteController = TextEditingController();
  final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');

  Reservation? _reservation;
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  List<Uint8List> _photos = [];
  FuelLevel? _fuelLevel;
  bool _isAccident = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _mileageController.dispose();
    _accidentNoteController.dispose();
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
      if (!reservation.canReturn) {
        setState(() {
          _loading = false;
          _error = '반납할 수 없는 예약입니다. (상태: ${reservation.statusLabel})';
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
      setState(() => _error = '반납 사진을 1장 이상 등록해주세요.');
      return;
    }
    if (mileage == null || mileage < 0) {
      setState(() => _error = '주행거리(km)를 입력해주세요.');
      return;
    }
    final mileageStart = _reservation?.mileageStart;
    if (mileageStart != null && mileage < mileageStart) {
      setState(() => _error = '반납 주행거리는 대여 시작($mileageStart km)보다 작을 수 없습니다.');
      return;
    }
    if (_fuelLevel == null) {
      setState(() => _error = '주유 상태를 선택해주세요.');
      return;
    }
    if (_isAccident && _accidentNoteController.text.trim().isEmpty) {
      setState(() => _error = '사고 내용을 입력해주세요.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await _service.completeReturn(
        reservationId: widget.reservationId,
        photos: _photos,
        mileageEnd: mileage,
        fuelLevelEnd: _fuelLevel!,
        isAccident: _isAccident,
        accidentNote:
            _isAccident ? _accidentNoteController.text.trim() : null,
        isEarlyReturn: widget.isEarlyReturn,
        earlyReturnAcknowledged: widget.earlyReturnAcknowledged,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isEarlyReturn
                ? EarlyReturnMessages.success
                : '반납이 완료되었습니다.',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final reservation = _reservation;
    final vehicle = reservation?.vehicle;

    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: DanjiAppBar(
        title: widget.isEarlyReturn ? '중도반납' : '차량 반납',
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : reservation == null
              ? _ErrorBody(message: _error ?? '예약 정보를 불러올 수 없습니다.')
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (widget.isEarlyReturn) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: DanjiColors.skyLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: DanjiColors.skySoft),
                        ),
                        child: const Text(
                          EarlyReturnMessages.confirmBody,
                          style: TextStyle(
                            color: DanjiColors.textSecondary,
                            height: 1.45,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
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
                          if (reservation.rentalStartedAt != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              '대여 시작: ${_dateFormat.format(reservation.rentalStartedAt!)}',
                              style: const TextStyle(
                                color: DanjiColors.textSecondary,
                              ),
                            ),
                          ],
                          if (reservation.mileageStart != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              '대여 시 주행거리: ${reservation.mileageStart} km',
                              style: const TextStyle(
                                color: DanjiColors.textSecondary,
                              ),
                            ),
                          ],
                          if (reservation.fuelLevelStart != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              '대여 시 주유: ${FuelLevel.fromValue(reservation.fuelLevelStart)?.label ?? reservation.fuelLevelStart}',
                              style: const TextStyle(
                                color: DanjiColors.textSecondary,
                              ),
                            ),
                          ],
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
                            '반납 주행거리 (km)',
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
                              hintText: '현재 계기판 km',
                              hintStyle: TextStyle(
                                color: DanjiColors.textMuted,
                              ),
                              filled: true,
                              fillColor: DanjiColors.skyLight,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
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
                    const SizedBox(height: 16),
                    SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              '사고 발생',
                              style: TextStyle(
                                color: DanjiColors.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: const Text(
                              '사고가 있었다면 체크 후 내용을 입력해주세요.',
                              style: const TextStyle(
                                color: DanjiColors.textSecondary,
                              ),
                            ),
                            value: _isAccident,
                            activeThumbColor: DanjiColors.buttonBlue,
                            onChanged: (value) {
                              setState(() {
                                _isAccident = value;
                                if (!value) _accidentNoteController.clear();
                              });
                            },
                          ),
                          if (_isAccident) ...[
                            const SizedBox(height: 8),
                            TextField(
                              controller: _accidentNoteController,
                              maxLines: 4,
                              style: const TextStyle(color: DanjiColors.textPrimary),
                              decoration: InputDecoration(
                                hintText: '사고 시간, 장소, 내용 등',
                                hintStyle: TextStyle(
                                  color: DanjiColors.textMuted,
                                ),
                                filled: true,
                                fillColor: DanjiColors.skyLight,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ],
                        ],
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
                        style: DanjiTheme.primaryButton.copyWith(
                          textStyle: WidgetStateProperty.all(
                            const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        child: _submitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(widget.isEarlyReturn ? '중도반납 완료' : '반납 완료'),
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
