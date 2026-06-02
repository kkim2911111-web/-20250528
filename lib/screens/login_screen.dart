import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/danji_colors.dart';
import '../theme/danji_theme.dart';
import '../widgets/danji_app_bar.dart';
import 'admin/admin_sign_up_screen.dart';

class LoginScreen extends StatelessWidget {
  final VoidCallback? onGoSignUp;
  final VoidCallback? onGoAdminSignUp;

  const LoginScreen({
    super.key,
    this.onGoSignUp,
    this.onGoAdminSignUp,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DanjiColors.background,
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 12),
                          const _Header(),
                          const SizedBox(height: 24),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: DanjiColors.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: DanjiColors.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _SocialButton(
                                  label: '카카오 로그인',
                                  background: const Color(0xFFFEE500),
                                  foreground: const Color(0xFF191600),
                                  icon: Icons.chat_bubble_rounded,
                                  onPressed: () {
                                    _toast(context, '카카오 로그인은 다음 단계에서 연결합니다.');
                                  },
                                ),
                                const SizedBox(height: 12),
                                _SocialButton(
                                  label: '네이버 로그인',
                                  background: const Color(0xFF03C75A),
                                  foreground: Colors.white,
                                  icon: Icons.eco_rounded,
                                  onPressed: () {
                                    _toast(context, '네이버 로그인은 다음 단계에서 연결합니다.');
                                  },
                                ),
                                const SizedBox(height: 12),
                                _SocialButton(
                                  label: '이메일 로그인',
                                  background: DanjiColors.buttonBlue,
                                  foreground: Colors.white,
                                  icon: Icons.mail_rounded,
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const EmailLoginScreen(),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Text(
                                      '처음이신가요?',
                                      style: TextStyle(color: DanjiColors.textSecondary),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        if (onGoSignUp != null) {
                                          onGoSignUp!();
                                          return;
                                        }
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => const SignUpScreen(),
                                          ),
                                        );
                                      },
                                      style: TextButton.styleFrom(
                                        foregroundColor: DanjiColors.buttonBlue,
                                      ),
                                      child: const Text('회원가입'),
                                    ),
                                  ],
                                ),
                                TextButton(
                                  onPressed: () {
                                    if (onGoAdminSignUp != null) {
                                      onGoAdminSignUp!();
                                      return;
                                    }
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const AdminSignUpScreen(),
                                      ),
                                    );
                                  },
                                  child: const Text('관리자 회원가입'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),
                          Text(
                            '계속 진행하면 서비스 이용약관 및 개인정보 처리방침에 동의한 것으로 간주됩니다.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: DanjiColors.textSecondary.withValues(alpha: 0.9),
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 10),
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

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 72,
          width: 72,
          decoration: BoxDecoration(
            color: DanjiColors.skyLight,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: DanjiColors.border),
          ),
          child: const Center(
            child: Text(
              '단지카',
              style: TextStyle(
                color: DanjiColors.textPrimary,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          '우리 단지의 두 번째 차',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: DanjiColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '한 번의 인증, 간편한 예약.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: DanjiColors.textSecondary,
            fontSize: 14,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  final IconData icon;
  final VoidCallback onPressed;

  const _SocialButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 10),
            Text(label),
          ],
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
                      SizedBox(
                        height: 52,
                        child: FilledButton(
                          onPressed: _loading ? null : _submit,
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
