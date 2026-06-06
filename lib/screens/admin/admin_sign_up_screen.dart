import 'package:flutter/material.dart';

import '../../services/admin_service.dart';
import '../../services/auth_service.dart';
import '../../supabase_client.dart';
import '../../theme/danji_colors.dart';
import '../../theme/danji_theme.dart';
import '../../widgets/admin_scaffold.dart';
import '../../widgets/danji_app_bar.dart';

class AdminSignUpScreen extends StatefulWidget {
  final VoidCallback? onGoLogin;
  final VoidCallback? onRegistrationComplete;

  const AdminSignUpScreen({
    super.key,
    this.onGoLogin,
    this.onRegistrationComplete,
  });

  @override
  State<AdminSignUpScreen> createState() => _AdminSignUpScreenState();
}

class _AdminSignUpScreenState extends State<AdminSignUpScreen> {
  final _auth = AuthService();
  final _admin = AdminService();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _company = TextEditingController();
  final _inviteCode = TextEditingController(text: 'ADMIN-DANJI2026');
  bool _loading = false;
  String? _error;
  bool _accountCreatedAwaitingStaff = false;

  @override
  void initState() {
    super.initState();
    _auth.beginAdminSignUpFlow();
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _phone.dispose();
    _company.dispose();
    _inviteCode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    final company = _company.text.trim();
    final code = _inviteCode.text.trim();

    if (email.isEmpty ||
        password.isEmpty ||
        name.isEmpty ||
        phone.isEmpty ||
        company.isEmpty ||
        code.isEmpty) {
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
    _auth.beginAdminSignUpFlow();

    try {
      final sessionUser = supabase.auth.currentUser;
      final alreadySignedIn = sessionUser != null;

      if (!alreadySignedIn) {
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
      } else if (sessionUser.email?.trim().toLowerCase() !=
          email.toLowerCase()) {
        setState(
          () => _error = '다른 계정으로 로그인되어 있습니다. 로그아웃 후 다시 시도해주세요.',
        );
        return;
      }

      if (mounted) {
        setState(() => _accountCreatedAwaitingStaff = true);
      }

      await _admin.registerStaff(
        displayName: name,
        adminInviteCode: code,
        phone: phone,
        companyName: company,
      );

      if (!mounted) return;
      _auth.endAdminSignUpFlow();
      widget.onRegistrationComplete?.call();
      if (widget.onRegistrationComplete == null) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on AdminException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = friendlyAdminError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      safeTop: true,
      appBar: const DanjiAppBar(title: '관리자 회원가입'),
      body: SingleChildScrollView(
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
                    if (_accountCreatedAwaitingStaff) ...[
                      const Text(
                        '계정은 생성되었습니다. 초대코드를 확인한 뒤 다시 시도해주세요.',
                        style: TextStyle(
                          color: DanjiColors.accentRed,
                          height: 1.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    const Text(
                      '지점 관리자 전용 가입입니다.\n'
                      '가입 후 staff_users에 등록되며, 승인 전까지는 입주민 온보딩(5단계)으로 '
                      '이동하지 않습니다.',
                      style: TextStyle(
                        color: DanjiColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
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
                      controller: _name,
                      decoration: _dec('이름'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: _dec('전화번호'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _company,
                      decoration: _dec('업체명'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _inviteCode,
                      decoration: _dec('초대코드'),
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
                              _auth.endAdminSignUpFlow();
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
    );
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: DanjiColors.skyLight,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      );
}
