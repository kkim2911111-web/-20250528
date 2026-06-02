import 'package:flutter/material.dart';

import '../repositories/staff_repository.dart';
import '../screens/login_screen.dart';
import '../screens/sign_up_wizard_screen.dart';
import '../services/signup_onboarding_service.dart';
import 'admin_staff_flow.dart';
import 'resident_gate.dart';

/// 입주민 전용 — `staff_users` 없을 때만 [RoleGate]에서 진입.
///
/// 관리자는 [AdminSignUpScreen] → `register_staff_for_me` → [AdminStaffFlow]이며
/// 이 게이트·5단계 위저드에 들어오지 않습니다.
class ResidentOnboardingGate extends StatefulWidget {
  const ResidentOnboardingGate({super.key});

  @override
  State<ResidentOnboardingGate> createState() => _ResidentOnboardingGateState();
}

class _ResidentOnboardingGateState extends State<ResidentOnboardingGate> {
  final _service = SignupOnboardingService();
  final _staffRepo = StaffRepository();
  SignupOnboardingState? _state;
  Object? _loadError;
  var _loading = true;
  var _wizardGeneration = 0;
  var _emailEntryDismissed = false;

  @override
  void initState() {
    super.initState();
    _loadOnce();
  }

  Future<void> _loadOnce() async {
    try {
      final staff = await _staffRepo.fetchMyProfile();
      if (staff != null) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => AdminStaffFlow(initialStaff: staff),
          ),
        );
        return;
      }

      final state = await _service.loadState();
      if (!mounted) return;
      setState(() {
        _state = state;
        _loadError = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  void _onWizardCompleted() {
    setState(() => _wizardGeneration++);
    _loadOnce();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('오류')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('가입 정보 확인 실패: $_loadError'),
        ),
      );
    }

    final state = _state!;
    if (!state.needsWizard) {
      return const ResidentGate();
    }

    if (state.showEmailSignUpEntry && !_emailEntryDismissed) {
      return _OnboardingEmailSignUpEntry(
        onContinue: () => setState(() => _emailEntryDismissed = true),
      );
    }

    return SignUpWizardScreen(
      key: ValueKey('signup-wizard-$_wizardGeneration'),
      initialStep: state.resumeStep,
      onCompleted: _onWizardCompleted,
    );
  }
}

/// onboarding_step=0 · 미완료 — [SignUpScreen] (이메일·비밀번호만, staff RPC 없음)
class _OnboardingEmailSignUpEntry extends StatelessWidget {
  final VoidCallback onContinue;

  const _OnboardingEmailSignUpEntry({required this.onContinue});

  @override
  Widget build(BuildContext context) {
    return SignUpScreen(
      onGoLogin: onContinue,
      continueLabel: '회원가입 계속하기',
      onContinue: onContinue,
    );
  }
}
