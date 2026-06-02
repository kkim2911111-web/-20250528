import '../models/my_page_profile.dart';
import '../repositories/staff_repository.dart';
import 'my_page_service.dart';

/// 회원가입 온보딩(이메일 가입 후) 진행 상태
class SignupOnboardingState {
  final bool needsWizard;
  final int resumeStep;
  /// signup_completed=false, onboarding_step=0, 프로필 있음 → 이메일 회원가입 화면
  final bool showEmailSignUpEntry;

  const SignupOnboardingState({
    required this.needsWizard,
    required this.resumeStep,
    this.showEmailSignUpEntry = false,
  });
}

/// SignUpWizardScreen 단계 (5단계, 표시 1/5 ~ 5/5)
enum SignupWizardStep {
  resident,
  personal,
  license,
  payment,
  complete;

  static const int count = 5;

  int get displayIndex => index + 1;

  String get title => switch (this) {
        SignupWizardStep.resident => '입주민 인증',
        SignupWizardStep.personal => '개인정보 입력',
        SignupWizardStep.license => '운전면허 등록',
        SignupWizardStep.payment => '결제카드 등록',
        SignupWizardStep.complete => '가입 완료',
      };
}

class SignupOnboardingService {
  final _myPage = MyPageService();

  Future<SignupOnboardingState> loadState() async {
    if (await StaffRepository().fetchMyProfile() != null) {
      throw StateError(
        'staff_users 계정은 입주민 온보딩 대상이 아닙니다. RoleGate → AdminStaffFlow',
      );
    }

    if (await _myPage.isSignupCompleted()) {
      return const SignupOnboardingState(needsWizard: false, resumeStep: 0);
    }

    final saved = await _myPage.getOnboardingStep() ?? 0;

    if (saved == 0) {
      return const SignupOnboardingState(
        needsWizard: true,
        resumeStep: 0,
        showEmailSignUpEntry: true,
      );
    }

    final profile = await _myPage.fetchProfile();
    final computed = _resolveStep(profile).index;
    final resume = computed > saved ? computed : saved;
    return SignupOnboardingState(
      needsWizard: true,
      resumeStep: resume.clamp(0, SignupWizardStep.count - 1),
    );
  }

  SignupWizardStep _resolveStep(MyPageProfile profile) {
    if (!profile.hasResidentRegistration &&
        !profile.residentVerificationRequested) {
      return SignupWizardStep.resident;
    }
    if (!profile.isBasicInfoComplete) return SignupWizardStep.personal;
    if (!profile.isLicenseComplete) return SignupWizardStep.license;
    if (!profile.isPaymentCardComplete) return SignupWizardStep.payment;
    return SignupWizardStep.complete;
  }
}
