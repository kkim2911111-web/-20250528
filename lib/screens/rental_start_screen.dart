import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../controllers/rental_start_controller.dart';
import '../models/my_page_profile.dart';
import '../screens/main_shell.dart';
import '../services/rental_service.dart';
import '../services/rental_start_service.dart';
import '../theme/danji_colors.dart';
import '../theme/danji_typography.dart';
import '../widgets/danji_app_bar.dart';
import '../widgets/license_registration_sheet.dart';
import '../widgets/rental_pickup_photo_grid.dart';
import '../widgets/section_card.dart';

/// 대여하기 — 사진 → 면허 → 문열림 (한 화면 3단계)
class RentalStartScreen extends StatefulWidget {
  final String reservationId;

  const RentalStartScreen({super.key, required this.reservationId});

  @override
  State<RentalStartScreen> createState() => _RentalStartScreenState();
}

class _RentalStartScreenState extends State<RentalStartScreen> {
  final _ctrl = RentalStartController();
  final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_rebuild);
    _ctrl.load(widget.reservationId);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_rebuild);
    _ctrl.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Future<void> _pickGallery() async {
    await _ctrl.pickFromGalleryAndUpload(widget.reservationId);
    if (!mounted) return;
    if (_ctrl.photosUploaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('사진 등록이 완료되었습니다.')),
      );
    }
  }

  Future<void> _takePhoto() async {
    await _ctrl.takePhotoAndUpload(widget.reservationId);
    if (!mounted) return;
    if (_ctrl.photosUploaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('사진 등록이 완료되었습니다.')),
      );
    }
  }

  Future<void> _openLicenseRegistration() async {
    final profile = _ctrl.profile;
    if (profile == null) return;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: DanjiColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => LicenseRegistrationSheet(
        initialNumber: profile.licenseNumber ?? '',
        initialExpiry: profile.licenseExpiry ?? '',
      ),
    );

    if (saved == true && mounted) {
      await _ctrl.load(widget.reservationId);
    }
  }

  Future<void> _confirmLicense() async {
    final profile = _ctrl.profile;
    if (profile != null && !profile.isLicenseComplete) {
      await _openLicenseRegistration();
      return;
    }

    final ok = await _ctrl.confirmLicense(widget.reservationId);
    if (!mounted || !ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('면허 확인이 완료되었습니다.')),
    );
  }

  Future<void> _unlock() async {
    final ok = await _ctrl.unlockAndStart(widget.reservationId);
    if (!mounted || !ok) return;

    RentalService.signalListRefresh();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainShell()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_ctrl.loading) {
      return const Scaffold(
        backgroundColor: DanjiColors.background,
        appBar: DanjiAppBar(title: '대여하기', light: true),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final reservation = _ctrl.reservation;
    if (reservation == null) {
      return Scaffold(
        backgroundColor: DanjiColors.background,
        appBar: const DanjiAppBar(title: '대여하기', light: true),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _ctrl.error ?? '예약 정보를 불러올 수 없습니다.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: DanjiColors.accentRed),
            ),
          ),
        ),
      );
    }

    final vehicle = reservation.vehicle;

    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: const DanjiAppBar(title: '대여하기', light: true),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vehicle?.name ?? '차량',
                        style: DanjiTypography.subtitleLarge,
                      ),
                      if (vehicle?.carNumber != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '번호: ${vehicle!.carNumber}',
                          style: DanjiTypography.secondary,
                        ),
                      ],
                      if (vehicle?.parkingLocation != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '주차: ${vehicle!.parkingLocation}',
                          style: DanjiTypography.secondary,
                        ),
                      ],
                      if (reservation.startAt != null &&
                          reservation.endAt != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          '예약: ${_dateFormat.format(reservation.startAt!)} ~ '
                          '${_dateFormat.format(reservation.endAt!)}',
                          style: DanjiTypography.secondary.copyWith(height: 1.4),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _StepBar(
                  step1Done: _ctrl.step1Complete,
                  step2Done: _ctrl.step2Complete,
                  step3Done: reservation.status == 'in_use',
                  active: _ctrl.activeStep,
                ),
                const SizedBox(height: 16),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      RentalPickupPhotoGrid(
                        photos: _ctrl.localPhotos,
                        locked: _ctrl.photosUploaded,
                        uploading: _ctrl.uploading,
                        uploadProgress: _ctrl.uploadProgress,
                        uploadTotal: _ctrl.uploadTotal,
                        onBulkGallery: _ctrl.canPickPhotos ? _pickGallery : null,
                        onCamera: _ctrl.canPickPhotos ? _takePhoto : null,
                        onRetryUpload: _ctrl.canPickPhotos &&
                                _ctrl.localPhotos.length >= 6
                            ? () => _ctrl.retryUpload(widget.reservationId)
                            : null,
                        onRemove: _ctrl.removePhotoAt,
                      ),
                      if (_ctrl.photosUploaded)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: _DoneLabel(text: '사진 등록 완료'),
                        )
                      else if (_ctrl.localPhotos.isNotEmpty &&
                          _ctrl.localPhotos.length <
                              RentalStartService.minPhotos)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            '최소 ${RentalStartService.minPhotos}장 이상 선택해주세요. '
                            '(현재 ${_ctrl.localPhotos.length}장)',
                            textAlign: TextAlign.center,
                            style: DanjiTypography.secondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _BottomActions(
            ctrl: _ctrl,
            profile: _ctrl.profile,
            onConfirmLicense: _confirmLicense,
            onUnlock: _unlock,
          ),
        ],
      ),
    );
  }
}

class _StepBar extends StatelessWidget {
  final bool step1Done;
  final bool step2Done;
  final bool step3Done;
  final RentalStartStep active;

  const _StepBar({
    required this.step1Done,
    required this.step2Done,
    required this.step3Done,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Row(
        children: [
          _StepChip(
            step: 1,
            label: '사진',
            done: step1Done,
            active: active == RentalStartStep.photos,
          ),
          _line(step1Done),
          _StepChip(
            step: 2,
            label: '면허',
            done: step2Done,
            active: active == RentalStartStep.license,
          ),
          _line(step2Done),
          _StepChip(
            step: 3,
            label: '문열림',
            done: step3Done,
            active: active == RentalStartStep.unlock,
          ),
        ],
      ),
    );
  }

  Widget _line(bool done) {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 18),
        color: done
            ? DanjiColors.rentalBlue.withValues(alpha: 0.5)
            : DanjiColors.border,
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  final int step;
  final String label;
  final bool done;
  final bool active;

  const _StepChip({
    required this.step,
    required this.label,
    required this.done,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final color = done
        ? DanjiColors.rentalBlue
        : active
            ? DanjiColors.buttonBlue
            : DanjiColors.textMuted;

    return Column(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: done || active
                ? color.withValues(alpha: 0.12)
                : DanjiColors.background,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: active ? 2 : 1),
          ),
          child: Center(
            child: done
                ? Icon(Icons.check, size: 16, color: color)
                : Text(
                    '$step',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _DoneLabel extends StatelessWidget {
  final String text;

  const _DoneLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.check_circle, color: DanjiColors.rentalBlue, size: 18),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            color: DanjiColors.rentalBlue,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

class _BottomActions extends StatelessWidget {
  final RentalStartController ctrl;
  final MyPageProfile? profile;
  final VoidCallback onConfirmLicense;
  final VoidCallback onUnlock;

  const _BottomActions({
    required this.ctrl,
    required this.profile,
    required this.onConfirmLicense,
    required this.onUnlock,
  });

  @override
  Widget build(BuildContext context) {
    final licenseDone = ctrl.step2Complete;
    final canLicense = ctrl.canConfirmLicense;
    final canUnlock = ctrl.canUnlock;

    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: DanjiColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (licenseDone) const _DoneLabel(text: '면허 확인 완료'),
          if (licenseDone) const SizedBox(height: 10),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: licenseDone
                  ? null
                  : (canLicense ? onConfirmLicense : null),
              icon: ctrl.confirmingLicense
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(licenseDone ? Icons.check_circle : Icons.badge_outlined),
              label: Text(licenseDone ? '면허 확인 완료' : '면허 확인'),
              style: FilledButton.styleFrom(
                backgroundColor: DanjiColors.buttonBlue,
                disabledBackgroundColor:
                    DanjiColors.textMuted.withValues(alpha: 0.35),
                disabledForegroundColor: DanjiColors.textMuted,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: DanjiTypography.buttonPrimary.copyWith(
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 56,
            child: FilledButton.icon(
              onPressed: canUnlock && !ctrl.unlocking ? onUnlock : null,
              icon: ctrl.unlocking
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.lock_open_rounded, size: 26),
              label: const Text('문열림'),
              style: FilledButton.styleFrom(
                backgroundColor: DanjiColors.rentalBlue,
                disabledBackgroundColor:
                    DanjiColors.textMuted.withValues(alpha: 0.35),
                disabledForegroundColor: Colors.white54,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: DanjiTypography.buttonPrimary.copyWith(
                  fontSize: 18,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _hint(ctrl),
            textAlign: TextAlign.center,
            style: DanjiTypography.caption.copyWith(
              height: 1.4,
            ),
          ),
          if (ctrl.error != null) ...[
            const SizedBox(height: 8),
            Text(
              ctrl.error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: DanjiColors.accentRed,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _hint(RentalStartController ctrl) {
    if (!ctrl.step1Complete) {
      return '사진 등록 완료 후 면허 확인 버튼이 활성화됩니다.';
    }
    if (!ctrl.step2Complete) {
      final p = profile;
      if (p != null && !p.isLicenseComplete) {
        return '면허 정보 등록 후 확인 버튼을 눌러주세요.';
      }
      return '면허 확인 후 문열림 버튼이 활성화됩니다.';
    }
    return '문열림과 동시에 대여가 시작되며 홈 화면으로 이동합니다.';
  }
}
