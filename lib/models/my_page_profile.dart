/// 마이페이지 프로필 및 필수 등록 완료 여부
class MyPageProfile {
  final String? name;
  final String? phone;
  final String? email;
  final String? address;
  final List<String> linkedProviders;
  final String? licenseNumber;
  final String? licenseExpiry;
  final bool licenseVerified;
  final String? licenseRejectionReason;
  final bool hasPaymentCard;
  final String? cardLast4;
  final int points;
  final int couponCount;
  final bool signupCompleted;
  final String role;
  final bool residentApproved;
  final bool hasResidentRegistration;
  final bool residentVerificationRequested;
  final String? residentComplexName;
  final String? residentBuilding;
  final String? residentUnit;
  final bool isBlacklisted;

  const MyPageProfile({
    this.name,
    this.phone,
    this.email,
    this.address,
    this.linkedProviders = const [],
    this.licenseNumber,
    this.licenseExpiry,
    this.licenseVerified = false,
    this.licenseRejectionReason,
    this.hasPaymentCard = false,
    this.cardLast4,
    this.points = 0,
    this.couponCount = 0,
    this.signupCompleted = false,
    this.role = 'resident',
    this.residentApproved = false,
    this.hasResidentRegistration = false,
    this.residentVerificationRequested = false,
    this.residentComplexName,
    this.residentBuilding,
    this.residentUnit,
    this.isBlacklisted = false,
  });

  bool get hasName => _filled(name);
  bool get hasPhone => _filled(phone);
  bool get hasEmail => _filled(email);
  bool get hasAddress => _filled(address);

  /// 이메일 로그인 또는 OAuth 연동
  bool get hasSnsLinked => linkedProviders.isNotEmpty;

  bool get isBasicInfoComplete =>
      hasName && hasPhone && hasEmail && hasAddress && hasSnsLinked;

  bool get isLicenseComplete => _filled(licenseNumber) && _filled(licenseExpiry);

  bool get isLicenseApproved => licenseVerified;

  bool get isPaymentCardComplete => hasPaymentCard;

  bool get isResidentComplete => residentApproved;

  bool get isAdmin => role == 'admin';

  /// user_profiles.resident_verification_requested + 미승인
  bool get isResidentVerificationPending =>
      residentVerificationRequested && !residentApproved;

  String? get residentLocationLabel {
    final parts = <String>[];
    if (residentComplexName != null && residentComplexName!.isNotEmpty) {
      parts.add(residentComplexName!);
    }
    if (residentBuilding != null && residentBuilding!.isNotEmpty) {
      parts.add('${residentBuilding!}동');
    }
    if (residentUnit != null && residentUnit!.isNotEmpty) {
      parts.add('${residentUnit!}호');
    }
    return parts.isEmpty ? null : parts.join(' ');
  }

  /// 마이페이지 상단 — 1005동 2002호 (입주민 building/unit)
  String? get dongHoLabel {
    final building = residentBuilding?.trim();
    final unit = residentUnit?.trim();
    if (building == null || building.isEmpty || unit == null || unit.isEmpty) {
      return null;
    }
    return '${building}동 ${unit}호';
  }

  String get displayName {
    if (hasName) return '${name!.trim()}님';
    if (email != null && email!.contains('@')) {
      return '${email!.split('@').first}님';
    }
    return '입주민님';
  }

  /// 마이페이지 타이틀 — "김환중님 · 1005동 2002호" 또는 "김환중님"
  String get pageHeaderTitle {
    final dongHo = dongHoLabel;
    if (hasResidentRegistration && dongHo != null) {
      return '$displayName · $dongHo';
    }
    return displayName;
  }

  bool get canUseVehicle =>
      isResidentComplete &&
      isBasicInfoComplete &&
      isLicenseComplete &&
      isLicenseApproved &&
      isPaymentCardComplete;

  bool get canBookVehicle => canUseVehicle;

  List<BasicInfoField> get basicInfoFields => [
        BasicInfoField('이름', name, hasName),
        BasicInfoField('휴대전화', phone, hasPhone),
        BasicInfoField('이메일', email, hasEmail),
        BasicInfoField('SNS 로그인 연동', _snsLabel, hasSnsLinked),
        BasicInfoField('주소', address, hasAddress),
      ];

  String? get _snsLabel {
    if (linkedProviders.isEmpty) return null;
    return linkedProviders.map(providerLabel).join(', ');
  }

  static String providerLabel(String provider) {
    switch (provider) {
      case 'email':
        return '이메일';
      case 'google':
        return 'Google';
      case 'kakao':
        return '카카오';
      case 'apple':
        return 'Apple';
      default:
        return provider;
    }
  }

  static bool _filled(String? value) =>
      value != null && value.trim().isNotEmpty;
}

class BasicInfoField {
  final String label;
  final String? value;
  final bool isComplete;

  const BasicInfoField(this.label, this.value, this.isComplete);
}
