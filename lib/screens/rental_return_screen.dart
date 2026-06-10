import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models/fuel_level.dart';
import '../models/reservation.dart';
import '../services/rental_service.dart';
import '../services/rental_start_service.dart';
import '../utils/danji_snackbar.dart';
import '../widgets/danji_app_bar.dart';
import '../widgets/fuel_level_selector.dart';
import '../widgets/rental_photo_capture_guide.dart';
import '../widgets/rental_pickup_photo_grid.dart';
import '../widgets/smart_key_door_buttons.dart';
import '../theme/danji_colors.dart';
import '../widgets/section_card.dart';

class RentalReturnScreen extends StatefulWidget {
  final String reservationId;

  const RentalReturnScreen({super.key, required this.reservationId});

  @override
  State<RentalReturnScreen> createState() => _RentalReturnScreenState();
}

class _RentalReturnScreenState extends State<RentalReturnScreen> {
  final _service = RentalService();
  final _picker = ImagePicker();
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
  bool _doorLockConfirmed = false;
  bool _doorLockLoading = false;

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

  Future<void> _pickFromGallery() async {
    final picked = await _picker.pickMultiImage(
      imageQuality: 85,
      maxWidth: 1920,
      limit: RentalStartService.maxPhotos,
    );
    if (picked.isEmpty) return;

    final bytes = <Uint8List>[];
    for (final file in picked) {
      bytes.add(await file.readAsBytes());
    }

    setState(() {
      _photos = bytes.take(RentalStartService.maxPhotos).toList();
      if (_photos.length < RentalStartService.minPhotos) {
        _error =
            '최소 ${RentalStartService.minPhotos}장 이상 선택해주세요. (현재 ${_photos.length}장)';
      } else {
        _error = null;
      }
    });
  }

  Future<void> _takePhoto() async {
    if (_photos.length >= RentalStartService.maxPhotos) {
      setState(() {
        _error =
            '사진은 최대 ${RentalStartService.maxPhotos}장까지 등록할 수 있습니다.';
      });
      return;
    }

    final file = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (file == null) return;

    final bytes = await file.readAsBytes();
    setState(() {
      _photos = [..._photos, bytes].take(RentalStartService.maxPhotos).toList();
      _error = _photos.length < RentalStartService.minPhotos
          ? '최소 ${RentalStartService.minPhotos}장 이상 등록해주세요.'
          : null;
    });
  }

  void _removePhotoAt(int index) {
    if (index < 0 || index >= _photos.length) return;
    setState(() {
      _photos = [..._photos]..removeAt(index);
      _error = _photos.length < RentalStartService.minPhotos
          ? '최소 ${RentalStartService.minPhotos}장 이상 등록해주세요.'
          : null;
    });
  }

  Future<void> _onDoorLock() async {
    final reservation = _reservation;
    if (reservation == null || _doorLockConfirmed || _doorLockLoading) return;

    setState(() => _doorLockLoading = true);
    try {
      await _service.setDoorLock(
        reservationId: reservation.id,
        unlocked: false,
      );
      if (!mounted) return;

      DanjiSnackBar.show(
        context,
        '${reservation.vehicle?.name ?? '차량'} 문이 잠겼습니다.',
      );

      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('문 잠금 확인'),
          content: const Text('문이 잠겼는지 확인해 주세요'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('확인'),
            ),
          ],
        ),
      );

      if (confirmed == true && mounted) {
        setState(() => _doorLockConfirmed = true);
      }
    } catch (e) {
      if (!mounted) return;
      DanjiSnackBar.show(
        context,
        e.toString().replaceFirst('RentalException: ', ''),
      );
    } finally {
      if (mounted) setState(() => _doorLockLoading = false);
    }
  }

  Future<void> _submit() async {
    if (!_doorLockConfirmed) {
      setState(() => _error = '문 잠금 확인 후 반납할 수 있습니다.');
      return;
    }

    final mileage = int.tryParse(_mileageController.text.trim());
    if (_photos.length < RentalStartService.minPhotos) {
      setState(() => _error =
          '반납 사진을 최소 ${RentalStartService.minPhotos}장 등록해주세요.');
      return;
    }
    if (mileage == null || mileage < 0) {
      setState(() => _error = '주행거리(km)를 입력해주세요.');
      return;
    }
    final mileageStart = _reservation?.mileageStart;
    if (mileageStart != null && mileage < mileageStart) {
      setState(() => _error =
          '반납 주행거리는 대여 시작($mileageStart km)보다 작을 수 없습니다.');
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
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('반납이 완료되었습니다.')),
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
      appBar: const DanjiAppBar(title: '반납하기'),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          RentalPhotoCaptureGuide(
                            capturedCount: _photos.length,
                          ),
                          const SizedBox(height: 12),
                          RentalPickupPhotoGrid(
                            sectionTitle: '반납 사진',
                            guideLine:
                                '전면·후면·좌측면·우측면·실내·계기판 순으로 최소 6장, 최대 10장 등록해 주세요.',
                            photos: _photos,
                            onBulkGallery: _pickFromGallery,
                            onCamera: _takePhoto,
                            onRemove: _removePhotoAt,
                          ),
                        ],
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
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            style:
                                const TextStyle(color: DanjiColors.textPrimary),
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
                              style: TextStyle(
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
                              style: const TextStyle(
                                color: DanjiColors.textPrimary,
                              ),
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
                    const SizedBox(height: 16),
                    SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            '문 잠금',
                            style: TextStyle(
                              color: DanjiColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '반납 전 차량 문을 잠그고 직접 확인해 주세요.',
                            style: TextStyle(
                              color: DanjiColors.textSecondary,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 14),
                          SmartKeyDoorButton(
                            label: '문닫힘',
                            icon: Icons.lock_rounded,
                            variant: SmartKeyDoorButtonVariant.lock,
                            enabled: !_doorLockConfirmed && !_doorLockLoading,
                            loading: _doorLockLoading,
                            onPressed: _onDoorLock,
                          ),
                          if (_doorLockConfirmed) ...[
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  size: 18,
                                  color: DanjiColors.buttonBlue,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '문 잠금 확인 완료',
                                  style: TextStyle(
                                    color: DanjiColors.buttonBlue,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
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
                    if (!_doorLockConfirmed) ...[
                      const SizedBox(height: 12),
                      const Text(
                        '문 잠금 확인 후 반납할 수 있습니다.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: DanjiColors.textMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 60,
                      child: FilledButton(
                        onPressed: _doorLockConfirmed && !_submitting
                            ? _submit
                            : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: DanjiColors.brandBlue,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: DanjiColors.textMuted,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
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
                            : const Text(
                                '반납하기',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
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
          style: const TextStyle(color: DanjiColors.toneRed),
        ),
      ),
    );
  }
}
