import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/my_page_profile.dart';
import '../models/rental_flow_status.dart';
import '../models/reservation.dart';
import '../services/license_service.dart';
import '../services/my_page_service.dart';
import '../services/rental_service.dart';
import '../services/smart_key_door_service.dart';
import '../utils/rental_navigation.dart';
import '../widgets/rental_start_photo_section.dart';
import '../widgets/smart_key_door_buttons.dart';

/// 예약 카드 UI 단계
enum ReservationCardPhase {
  beforeRental,
  inRental,
  finished,
}

enum HomeReservationMode {
  confirmedBeforeWindow,
  confirmedInWindow,
  inUse,
}

/// 홈·내 예약·대여하기 — 3단계 선형 플로우 + 차량 제어 통합
class ReservationController extends ChangeNotifier {
  ReservationController({
    RentalService? rentalService,
    MyPageService? myPageService,
    LicenseService? licenseService,
    SmartKeyDoorService? doorService,
  })  : _rentalService = rentalService ?? RentalService(),
        _myPageService = myPageService ?? MyPageService(),
        _licenseService = licenseService ?? LicenseService(),
        _doorService = doorService ?? SmartKeyDoorService();

  final RentalService _rentalService;
  final MyPageService _myPageService;
  final LicenseService _licenseService;
  final SmartKeyDoorService _doorService;

  Reservation? reservation;
  MyPageProfile? profile;

  PhotoFlowStatus photoStatus = PhotoFlowStatus.none;
  LicenseFlowStatus licenseStatus = LicenseFlowStatus.none;
  DoorFlowStatus doorStatus = DoorFlowStatus.locked;

  /// 이번 대여하기 화면에서 면허 확인 버튼을 눌렀는지
  bool licenseVerifiedThisSession = false;

  bool loading = false;
  bool uploadingPhotos = false;
  bool verifyingLicense = false;
  bool unlocking = false;
  int uploadProgress = 0;
  int uploadTotal = RentalStartPhotoSection.minPhotos;
  String? error;

  List<Uint8List> localPhotos = [];

  int get activeStep {
    if (!isPhotoStepComplete) return 1;
    if (!isLicenseVerified) return 2;
    return 3;
  }

  /// 서버에 6장 업로드 완료 후에만 true
  bool get isPhotoStepComplete => photoStatus == PhotoFlowStatus.complete;

  bool get isLicenseVerified =>
      licenseVerifiedThisSession && licenseStatus == LicenseFlowStatus.approved;

  bool get canVerifyLicense =>
      isPhotoStepComplete &&
      !isLicenseVerified &&
      !verifyingLicense &&
      !unlocking;

  bool get canUnlockDoorInFlow {
    if (unlocking || uploadingPhotos) return false;
    if (!isLicenseVerified || !isPhotoStepComplete) return false;
    final r = reservation;
    if (r == null) return false;
    return r.canStartRental;
  }

  bool canUnlockDoor(Reservation r) {
    if (r.status != 'in_use') return false;
    return r.canUnlockDoor;
  }

  Future<void> loadForRentalStart(String reservationId) async {
    loading = true;
    error = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _rentalService.fetchReservation(reservationId),
        _myPageService.fetchProfile(),
      ]);
      final r = results[0] as Reservation;
      final p = results[1] as MyPageProfile;

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

      reservation = r;
      profile = p;
      _syncFlowFromData(r);
      loading = false;
      notifyListeners();
    } catch (e) {
      error = e.toString();
      loading = false;
      notifyListeners();
    }
  }

  void _syncFlowFromData(Reservation r) {
    photoStatus = (r.photosUploaded || r.hasPickupPhotosComplete)
        ? PhotoFlowStatus.complete
        : PhotoFlowStatus.none;

    // DB에 면허 확인 완료가 있으면 2단계 복원, 없으면 이번 세션에서만 진행
    if (r.licenseVerified || licenseVerifiedThisSession) {
      licenseStatus = LicenseFlowStatus.approved;
      licenseVerifiedThisSession = true;
    } else {
      licenseStatus = LicenseFlowStatus.none;
    }

    doorStatus =
        r.doorUnlocked ? DoorFlowStatus.unlocked : DoorFlowStatus.locked;
  }

  void syncLocalPhotos(List<Uint8List> photos) {
    localPhotos = photos;
    notifyListeners();
  }

  Future<void> uploadPhotos(String reservationId, List<Uint8List> photos) async {
    if (photos.length < RentalStartPhotoSection.minPhotos) return;

    uploadingPhotos = true;
    uploadProgress = 0;
    uploadTotal = photos.length;
    error = null;
    notifyListeners();

    try {
      await _rentalService.savePickupPhotos(
        reservationId: reservationId,
        photos: photos,
        onProgress: (completed, total) {
          uploadProgress = completed;
          uploadTotal = total;
          notifyListeners();
        },
      );
      photoStatus = PhotoFlowStatus.complete;
      localPhotos = photos;
      licenseVerifiedThisSession = false;
      licenseStatus = LicenseFlowStatus.none;
      await loadForRentalStart(reservationId);
      uploadingPhotos = false;
      notifyListeners();
    } catch (e) {
      error = e.toString().replaceFirst('RentalException: ', '');
      uploadingPhotos = false;
      notifyListeners();
    }
  }

  Future<bool> verifyLicense({
    required BuildContext context,
    required String reservationId,
    required VoidCallback onNeedRegister,
  }) async {
    if (!isPhotoStepComplete) return false;

    final p = profile;
    if (p == null) return false;

    if (!p.isLicenseComplete) {
      onNeedRegister();
      return false;
    }

    verifyingLicense = true;
    error = null;
    notifyListeners();

    try {
      final approved =
          await _licenseService.confirmRentalLicenseForMe(reservationId);

      if (!approved) {
        error = '면허 확인에 실패했습니다. 면허 정보를 다시 확인해주세요.';
        verifyingLicense = false;
        notifyListeners();
        return false;
      }

      licenseStatus = LicenseFlowStatus.approved;
      licenseVerifiedThisSession = true;
      verifyingLicense = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
      verifyingLicense = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> unlockAndStartRental(
    BuildContext context,
    String reservationId,
  ) async {
    if (!canUnlockDoorInFlow) return false;

    unlocking = true;
    error = null;
    notifyListeners();

    try {
      // 1) DB status → in_use (RPC start_rental_for_me 또는 direct fallback)
      final r = await _rentalService.startRentalAndFetchInUse(
        reservationId: reservationId,
      );
      reservation = r;

      if (r.status != 'in_use') {
        throw const RentalException(
          '대여 시작이 DB에 반영되지 않았습니다. 문열림을 진행할 수 없습니다.',
        );
      }

      // 2) in_use 확인 후에만 도어 제어 + 팝업
      await _doorService.setDoorLock(
        reservationId: reservationId,
        unlocked: true,
        context: context,
      );

      if (!context.mounted) return false;

      doorStatus = DoorFlowStatus.unlocked;
      unlocking = false;
      RentalService.clearQueryCache();
      RentalService.signalListRefresh();
      notifyListeners();

      await SmartKeyDoorFeedback.showUnlockSuccess(context);
      return true;
    } catch (e) {
      error = e.toString().replaceFirst('RentalException: ', '');
      unlocking = false;
      notifyListeners();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error!)),
        );
      }
      return false;
    }
  }

  ReservationCardPhase cardPhase(Reservation r) {
    if (r.isFinished || r.isCancelled || r.isInUsageHistory) {
      return ReservationCardPhase.finished;
    }
    if (r.status == 'in_use') return ReservationCardPhase.inRental;
    return ReservationCardPhase.beforeRental;
  }

  bool showStartButton(Reservation r) {
    if (r.status == 'in_use') return false;
    if (r.isEffectivelyFinished) return false;
    return r.showRentalStartButton;
  }

  bool canStartRental(Reservation r) {
    if (!showStartButton(r)) return false;
    return r.canStartRental;
  }

  bool isTooEarlyForStart(Reservation r) => r.isTooEarlyForRentalStart;

  bool canReturn(Reservation r) => r.status == 'in_use';

  Future<bool?> startRental(BuildContext context, Reservation r) async {
    if (isTooEarlyForStart(r)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(RentalStartMessages.tooEarly)),
      );
      return null;
    }
    return openRentalOrUseScreen<bool>(context, r);
  }

  Future<bool?> returnVehicle(BuildContext context, Reservation r) {
    return openRentalReturn<bool>(context, r);
  }

  Future<void> controlDoor(
    BuildContext context, {
    required Reservation r,
    required bool unlock,
    VoidCallback? onChanged,
  }) {
    if (unlock) {
      return SmartKeyDoorActions.unlock(
        context,
        reservation: r,
        service: _doorService,
        onSuccess: onChanged,
      );
    }
    return SmartKeyDoorActions.lock(
      context,
      reservation: r,
      service: _doorService,
      onSuccess: onChanged,
    );
  }

  Future<void> unlockDoor(
    BuildContext context,
    Reservation r, {
    VoidCallback? onChanged,
  }) =>
      controlDoor(context, r: r, unlock: true, onChanged: onChanged);

  Future<void> lockDoor(
    BuildContext context,
    Reservation r, {
    VoidCallback? onChanged,
  }) =>
      controlDoor(context, r: r, unlock: false, onChanged: onChanged);

  HomeReservationMode homeMode(Reservation r) {
    if (r.status == 'in_use') return HomeReservationMode.inUse;
    if (r.status == 'confirmed' || r.status == 'pending') {
      return r.isWithinUsageWindow
          ? HomeReservationMode.confirmedInWindow
          : HomeReservationMode.confirmedBeforeWindow;
    }
    return r.isWithinUsageWindow
        ? HomeReservationMode.confirmedInWindow
        : HomeReservationMode.confirmedBeforeWindow;
  }
}

typedef RentalController = ReservationController;
