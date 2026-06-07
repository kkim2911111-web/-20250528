import '../models/my_page_profile.dart';

/// 예약·결제 진입 전 필수 조건 검사
abstract final class BookingEligibility {
  static String? blockReason(MyPageProfile profile) {
    if (profile.isBlacklisted) {
      return '서비스 이용이 제한된 계정입니다. 고객센터로 문의해주세요.';
    }
    if (!profile.hasResidentRegistration) {
      return '입주민 인증(초대코드·동/호)을 먼저 완료해주세요.';
    }
    if (!profile.residentApproved) {
      return '입주민 승인 대기 중입니다. 관리자 승인 후 예약할 수 있습니다.';
    }
    if (!profile.isBasicInfoComplete) {
      return '마이페이지에서 기본정보를 먼저 등록해주세요.';
    }
    if (!profile.isLicenseComplete) {
      return '면허증 촬영·등록을 먼저 완료해주세요.';
    }
    if (!profile.licenseVerified) {
      if (profile.licenseRejectionReason != null &&
          profile.licenseRejectionReason!.trim().isNotEmpty) {
        return '면허 심사가 거절되었습니다.\n${profile.licenseRejectionReason!.trim()}\n다시 등록해주세요.';
      }
      return '면허 심사 중입니다. 관리자 승인 후 예약할 수 있습니다.';
    }
    if (!profile.isPaymentCardComplete) {
      return '결제카드를 먼저 등록해주세요.';
    }
    return null;
  }

  static bool canBook(MyPageProfile profile) => blockReason(profile) == null;
}
