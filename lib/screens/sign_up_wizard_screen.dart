import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/license_service.dart';
import '../services/my_page_service.dart';
import '../theme/danji_colors.dart';
import '../theme/danji_theme.dart';

/// 회원가입 2단계: 상세 정보 → 면허/결제 (모두 완료 시 가입 완료)
class SignUpWizardScreen extends StatefulWidget {
  final VoidCallback? onCompleted;

  const SignUpWizardScreen({super.key, this.onCompleted});

  @override
  State<SignUpWizardScreen> createState() => _SignUpWizardScreenState();
}

class _SignUpWizardScreenState extends State<SignUpWizardScreen> {
  final _pageController = PageController();
  final _myPageService = MyPageService();
  final _licenseService = LicenseService();

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _licenseNumber = TextEditingController();
  final _licenseExpiry = TextEditingController();
  final _cardLast4 = TextEditingController();

  int _step = 0;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _pageController.dispose();
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _licenseNumber.dispose();
    _licenseExpiry.dispose();
    _cardLast4.dispose();
    super.dispose();
  }

  Future<void> _savePersonalAndNext() async {
    if (_name.text.trim().isEmpty ||
        _phone.text.trim().isEmpty ||
        _address.text.trim().isEmpty) {
      setState(() => _error = '이름, 휴대폰, 주소를 모두 입력해주세요.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _myPageService.saveBasicInfo(
        name: _name.text,
        phone: _phone.text,
        address: _address.text,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _step = 1;
      });
      await _pageController.animateToPage(
        1,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _completeSignup() async {
    if (_licenseNumber.text.trim().isEmpty ||
        _licenseExpiry.text.trim().isEmpty) {
      setState(() => _error = '면허번호와 만료일을 입력해주세요.');
      return;
    }
    if (_cardLast4.text.trim().length != 4) {
      setState(() => _error = '카드 번호 뒤 4자리를 입력해주세요.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _licenseService.submitLicense(
        licenseNumber: _licenseNumber.text,
        licenseExpiry: _licenseExpiry.text,
      );
      await _myPageService.savePaymentCard(cardLast4: _cardLast4.text);
      await _myPageService.markSignupComplete();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '가입 정보가 저장되었습니다. 면허 심사 승인 후 예약할 수 있습니다.',
          ),
        ),
      );
      if (widget.onCompleted != null) {
        widget.onCompleted!();
      } else {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: DanjiColors.background,
        appBar: AppBar(
          backgroundColor: DanjiColors.background,
          foregroundColor: DanjiColors.textPrimary,
          elevation: 0,
          leading: _step > 0
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    setState(() => _step = 0);
                    _pageController.animateToPage(
                      0,
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                    );
                  },
                )
              : null,
          automaticallyImplyLeading: false,
          title: Text(
            _step == 0 ? '상세 정보 입력' : '면허/결제 정보',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  _StepDot(active: _step >= 0, label: '1'),
                  Expanded(
                    child: Container(
                      height: 2,
                      color: _step >= 1
                          ? DanjiColors.buttonBlue
                          : DanjiColors.border,
                    ),
                  ),
                  _StepDot(active: _step >= 1, label: '2'),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _PersonalStep(
                    name: _name,
                    phone: _phone,
                    address: _address,
                  ),
                  _LicensePaymentStep(
                    licenseNumber: _licenseNumber,
                    licenseExpiry: _licenseExpiry,
                    cardLast4: _cardLast4,
                    onScan: _scanLicense,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: const TextStyle(color: DanjiColors.accentRed),
                    ),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: _loading
                          ? null
                          : (_step == 0 ? _savePersonalAndNext : _completeSignup),
                      style: DanjiTheme.primaryButton,
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_step == 0 ? '다음' : '가입 완료'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _scanLicense() async {
    setState(() => _error = null);
    try {
      final result = await _licenseService.captureAndRecognize();
      if (!mounted || result.image == null) return;
      final ocr = result.ocr;
      if (ocr != null) {
        if (ocr.licenseNumber != null && ocr.licenseNumber!.isNotEmpty) {
          _licenseNumber.text = ocr.licenseNumber!;
        }
        if (ocr.licenseExpiry != null && ocr.licenseExpiry!.isNotEmpty) {
          _licenseExpiry.text = ocr.licenseExpiry!;
        }
      }
      setState(() {});
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }
}

class _StepDot extends StatelessWidget {
  final bool active;
  final String label;

  const _StepDot({required this.active, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? DanjiColors.buttonBlue : DanjiColors.border,
            shape: BoxShape.circle,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : DanjiColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _PersonalStep extends StatelessWidget {
  final TextEditingController name;
  final TextEditingController phone;
  final TextEditingController address;

  const _PersonalStep({
    required this.name,
    required this.phone,
    required this.address,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          '이름, 휴대폰, 주소를 입력해주세요.',
          style: TextStyle(
            color: DanjiColors.textSecondary,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 16),
        _Field(label: '이름', controller: name),
        _Field(
          label: '휴대폰',
          controller: phone,
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        _Field(label: '주소', controller: address),
      ],
    );
  }
}

class _LicensePaymentStep extends StatelessWidget {
  final TextEditingController licenseNumber;
  final TextEditingController licenseExpiry;
  final TextEditingController cardLast4;
  final VoidCallback onScan;

  const _LicensePaymentStep({
    required this.licenseNumber,
    required this.licenseExpiry,
    required this.cardLast4,
    required this.onScan,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          '운전면허와 결제 정보를 등록해야 가입이 완료됩니다.\n'
          '면허는 관리자 심사 후 예약·대여가 가능합니다.',
          style: TextStyle(
            color: DanjiColors.textSecondary,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: onScan,
          icon: const Icon(Icons.camera_alt_outlined),
          label: const Text('면허증 촬영 (OCR)'),
          style: OutlinedButton.styleFrom(
            foregroundColor: DanjiColors.buttonBlue,
            side: const BorderSide(color: DanjiColors.buttonBlue),
            minimumSize: const Size.fromHeight(48),
          ),
        ),
        const SizedBox(height: 16),
        _Field(label: '면허번호', controller: licenseNumber),
        _Field(
          label: '면허 만료일',
          controller: licenseExpiry,
          hint: '예: 2030-12-31',
        ),
        const SizedBox(height: 20),
        const Text(
          '결제 정보',
          style: TextStyle(
            color: DanjiColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '테스트용 등록입니다. 실제 결제는 토스페이먼츠 연동 후 적용됩니다.',
          style: TextStyle(
            color: DanjiColors.textSecondary,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        _Field(
          label: '카드 뒤 4자리',
          controller: cardLast4,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4),
          ],
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: DanjiColors.surface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
