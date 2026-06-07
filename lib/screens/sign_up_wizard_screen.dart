import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../resident_profile_screen.dart';
import '../services/coupon_service.dart';
import '../services/license_service.dart';
import '../services/my_page_service.dart';
import '../services/payment_service.dart';
import '../services/push_notification_service.dart';
import '../services/signup_onboarding_service.dart';
import '../supabase_client.dart';
import '../theme/danji_colors.dart';
import '../theme/danji_theme.dart';
import '../widgets/kakao_address_field.dart';
import '../widgets/resident_verification_pending.dart';

/// 이메일 가입 후 5단계 온보딩 (입주민 → 개인정보 → 면허 → 결제 → 완료)
class SignUpWizardScreen extends StatefulWidget {
  final int initialStep;
  final VoidCallback? onCompleted;

  const SignUpWizardScreen({
    super.key,
    this.initialStep = 0,
    this.onCompleted,
  });

  @override
  State<SignUpWizardScreen> createState() => _SignUpWizardScreenState();
}

class _SignUpWizardScreenState extends State<SignUpWizardScreen> {
  static const _stepCount = SignupWizardStep.count;

  late final PageController _pageController;
  final _myPageService = MyPageService();
  final _couponService = CouponService();
  final _licenseService = LicenseService();
  final _paymentService = PaymentService();
  final _residentRepo = ResidentRepository();

  final _inviteCode = TextEditingController();
  final _building = TextEditingController();
  final _unit = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _licenseNumber = TextEditingController();
  final _licenseExpiry = TextEditingController();

  Timer? _inviteDebounce;
  bool _lookingUp = false;
  String? _lookupError;
  String? _complexId;
  String? _complexName;

  XFile? _licensePhoto;
  bool _cardRegistered = false;
  bool _residentVerificationPending = false;

  late int _step;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _step = widget.initialStep.clamp(0, _stepCount - 1);
    _pageController = PageController(initialPage: _step);
    _inviteCode.addListener(_onInviteCodeChanged);
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    try {
      final profile = await _myPageService.fetchProfile();
      if (!mounted) return;
      if (profile.name != null) _name.text = profile.name!;
      if (profile.phone != null) _phone.text = profile.phone!;
      if (profile.address != null) _address.text = profile.address!;
      if (profile.licenseNumber != null) {
        _licenseNumber.text = profile.licenseNumber!;
      }
      if (profile.licenseExpiry != null) {
        _licenseExpiry.text = profile.licenseExpiry!;
      }
      if (profile.residentBuilding != null) {
        _building.text = profile.residentBuilding!;
      }
      if (profile.residentUnit != null) {
        _unit.text = profile.residentUnit!;
      }
      setState(() {
        _cardRegistered = profile.isPaymentCardComplete;
        _residentVerificationPending = profile.isResidentVerificationPending;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _inviteDebounce?.cancel();
    _inviteCode.removeListener(_onInviteCodeChanged);
    _pageController.dispose();
    _inviteCode.dispose();
    _building.dispose();
    _unit.dispose();
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _licenseNumber.dispose();
    _licenseExpiry.dispose();
    super.dispose();
  }

  void _onInviteCodeChanged() {
    _inviteDebounce?.cancel();
    _inviteDebounce = Timer(const Duration(milliseconds: 400), () {
      _lookupComplex(_inviteCode.text);
    });
  }

  String _normalizeCode(String raw) =>
      raw.trim().replaceAll(' ', '').toUpperCase();

  Future<void> _lookupComplex(String rawCode) async {
    final code = _normalizeCode(rawCode);

    if (code.length < 4) {
      setState(() {
        _lookingUp = false;
        _lookupError = null;
        _complexId = null;
        _complexName = null;
      });
      return;
    }

    setState(() {
      _lookingUp = true;
      _lookupError = null;
      _complexId = null;
      _complexName = null;
    });

    try {
      final payload = await supabase.rpc(
        'lookup_complex_by_invite_code',
        params: {'p_invite_code': code},
      );

      if (!mounted) return;

      if (payload == null || payload is! Map) {
        setState(() => _lookupError = '유효하지 않은 초대코드입니다.');
        return;
      }

      final id = payload['id']?.toString();
      final name = payload['name']?.toString();

      if (id == null || id.isEmpty) {
        setState(() => _lookupError = '유효하지 않은 초대코드입니다.');
        return;
      }

      setState(() {
        _complexId = id;
        _complexName = (name == null || name.isEmpty) ? '단지' : name;
        _lookupError = null;
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      final msg = e.message.toLowerCase();
      String friendly;
      if (msg.contains('rate_limited')) {
        friendly = '조회가 너무 잦습니다. 잠시 후 다시 시도해주세요.';
      } else if (msg.contains('invite_code_too_short')) {
        friendly = '초대코드를 더 길게 입력해주세요.';
      } else {
        friendly = '단지 조회 실패: ${e.message}';
      }
      setState(() => _lookupError = friendly);
    } catch (e) {
      if (!mounted) return;
      setState(() => _lookupError = '단지 조회 실패: $e');
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  Future<void> _goToStep(int step) async {
    setState(() {
      _step = step;
      _error = null;
    });
    unawaited(_myPageService.saveOnboardingStep(step));
    await _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _continueFromResidentStep() async {
    if (_residentVerificationPending) {
      await _goToStep(SignupWizardStep.personal.index);
      return;
    }
    await _saveResidentAndNext();
  }

  Future<void> _saveResidentAndNext() async {
    final complexId = _complexId;
    final b = _building.text.trim();
    final u = _unit.text.trim();

    if (complexId == null) {
      setState(() => _error = '초대코드를 확인해주세요.');
      return;
    }
    if (b.isEmpty || u.isEmpty) {
      setState(() => _error = '동/호수를 모두 입력해주세요.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _residentRepo.upsertMyProfile(
        complexId: complexId,
        building: b,
        unit: u,
      );
      await _myPageService.markResidentVerificationRequested();
      await PushNotificationService.instance
          .staffResidentReviewRequest(complexId: complexId);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _residentVerificationPending = true;
      });
      await _goToStep(SignupWizardStep.personal.index);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
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
      setState(() => _loading = false);
      await _goToStep(SignupWizardStep.license.index);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _saveLicenseAndNext() async {
    if (_licenseNumber.text.trim().isEmpty ||
        _licenseExpiry.text.trim().isEmpty) {
      setState(() => _error = '면허번호와 만료일을 입력해주세요.');
      return;
    }
    if (_licensePhoto == null) {
      setState(() => _error = '면허증 사진을 촬영해주세요.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final photoPath = await _licenseService.uploadPhoto(_licensePhoto!);
      await _licenseService.submitLicense(
        licenseNumber: _licenseNumber.text,
        licenseExpiry: _licenseExpiry.text,
        photoPath: photoPath,
      );
      if (!mounted) return;
      setState(() => _loading = false);
      await _goToStep(SignupWizardStep.payment.index);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _registerCardAndNext() async {
    if (_cardRegistered) {
      await _goToStep(SignupWizardStep.complete.index);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final ok = await _paymentService.registerSignupBillingKey(context);
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _loading = false;
          _error = kIsWeb
              ? '카드 등록창에서 완료하거나, 취소 시 이 화면에서 다시 시도해주세요.'
              : '카드 등록이 완료되지 않았습니다. 다시 시도해주세요.';
        });
        return;
      }
      setState(() {
        _loading = false;
        _cardRegistered = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(paymentCardRegistrationSuccessMessage),
        ),
      );
      await _goToStep(SignupWizardStep.complete.index);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _finishSignup() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      WelcomeCouponGrantResult? welcomeCoupon;
      try {
        welcomeCoupon = await _couponService.grantWelcomeCoupon();
      } catch (e) {
        debugPrint('[onboarding] grant_welcome_coupon failed: $e');
      }

      await _myPageService.markSignupComplete();
      final push = PushNotificationService.instance;
      await push.customerSignupComplete();
      final complexId = _complexId;
      if (complexId != null && complexId.isNotEmpty) {
        await push.staffNewSignup(complexId: complexId);
      }
      if (!mounted) return;

      setState(() => _loading = false);

      if (welcomeCoupon?.granted == true) {
        await _showWelcomeCouponDialog();
      }

      if (!mounted) return;
      widget.onCompleted?.call();
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _showWelcomeCouponDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            '가입 축하 쿠폰',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: const Text(
            '가입을 축하합니다! 5,000원 쿠폰이 발급되었습니다.',
            style: TextStyle(height: 1.5),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: DanjiTheme.primaryButton,
              child: const Text('확인'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _scanLicense() async {
    setState(() => _error = null);
    try {
      final result = await _licenseService.captureAndRecognize();
      if (!mounted || result.image == null) return;
      _licensePhoto = result.image;
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

  VoidCallback? get _primaryAction {
    if (_loading) return null;
    return switch (_step) {
      0 => _continueFromResidentStep,
      1 => _savePersonalAndNext,
      2 => _saveLicenseAndNext,
      3 => _registerCardAndNext,
      4 => _finishSignup,
      _ => null,
    };
  }

  String get _primaryLabel => switch (_step) {
        0 || 1 || 2 || 3 => '다음',
        4 => '홈으로 시작하기',
        _ => '다음',
      };

  @override
  Widget build(BuildContext context) {
    final wizardStep = SignupWizardStep.values[_step];

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: DanjiColors.background,
        appBar: AppBar(
          backgroundColor: DanjiColors.background,
          foregroundColor: DanjiColors.textPrimary,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: Text(
            wizardStep.title,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SignupStepIndicator(currentStep: _step),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(
                '${wizardStep.displayIndex}/$_stepCount',
                style: const TextStyle(
                  color: DanjiColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _ResidentStep(
                    inviteCode: _inviteCode,
                    building: _building,
                    unit: _unit,
                    lookingUp: _lookingUp,
                    lookupError: _lookupError,
                    complexName: _complexName,
                    verificationPending: _residentVerificationPending,
                  ),
                  _PersonalStep(
                    name: _name,
                    phone: _phone,
                    address: _address,
                  ),
                  _LicenseStep(
                    licenseNumber: _licenseNumber,
                    licenseExpiry: _licenseExpiry,
                    hasPhoto: _licensePhoto != null,
                    onScan: _scanLicense,
                  ),
                  _PaymentStep(cardRegistered: _cardRegistered),
                  const _CompleteStep(),
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
                      onPressed: _primaryAction,
                      style: DanjiTheme.primaryButton,
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_primaryLabel),
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
}

class _SignupStepIndicator extends StatelessWidget {
  final int currentStep;

  const _SignupStepIndicator({required this.currentStep});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: List.generate(SignupWizardStep.count, (i) {
          final done = i < currentStep;
          final active = i == currentStep;
          return Expanded(
            child: Row(
              children: [
                if (i > 0)
                  Expanded(
                    child: Container(
                      height: 2,
                      color: done || active
                          ? DanjiColors.buttonBlue
                          : DanjiColors.border,
                    ),
                  ),
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: done || active
                        ? DanjiColors.buttonBlue
                        : DanjiColors.border,
                    shape: BoxShape.circle,
                  ),
                  child: done
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : Text(
                          '${i + 1}',
                          style: TextStyle(
                            color: active
                                ? Colors.white
                                : DanjiColors.textMuted,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                ),
                if (i < SignupWizardStep.count - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      color: done
                          ? DanjiColors.buttonBlue
                          : DanjiColors.border,
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _ResidentStep extends StatelessWidget {
  final TextEditingController inviteCode;
  final TextEditingController building;
  final TextEditingController unit;
  final bool lookingUp;
  final String? lookupError;
  final String? complexName;
  final bool verificationPending;

  const _ResidentStep({
    required this.inviteCode,
    required this.building,
    required this.unit,
    required this.lookingUp,
    this.lookupError,
    this.complexName,
    this.verificationPending = false,
  });

  @override
  Widget build(BuildContext context) {
    if (verificationPending) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          ResidentVerificationPendingPanel(),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          '초대코드와 동/호수를 입력해주세요.\n관리자 승인 후 예약이 가능합니다.',
          style: TextStyle(
            color: DanjiColors.textSecondary,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 16),
        _WizardField(
          label: '초대코드',
          controller: inviteCode,
          hint: '예) DANJI2026',
        ),
        if (lookingUp) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(minHeight: 2),
        ],
        if (lookupError != null) ...[
          const SizedBox(height: 8),
          Text(
            lookupError!,
            style: const TextStyle(color: DanjiColors.accentRed),
          ),
        ],
        if (complexName != null) ...[
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const Icon(Icons.apartment, color: DanjiColors.buttonBlue),
              title: Text(complexName!),
              subtitle: const Text('단지가 확인되었습니다.'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        _WizardField(label: '동', controller: building, hint: '예) 101'),
        _WizardField(label: '호', controller: unit, hint: '예) 1203'),
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
          style: TextStyle(color: DanjiColors.textSecondary, height: 1.45),
        ),
        const SizedBox(height: 16),
        _WizardField(label: '이름', controller: name),
        _WizardField(
          label: '휴대폰',
          controller: phone,
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        KakaoAddressField(
          controller: address,
          padding: const EdgeInsets.only(bottom: 14),
          decoration: InputDecoration(
            labelText: '주소',
            hintText: '탭하여 주소 검색',
            filled: true,
            fillColor: DanjiColors.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }
}

class _LicenseStep extends StatelessWidget {
  final TextEditingController licenseNumber;
  final TextEditingController licenseExpiry;
  final bool hasPhoto;
  final VoidCallback onScan;

  const _LicenseStep({
    required this.licenseNumber,
    required this.licenseExpiry,
    required this.hasPhoto,
    required this.onScan,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          '운전면허 정보와 사진을 등록해주세요.\n심사 승인 후 예약·대여가 가능합니다.',
          style: TextStyle(color: DanjiColors.textSecondary, height: 1.45),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: onScan,
          icon: const Icon(Icons.camera_alt_outlined),
          label: Text(hasPhoto ? '면허증 다시 촬영' : '면허증 촬영 (OCR)'),
          style: OutlinedButton.styleFrom(
            foregroundColor: DanjiColors.buttonBlue,
            side: const BorderSide(color: DanjiColors.buttonBlue),
            minimumSize: const Size.fromHeight(48),
          ),
        ),
        if (hasPhoto) ...[
          const SizedBox(height: 8),
          const Row(
            children: [
              Icon(Icons.check_circle, color: DanjiColors.buttonBlue, size: 18),
              SizedBox(width: 6),
              Text(
                '면허증 사진이 선택되었습니다.',
                style: TextStyle(
                  color: DanjiColors.buttonBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        _WizardField(label: '면허번호', controller: licenseNumber),
        _WizardField(
          label: '면허 만료일',
          controller: licenseExpiry,
          hint: '예: 2030-12-31',
        ),
      ],
    );
  }
}

class _PaymentStep extends StatelessWidget {
  final bool cardRegistered;

  const _PaymentStep({required this.cardRegistered});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          '토스페이먼츠로 결제카드를 등록합니다.\n'
          '실제 결제 없이 카드 정보만 등록되며, 빌링키가 발급됩니다.',
          style: TextStyle(color: DanjiColors.textSecondary, height: 1.45),
        ),
        const SizedBox(height: 20),
        if (cardRegistered)
          const Card(
            child: ListTile(
              leading: Icon(Icons.credit_card, color: DanjiColors.buttonBlue),
              title: Text('결제카드 등록 완료'),
              subtitle: Text('다음 단계로 진행할 수 있습니다.'),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '등록 방법',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '「다음」을 누르면 토스 카드 등록창이 열립니다.',
                    style: TextStyle(
                      color: DanjiColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _CompleteStep extends StatelessWidget {
  const _CompleteStep();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 24),
        const Icon(Icons.celebration_outlined,
            size: 64, color: DanjiColors.buttonBlue),
        const SizedBox(height: 16),
        const Text(
          '가입 정보 입력이 완료되었습니다!',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: DanjiColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '입주민 승인이 완료되면 예약·대여를 이용할 수 있습니다.\n'
          '「홈으로 시작하기」를 눌러주세요.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: DanjiColors.textSecondary,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _WizardField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  const _WizardField({
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
