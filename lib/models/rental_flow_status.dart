/// 대여 3단계 — 사진 등록 상태
enum PhotoFlowStatus {
  /// 미등록
  none,

  /// 6장 등록 완료 → 승인 대기 (2단계 활성화)
  pending,

  /// 등록 완료 (서버 반영)
  complete,
}

/// 대여 3단계 — 면허 진위 확인 상태
enum LicenseFlowStatus {
  /// 미등록
  none,

  /// 정보 있음 · 진위 확인 대기
  pending,

  /// 인증 완료
  approved,
}

/// 대여 3단계 — 도어 상태
enum DoorFlowStatus {
  locked,
  unlocked,
}

extension PhotoFlowStatusX on PhotoFlowStatus {
  bool get isStepComplete => this == PhotoFlowStatus.complete;

  String get label => switch (this) {
        PhotoFlowStatus.none => '미등록',
        PhotoFlowStatus.pending => '등록 완료',
        PhotoFlowStatus.complete => '등록 완료',
      };
}

extension LicenseFlowStatusX on LicenseFlowStatus {
  bool get isVerified => this == LicenseFlowStatus.approved;

  String get label => switch (this) {
        LicenseFlowStatus.none => '미등록',
        LicenseFlowStatus.pending => '확인 대기',
        LicenseFlowStatus.approved => '면허 확인 완료',
      };
}

extension DoorFlowStatusX on DoorFlowStatus {
  bool get isUnlocked => this == DoorFlowStatus.unlocked;

  String get label => isUnlocked ? '열림' : '잠김';
}
