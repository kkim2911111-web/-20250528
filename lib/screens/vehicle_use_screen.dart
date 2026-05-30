import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models/reservation.dart';
import '../services/rental_service.dart';
import '../theme/danji_colors.dart';
import '../utils/rental_navigation.dart';
import '../widgets/danji_app_bar.dart';
import '../widgets/section_card.dart';

/// 예약 완료 후 차량 이용 화면 (사진 등록 · 도어 제어 · 반납)
class VehicleUseScreen extends StatefulWidget {
  final String reservationId;

  const VehicleUseScreen({super.key, required this.reservationId});

  @override
  State<VehicleUseScreen> createState() => _VehicleUseScreenState();
}

class _VehicleUseScreenState extends State<VehicleUseScreen> {
  static const _preDriveLabels = [
    '전면',
    '후면',
    '좌측',
    '우측',
    '측면(전방,좌)',
    '측면(전방,우)',
    '측면(후방,좌)',
    '측면(후방,우)',
    '실내',
    '계기판',
  ];

  final _service = RentalService();
  final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');
  final _picker = ImagePicker();

  Reservation? _reservation;
  bool _loading = true;
  String? _error;
  bool _doorUnlocked = false;

  /// index → photo bytes (10 slots)
  final List<Uint8List?> _preDrivePhotos =
      List<Uint8List?>.filled(_preDriveLabels.length, null);

  bool get _preDrivePhotosComplete =>
      _preDrivePhotos.every((p) => p != null);

  int get _registeredCount =>
      _preDrivePhotos.where((p) => p != null).length;

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

      if (!_canOpenUseScreen(reservation)) {
        setState(() {
          _loading = false;
          _error = '이 예약은 차량 이용 화면을 열 수 없습니다. (${reservation.statusLabel})';
        });
        return;
      }

      // DB에 이미 등록된 운행 전 사진이 있으면 완료 처리
      final alreadyComplete = reservation.pickupPhotos.length >= 10;

      setState(() {
        _reservation = reservation;
        _loading = false;
        if (alreadyComplete && !_preDrivePhotosComplete) {
          // URL만 있고 로컬 바이트는 없지만 등록 완료로 간주
          _markPreDriveCompleteFromServer();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  bool _canOpenUseScreen(Reservation r) => r.status == 'in_use';

  void _markPreDriveCompleteFromServer() {
    // 서버에 10장 이상 저장된 경우 문열림 허용 (placeholder bytes)
    for (var i = 0; i < _preDrivePhotos.length; i++) {
      _preDrivePhotos[i] ??= Uint8List(0);
    }
  }

  bool get _photosCompleteForDoors {
    if (_preDrivePhotosComplete) return true;
    final r = _reservation;
    return r != null && r.pickupPhotos.length >= 10;
  }

  Future<void> _openPreDrivePhotoSheet() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SectionCard.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _PreDrivePhotoSheet(
        labels: _preDriveLabels,
        initialPhotos: List<Uint8List?>.from(_preDrivePhotos),
        picker: _picker,
        onComplete: (photos) {
          for (var i = 0; i < photos.length; i++) {
            _preDrivePhotos[i] = photos[i];
          }
        },
      ),
    );

    if (saved == true && mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('운행 전 사진 등록이 완료되었습니다.')),
      );
    }
  }

  void _onUnlockDoor() {
    if (!_photosCompleteForDoors) return;
    setState(() => _doorUnlocked = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('문 열림 (도어 API 연동 예정)')),
    );
  }

  void _onLockDoor() {
    setState(() => _doorUnlocked = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('문 닫힘 (도어 API 연동 예정)')),
    );
  }

  void _showVehicleInfo() {
    final r = _reservation;
    if (r == null) return;
    final v = r.vehicle;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: SectionCard.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '차량 정보',
              style: TextStyle(
                color: DanjiColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            _InfoLine('차량명', v?.name ?? '-'),
            _InfoLine('차종', v?.vehicleType ?? '-'),
            _InfoLine('차량번호', v?.carNumber ?? '-'),
            _InfoLine('주차위치', v?.parkingLocation ?? '-'),
            _InfoLine('요금', v?.priceLabel ?? '-'),
            if (r.startAt != null && r.endAt != null)
              _InfoLine(
                '예약시간',
                '${_dateFormat.format(r.startAt!)} ~ ${_dateFormat.format(r.endAt!)}',
              ),
            _InfoLine('예약 상태', r.statusLabel),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _onReturn() async {
    if (!_photosCompleteForDoors) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('반납 전 운행 전 필수 사진을 먼저 등록해주세요.'),
        ),
      );
      return;
    }

    final reservation = _reservation;
    if (reservation == null) return;

    final result = await openRentalReturn<bool>(context, reservation);
    if (result == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reservation = _reservation;
    final vehicle = reservation?.vehicle;

    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: const DanjiAppBar(title: '차량 이용', light: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: DanjiColors.accentRed),
                    ),
                  ),
                )
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
                          const SizedBox(height: 8),
                          _InfoLine('차종', vehicle?.vehicleType ?? '-'),
                          if (reservation!.startAt != null &&
                              reservation.endAt != null)
                            _InfoLine(
                              '예약시간',
                              '${_dateFormat.format(reservation.startAt!)} ~ '
                              '${_dateFormat.format(reservation.endAt!)}',
                            ),
                          _InfoLine(
                            '주차위치',
                            vehicle?.parkingLocation ?? '정보 없음',
                          ),
                          if (_doorUnlocked) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: DanjiColors.rentalBlue.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                '도어 열림 상태',
                                style: TextStyle(
                                  color: DanjiColors.rentalBlue,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
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
                            '운행 전 필수 사진',
                            style: TextStyle(
                              color: DanjiColors.textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _photosCompleteForDoors
                                ? '10장 등록 완료 — 문열림을 사용할 수 있습니다.'
                                : '전면/후면/좌우/측면/실내/계기판 총 10장을 등록해주세요.',
                            style: const TextStyle(
                              color: DanjiColors.textSecondary,
                              height: 1.4,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _openPreDrivePhotoSheet,
                            icon: Icon(
                              _photosCompleteForDoors
                                  ? Icons.check_circle
                                  : Icons.add_a_photo_outlined,
                              color: _photosCompleteForDoors
                                  ? DanjiColors.rentalBlue
                                  : DanjiColors.rentalBlue,
                            ),
                            label: Text(
                              _photosCompleteForDoors
                                  ? '운행 전 사진 등록 완료'
                                  : '운행 전 필수 사진 등록 ($_registeredCount/10)',
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: DanjiColors.textPrimary,
                              side: BorderSide(
                                color: _photosCompleteForDoors
                                    ? DanjiColors.rentalBlue
                                    : DanjiColors.rentalBlue,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    _DoorButton(
                      label: '문열림',
                      icon: Icons.lock_open_rounded,
                      color: DanjiColors.rentalBlue,
                      enabled: _photosCompleteForDoors,
                      onPressed: _onUnlockDoor,
                    ),
                    const SizedBox(height: 12),
                    _DoorButton(
                      label: '문닫힘',
                      icon: Icons.lock_rounded,
                      color: DanjiColors.accentRed,
                      enabled: true,
                      onPressed: _onLockDoor,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _showVehicleInfo,
                      icon: const Icon(Icons.info_outline),
                      label: const Text('차량 정보 확인'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: DanjiColors.textPrimary,
                        side: const BorderSide(color: DanjiColors.textSecondary),
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _onReturn,
                      icon: const Icon(Icons.keyboard_return),
                      label: const Text('반납하기 (반납 사진 필수)'),
                      style: FilledButton.styleFrom(
                        backgroundColor: DanjiColors.rentalBlue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(52),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    if (!_photosCompleteForDoors) ...[
                      const SizedBox(height: 12),
                      const Text(
                        '※ 운행 전 사진 10장 등록 후 문열림 및 반납이 가능합니다.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: DanjiColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ],
                ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;

  const _InfoLine(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                color: DanjiColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: DanjiColors.textPrimary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DoorButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool enabled;
  final VoidCallback onPressed;

  const _DoorButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 28),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: color.withValues(alpha: 0.25),
          disabledForegroundColor: Colors.white38,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

class _PreDrivePhotoSheet extends StatefulWidget {
  final List<String> labels;
  final List<Uint8List?> initialPhotos;
  final ImagePicker picker;
  final ValueChanged<List<Uint8List?>> onComplete;

  const _PreDrivePhotoSheet({
    required this.labels,
    required this.initialPhotos,
    required this.picker,
    required this.onComplete,
  });

  @override
  State<_PreDrivePhotoSheet> createState() => _PreDrivePhotoSheetState();
}

class _PreDrivePhotoSheetState extends State<_PreDrivePhotoSheet> {
  late List<Uint8List?> _photos;

  @override
  void initState() {
    super.initState();
    _photos = List<Uint8List?>.from(widget.initialPhotos);
  }

  bool get _complete => _photos.every((p) => p != null);

  Future<void> _pick(int index, ImageSource source) async {
    final picked = await widget.picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() => _photos[index] = bytes);
  }

  void _remove(int index) {
    setState(() => _photos[index] = null);
  }

  void _save() {
    if (!_complete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('10장 모두 등록해주세요.')),
      );
      return;
    }
    widget.onComplete(_photos);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final maxH = MediaQuery.of(context).size.height * 0.75;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '운행 전 필수 사진 (10장)',
                  style: TextStyle(
                    color: DanjiColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${_photos.where((p) => p != null).length}/10',
                style: const TextStyle(
                  color: DanjiColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: maxH,
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: List.generate(widget.labels.length, (i) {
                  return _PhotoSlot(
                    label: widget.labels[i],
                    bytes: _photos[i],
                    onCamera: () => _pick(i, ImageSource.camera),
                    onGallery: () => _pick(i, ImageSource.gallery),
                    onRemove: () => _remove(i),
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(
              backgroundColor:
                  _complete ? DanjiColors.rentalBlue : DanjiColors.border,
              foregroundColor:
                  _complete ? Colors.white : DanjiColors.textSecondary,
              minimumSize: const Size.fromHeight(48),
            ),
            child: Text(_complete ? '등록 완료' : '10장 모두 촬영해주세요'),
          ),
        ],
      ),
    );
  }
}

class _PhotoSlot extends StatelessWidget {
  final String label;
  final Uint8List? bytes;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onRemove;

  const _PhotoSlot({
    required this.label,
    required this.bytes,
    required this.onCamera,
    required this.onGallery,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    const w = 150.0;

    return SizedBox(
      width: w,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: bytes != null
                  ? DanjiColors.buttonBlue
                  : DanjiColors.accentRed,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 4),
          if (bytes != null)
            Stack(
              clipBehavior: Clip.none,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.memory(
                    bytes!,
                    width: w,
                    height: 100,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: -4,
                  right: -4,
                  child: GestureDetector(
                    onTap: onRemove,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.black87,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ],
            )
          else
            Container(
              width: w,
              height: 100,
              decoration: BoxDecoration(
                color: DanjiColors.skyLight,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: DanjiColors.accentRed.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: onCamera,
                        icon: const Icon(Icons.photo_camera_outlined,
                            color: DanjiColors.textSecondary, size: 20),
                        tooltip: '촬영',
                      ),
                      IconButton(
                        onPressed: onGallery,
                        icon: const Icon(Icons.photo_library_outlined,
                            color: DanjiColors.textSecondary, size: 20),
                        tooltip: '앨범',
                      ),
                    ],
                  ),
                  const Text(
                    '미등록',
                    style: TextStyle(
                      color: DanjiColors.accentRed,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
