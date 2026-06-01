import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/my_page_profile.dart';
import '../models/reservation.dart';
import '../services/my_page_service.dart';
import '../services/rental_service.dart';
import '../services/rental_start_service.dart';

enum RentalStartStep { photos, license, unlock }

/// 대여하기 화면 상태
class RentalStartController extends ChangeNotifier {
  RentalStartController({
    RentalStartService? service,
    MyPageService? profileService,
    ImagePicker? picker,
  })  : _service = service ?? RentalStartService(),
        _profileService = profileService ?? MyPageService(),
        _picker = picker ?? ImagePicker();

  final RentalStartService _service;
  final MyPageService _profileService;
  final ImagePicker _picker;

  Reservation? reservation;
  MyPageProfile? profile;

  /// 선택된 사진 (순서대로 1~10장, 앞 6장은 필수 슬롯 라벨 표시용)
  List<Uint8List> localPhotos = [];
  List<String> uploadedPhotoUrls = [];

  bool loading = true;
  bool uploading = false;
  bool confirmingLicense = false;
  bool unlocking = false;
  int uploadProgress = 0;
  int uploadTotal = RentalStartService.minPhotos;
  String? error;

  /// DB photos_uploaded=true 일 때만 완료
  bool get photosUploaded => reservation?.photosUploaded == true;

  bool get licenseVerified => reservation?.licenseVerified == true;

  bool get step1Complete => photosUploaded;

  bool get step2Complete => licenseVerified;

  bool get canPickPhotos => !photosUploaded && !uploading;

  bool get canConfirmLicense {
    if (!photosUploaded || step2Complete) return false;
    if (confirmingLicense || unlocking || uploading) return false;
    return true;
  }

  bool get canUnlock {
    if (!photosUploaded || !step2Complete) return false;
    if (unlocking || uploading || confirmingLicense) return false;
    final r = reservation;
    if (r == null) return false;
    if (r.status == 'in_use') return false;
    return r.canStartRental;
  }

  RentalStartStep get activeStep {
    if (!step1Complete) return RentalStartStep.photos;
    if (!step2Complete) return RentalStartStep.license;
    return RentalStartStep.unlock;
  }

  List<String> get pickupUrlsForStart {
    if (reservation?.pickupPhotos.length != null &&
        reservation!.pickupPhotos.length >= RentalStartService.minPhotos) {
      return reservation!.pickupPhotos;
    }
    if (uploadedPhotoUrls.length >= RentalStartService.minPhotos) {
      return uploadedPhotoUrls;
    }
    return const [];
  }

  Future<void> load(String reservationId) async {
    loading = true;
    error = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _service.fetchReservation(reservationId),
        _profileService.fetchProfile(),
      ]);
      final r = results[0] as Reservation;
      profile = results[1] as MyPageProfile;
      reservation = r;

      if (r.status != 'confirmed' &&
          r.status != 'pending' &&
          r.status != 'in_use') {
        error = '대여를 시작할 수 없는 예약입니다. (${r.statusLabel})';
        loading = false;
        notifyListeners();
        return;
      }

      if (r.status != 'in_use' && r.isTooEarlyForRentalStart) {
        error = RentalStartMessages.tooEarly;
        loading = false;
        notifyListeners();
        return;
      }

      if (r.photosUploaded && r.pickupPhotos.isNotEmpty) {
        uploadedPhotoUrls = r.pickupPhotos;
      }

      loading = false;
      notifyListeners();
    } catch (e) {
      error = _cleanError(e);
      loading = false;
      notifyListeners();
    }
  }

  /// 갤러리에서 최대 10장 일괄 선택 → 즉시 업로드
  Future<void> pickFromGalleryAndUpload(String reservationId) async {
    if (!canPickPhotos) return;

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

    await _applyPhotosAndUpload(reservationId, bytes);
  }

  /// 카메라 1장 추가 → 6장 이상이면 즉시 업로드
  Future<void> takePhotoAndUpload(String reservationId) async {
    if (!canPickPhotos) return;
    if (localPhotos.length >= RentalStartService.maxPhotos) {
      error = '사진은 최대 ${RentalStartService.maxPhotos}장까지 등록할 수 있습니다.';
      notifyListeners();
      return;
    }

    final file = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (file == null) return;

    final next = [...localPhotos, await file.readAsBytes()];
    if (next.length < RentalStartService.minPhotos) {
      localPhotos = next;
      error = null;
      notifyListeners();
      return;
    }

    await _applyPhotosAndUpload(reservationId, next);
  }

  void removePhotoAt(int index) {
    if (photosUploaded || uploading) return;
    if (index < 0 || index >= localPhotos.length) return;
    localPhotos = [...localPhotos]..removeAt(index);
    error = null;
    notifyListeners();
  }

  Future<void> retryUpload(String reservationId) async {
    if (photosUploaded || uploading) return;
    if (localPhotos.length < RentalStartService.minPhotos) {
      error = '최소 ${RentalStartService.minPhotos}장 이상 선택해주세요.';
      notifyListeners();
      return;
    }
    await _uploadPhotos(reservationId, localPhotos);
  }

  Future<void> _applyPhotosAndUpload(
    String reservationId,
    List<Uint8List> bytes,
  ) async {
    if (bytes.length < RentalStartService.minPhotos) {
      localPhotos = bytes;
      error =
          '최소 ${RentalStartService.minPhotos}장 이상 선택해주세요. (현재 ${bytes.length}장)';
      notifyListeners();
      return;
    }

    localPhotos = bytes.take(RentalStartService.maxPhotos).toList();
    error = null;
    notifyListeners();
    await _uploadPhotos(reservationId, localPhotos);
  }

  Future<void> _uploadPhotos(
    String reservationId,
    List<Uint8List> photos,
  ) async {
    uploading = true;
    uploadProgress = 0;
    uploadTotal = photos.length;
    error = null;
    notifyListeners();

    try {
      final urls = await _service.uploadPickupPhotos(
        reservationId: reservationId,
        photos: photos,
        onProgress: (done, total) {
          uploadProgress = done;
          uploadTotal = total;
          notifyListeners();
        },
      );
      uploadedPhotoUrls = urls;
      reservation = await _service.fetchReservation(reservationId);

      if (reservation?.photosUploaded != true) {
        debugPrint(
          '[rental-start] 컨트롤러 업로드 실패 reservationId=$reservationId '
          'photos_uploaded=${reservation?.photosUploaded}',
        );
        throw const RentalException(
          '사진 업로드 후 photos_uploaded=true 가 DB에 저장되지 않았습니다.',
        );
      }

      debugPrint(
        '[rental-start] 컨트롤러 업로드 성공 reservationId=$reservationId '
        'photos_uploaded=${reservation!.photosUploaded} '
        'urlCount=${uploadedPhotoUrls.length}',
      );
      uploading = false;
      notifyListeners();
    } catch (e) {
      debugPrint(
        '[rental-start] 컨트롤러 업로드 실패 reservationId=$reservationId '
        'error=${_cleanError(e)}',
      );
      error = _cleanError(e);
      uploading = false;
      notifyListeners();
    }
  }

  Future<bool> confirmLicense(String reservationId) async {
    if (!canConfirmLicense) return false;

    confirmingLicense = true;
    error = null;
    notifyListeners();

    try {
      reservation = await _service.fetchReservation(reservationId);
      if (reservation?.photosUploaded != true) {
        throw const RentalException(
          '사진 등록이 완료되지 않았습니다. 업로드 완료 후 다시 시도해주세요.',
        );
      }

      await _service.confirmLicense(reservationId);
      reservation = await _service.fetchReservation(reservationId);
      confirmingLicense = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = _cleanError(e);
      confirmingLicense = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> unlockAndStart(String reservationId) async {
    if (!canUnlock) return false;

    unlocking = true;
    error = null;
    notifyListeners();

    try {
      reservation = await _service.startRental(
        reservationId: reservationId,
        pickupPhotoUrls: pickupUrlsForStart,
      );
      unlocking = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = _cleanError(e);
      unlocking = false;
      notifyListeners();
      return false;
    }
  }

  String _cleanError(Object e) {
    final msg = e.toString().replaceFirst('RentalException: ', '');
    if (msg.contains('photos_required') || msg.contains('photos_not_uploaded')) {
      return '사진 등록이 DB에 반영되지 않았습니다.\n'
          '갤러리에서 6장 이상 선택 후 업로드가 완료된 뒤 다시 시도해주세요.';
    }
    if (msg.contains('license_verified_self_change_forbidden')) {
      return '면허 확인 SQL이 적용되지 않았습니다.\n'
          'Supabase에서 fix_confirm_rental_license_for_me.sql 을 실행해주세요.';
    }
    if (msg.contains('license_info_required')) {
      return '면허번호와 만료일을 먼저 등록해주세요.';
    }
    return msg;
  }
}
