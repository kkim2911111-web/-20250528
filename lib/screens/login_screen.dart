import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/my_page_service.dart';
import '../theme/danji_colors.dart';
import '../theme/danji_theme.dart';
import '../widgets/danji_app_bar.dart';
import '../widgets/danji_logo.dart';
import '../widgets/terms_consent_section.dart';
import 'admin/admin_sign_up_screen.dart';

/// 로그인 화면 전용 색상 (디자인 스펙)
abstract final class _LoginColors {
  static const brandBlue = Color(0xFF3182F6);
  static const background = Color(0xFFFFFFFF);
  static const kakaoYellow = Color(0xFFFEE500);
  static const kakaoText = Color(0xFF3C1E1E);
  static const naverGreen = Color(0xFF03C75A);
  static const subtitleGray = Color(0xFF888888);
  static const dividerGray = Color(0xFFE5E5E5);
  static const mutedGray = Color(0xFFBBBBBB);
  static const headlineDark = Color(0xFF191919);
}

class LoginScreen extends StatelessWidget {
  final VoidCallback? onGoSignUp;
  final VoidCallback? onGoAdminSignUp;

  const LoginScreen({
    super.key,
    this.onGoSignUp,
    this.onGoAdminSignUp,
  });

  void _goSignUp(BuildContext context) {
    if (onGoSignUp != null) {
      onGoSignUp!();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SignUpScreen()),
    );
  }

  void _goAdminSignUp(BuildContext context) {
    if (onGoAdminSignUp != null) {
      onGoAdminSignUp!();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AdminSignUpScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _LoginColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 24),
                          const _LoginLogoSection(),
                          const SizedBox(height: 24),
                          const _LoginHeadlineSection(),
                          const SizedBox(height: 40),
                          _KakaoLoginButton(
                            onPressed: () {
                              _toast(context, '카카오 로그인은 다음 단계에서 연결합니다.');
                            },
                          ),
                          const SizedBox(height: 10),
                          _NaverLoginButton(
                            onPressed: () {
                              _toast(context, '네이버 로그인은 다음 단계에서 연결합니다.');
                            },
                          ),
                          const SizedBox(height: 10),
                          const _EmailDivider(),
                          const SizedBox(height: 10),
                          _EmailLoginButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const EmailLoginScreen(),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 28),
                          _SignUpLink(onTap: () => _goSignUp(context)),
                          const SizedBox(height: 6),
                          _AdminLoginLink(onTap: () => _goAdminSignUp(context)),
                          const SizedBox(height: 28),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  static void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: DanjiColors.surface,
      ),
    );
  }
}

class _LoginLogoSection extends StatelessWidget {
  const _LoginLogoSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const DanjiLogo(
          size: 64,
          variant: DanjiLogoVariant.full,
        ),
        const SizedBox(height: 10),
        const Text(
          '단지카',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            color: _LoginColors.headlineDark,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

class _LoginHeadlineSection extends StatelessWidget {
  const _LoginHeadlineSection();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Text(
          '우리 단지의 두 번째 차',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _LoginColors.headlineDark,
            fontSize: 20,
            fontWeight: FontWeight.w500,
            height: 1.3,
          ),
        ),
        SizedBox(height: 8),
        Text(
          '한 번의 인증, 간편한 예약.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _LoginColors.subtitleGray,
            fontSize: 13,
            fontWeight: FontWeight.w400,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _KakaoLoginButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _KakaoLoginButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: _LoginColors.kakaoYellow,
          foregroundColor: _LoginColors.kakaoText,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _KakaoIcon(),
            SizedBox(width: 8),
            Text(
              '카카오 로그인',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _LoginColors.kakaoText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KakaoIcon extends StatelessWidget {
  const _KakaoIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(
        painter: _KakaoIconPainter(),
      ),
    );
  }
}

class _KakaoIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bubble = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 2, size.width, size.height - 4),
      const Radius.circular(5),
    );
    canvas.drawRRect(
      bubble,
      Paint()..color = _LoginColors.kakaoText,
    );
    final tail = Path()
      ..moveTo(4, size.height - 2)
      ..lineTo(0, size.height + 1)
      ..lineTo(10, size.height - 2)
      ..close();
    canvas.drawPath(tail, Paint()..color = _LoginColors.kakaoText);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _NaverLoginButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _NaverLoginButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: _LoginColors.naverGreen,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _NaverIcon(),
            SizedBox(width: 8),
            Text(
              '네이버 로그인',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NaverIcon extends StatelessWidget {
  const _NaverIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'N',
        style: TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

class _EmailDivider extends StatelessWidget {
  const _EmailDivider();

  @override
  Widget build(BuildContext context) {
    const line = Expanded(
      child: Divider(
        height: 1,
        thickness: 1,
        color: _LoginColors.dividerGray,
      ),
    );
    return const Row(
      children: [
        line,
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            '또는 이메일로',
            style: TextStyle(
              fontSize: 12,
              color: _LoginColors.subtitleGray,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        line,
      ],
    );
  }
}

class _EmailLoginButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _EmailLoginButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: _LoginColors.background,
          foregroundColor: _LoginColors.brandBlue,
          side: const BorderSide(color: _LoginColors.brandBlue, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mail_outline_rounded, size: 20),
            SizedBox(width: 8),
            Text(
              '이메일로 로그인',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _LoginColors.brandBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignUpLink extends StatelessWidget {
  final VoidCallback onTap;

  const _SignUpLink({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Text.rich(
          TextSpan(
            style: const TextStyle(
              fontSize: 13,
              color: _LoginColors.subtitleGray,
              height: 1.4,
            ),
            children: [
              const TextSpan(text: '처음이신가요? '),
              TextSpan(
                text: '회원가입',
                style: TextStyle(
                  color: _LoginColors.brandBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _AdminLoginLink extends StatelessWidget {
  final VoidCallback onTap;

  const _AdminLoginLink({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: const Text(
          '관리자이신가요? 관리자 로그인',
          style: TextStyle(
            fontSize: 11,
            color: _LoginColors.mutedGray,
            height: 1.35,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class EmailLoginScreen extends StatefulWidget {
  const EmailLoginScreen({super.key});

  @override
  State<EmailLoginScreen> createState() => _EmailLoginScreenState();
}

class _EmailLoginScreenState extends State<EmailLoginScreen> {
  final _auth = AuthService();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = '이메일과 비밀번호를 입력해주세요.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _auth.signInWithEmail(email: email, password: password);

      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      setState(() => _error = friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: const DanjiAppBar(title: '이메일 로그인'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: DanjiColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: DanjiColors.border),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(color: DanjiColors.textPrimary),
                      decoration: _inputDecoration('이메일'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      style: const TextStyle(color: DanjiColors.textPrimary),
                      decoration: _inputDecoration('비밀번호'),
                    ),
                    const SizedBox(height: 14),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: DanjiColors.accentRed),
                        ),
                      ),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: _loading ? null : _submit,
                        style: DanjiTheme.primaryButton,
                        child: _loading
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('로그인'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () {
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute(
                                  builder: (_) => const SignUpScreen(),
                                ),
                              );
                            },
                      child: const Text('회원가입'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: DanjiColors.textSecondary),
      filled: true,
      fillColor: DanjiColors.skyLight,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: DanjiColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: DanjiColors.buttonBlue, width: 1.5),
      ),
    );
  }
}

/// 입주민 이메일 가입 — 이메일·비밀번호만. `register_staff_for_me` / staff_users 미사용.
class SignUpScreen extends StatefulWidget {
  final VoidCallback? onGoLogin;
  /// 온보딩 새로고침 후 — 이미 로그인된 상태에서 위저드로 이어가기
  final VoidCallback? onContinue;
  final String? continueLabel;

  const SignUpScreen({
    super.key,
    this.onGoLogin,
    this.onContinue,
    this.continueLabel,
  });

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _auth = AuthService();
  final _myPageService = MyPageService();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _agreeTerms = false;
  bool _agreePrivacy = false;
  bool _agreeCarRental = false;
  bool _agreeMarketing = false;

  bool get _requiredConsentGiven =>
      _agreeTerms && _agreePrivacy && _agreeCarRental;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = '이메일과 비밀번호를 입력해주세요.');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = '비밀번호는 6자 이상으로 입력해주세요.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final signedIn =
          await _auth.signUpWithEmail(email: email, password: password);

      if (!mounted) return;

      if (!signedIn) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(emailSignUpConfirmationMessage)),
        );
        Navigator.of(context).pop();
        return;
      }

      try {
        await _myPageService.saveTermsConsent(
          marketingAgreed: _agreeMarketing,
        );
      } catch (_) {
        // 프로필·컬럼 미준비 시에도 가입 흐름 유지
      }

      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      setState(() => _error = friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final restartMode = widget.onContinue != null;

    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: const DanjiAppBar(title: '회원가입'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: DanjiColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: DanjiColors.border),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (restartMode) ...[
                      const Text(
                        '가입이 완료되지 않았습니다.\n'
                        '아래 버튼을 눌러 회원가입 단계를 이어서 진행해주세요.',
                        style: TextStyle(
                          color: DanjiColors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 52,
                        child: FilledButton(
                          onPressed: widget.onContinue,
                          style: DanjiTheme.primaryButton,
                          child: Text(
                            widget.continueLabel ?? '회원가입 계속하기',
                          ),
                        ),
                      ),
                    ] else ...[
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(color: DanjiColors.textPrimary),
                        decoration: _inputDecoration('이메일'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _password,
                        obscureText: true,
                        style: const TextStyle(color: DanjiColors.textPrimary),
                        decoration: _inputDecoration('비밀번호'),
                      ),
                      const SizedBox(height: 14),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: DanjiColors.accentRed),
                          ),
                        ),
                      TermsConsentSection(
                        agreeTerms: _agreeTerms,
                        agreePrivacy: _agreePrivacy,
                        agreeCarRental: _agreeCarRental,
                        agreeMarketing: _agreeMarketing,
                        onTermsChanged: (v) => setState(() => _agreeTerms = v),
                        onPrivacyChanged: (v) =>
                            setState(() => _agreePrivacy = v),
                        onCarRentalChanged: (v) =>
                            setState(() => _agreeCarRental = v),
                        onMarketingChanged: (v) =>
                            setState(() => _agreeMarketing = v),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 52,
                        child: FilledButton(
                          onPressed: _loading || !_requiredConsentGiven
                              ? null
                              : _submit,
                          style: DanjiTheme.primaryButton,
                          child: _loading
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('가입하기'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: _loading
                            ? null
                            : () {
                                if (widget.onGoLogin != null) {
                                  widget.onGoLogin!();
                                  return;
                                }
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(
                                    builder: (_) => const EmailLoginScreen(),
                                  ),
                                );
                              },
                        child: const Text('이미 계정이 있으신가요? 로그인'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: DanjiColors.textSecondary),
      filled: true,
      fillColor: DanjiColors.skyLight,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: DanjiColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: DanjiColors.buttonBlue, width: 1.5),
      ),
    );
  }
}
