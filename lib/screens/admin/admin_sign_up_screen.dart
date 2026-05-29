import 'package:flutter/material.dart';

import '../../models/admin_messages.dart';
import '../../services/admin_service.dart';
import '../../services/auth_service.dart';
import '../../theme/danji_colors.dart';
import '../../theme/danji_theme.dart';
import '../../widgets/danji_app_bar.dart';

class AdminSignUpScreen extends StatefulWidget {
  final VoidCallback? onGoLogin;

  const AdminSignUpScreen({super.key, this.onGoLogin});

  @override
  State<AdminSignUpScreen> createState() => _AdminSignUpScreenState();
}

class _AdminSignUpScreenState extends State<AdminSignUpScreen> {
  final _auth = AuthService();
  final _admin = AdminService();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _inviteCode = TextEditingController(text: 'ADMIN-DANJI2026');
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _inviteCode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final password = _password.text;
    final code = _inviteCode.text.trim();

    if (name.isEmpty || email.isEmpty || password.isEmpty || code.isEmpty) {
      setState(() => _error = '모든 항목을 입력해주세요.');
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
      final signedIn = await _auth.signUpWithEmail(
        email: email,
        password: password,
      );
      if (!signedIn) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(emailSignUpConfirmationMessage)),
        );
        Navigator.of(context).pop();
        return;
      }

      await _admin.registerStaff(
        displayName: name,
        adminInviteCode: code,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AdminMessages.pendingApproval)),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      setState(() => _error = friendlyAdminError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: const DanjiAppBar(title: '관리자 회원가입'),
      body: SafeArea(
        child: SingleChildScrollView(
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
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '지점 관리자 계정을 생성합니다.\n'
                      '가입 후 운영팀 승인이 완료되어야 차량 등록·관리가 가능합니다.',
                      style: TextStyle(
                        color: DanjiColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _name,
                      decoration: _dec('관리자 이름'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: _dec('이메일'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      decoration: _dec('비밀번호'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _inviteCode,
                      decoration: _dec('관리자 초대코드'),
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
                            : const Text('관리자 가입하기'),
                      ),
                    ),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () {
                              if (widget.onGoLogin != null) {
                                widget.onGoLogin!();
                                return;
                              }
                              Navigator.of(context).pop();
                            },
                      child: const Text('이미 계정이 있으신가요? 로그인'),
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

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: DanjiColors.skyLight,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      );
}
