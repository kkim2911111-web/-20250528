import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/my_page_profile.dart';
import '../resident_profile_screen.dart';
import '../services/auth_service.dart';
import '../services/my_page_service.dart';
import '../theme/danji_colors.dart';
import '../widgets/danji_app_bar.dart';
import '../widgets/license_registration_sheet.dart';
import 'my_personal_info_screen.dart';
import 'my_reservations_screen.dart';
import 'support_pages.dart';

class MyPageScreen extends StatefulWidget {
  final bool embedded;

  const MyPageScreen({super.key, this.embedded = false});

  @override
  State<MyPageScreen> createState() => _MyPageScreenState();
}

class _MyPageScreenState extends State<MyPageScreen> {
  final _service = MyPageService();
  final _auth = AuthService();
  Future<MyPageProfile>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = _service.fetchProfile();
    });
  }

  Future<void> _openPersonalInfo(MyPageProfile profile) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MyPersonalInfoScreen(profile: profile),
      ),
    );
    if (saved == true) _reload();
  }

  Future<void> _editLicense(MyPageProfile profile) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: DanjiColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => LicenseRegistrationSheet(
        initialNumber: profile.licenseNumber ?? '',
        initialExpiry: profile.licenseExpiry ?? '',
      ),
    );
    if (saved == true) _reload();
  }

  Future<void> _editPaymentCard(MyPageProfile profile) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: DanjiColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PaymentCardSheet(
        initialLast4: profile.cardLast4 ?? '',
      ),
    );
    if (saved == true) _reload();
  }

  Future<void> _openResidentVerification() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ResidentProfileScreen(embedded: true),
      ),
    );
    _reload();
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DanjiColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '로그아웃',
          style: TextStyle(
            color: DanjiColors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: const Text(
          '로그아웃 하시겠습니까?',
          style: TextStyle(color: DanjiColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: DanjiColors.accentRed,
              foregroundColor: Colors.white,
            ),
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _auth.signOut(toSignUp: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: DanjiAppBar(
        title: '마이페이지',
        showBack: !widget.embedded,
        showHome: !widget.embedded,
        light: true,
      ),
      body: FutureBuilder<MyPageProfile>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      snap.error.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: DanjiColors.accentRed),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _reload, child: const Text('다시 시도')),
                  ],
                ),
              ),
            );
          }

          final profile = snap.data;
          if (profile == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              children: [
                _ProfileSummaryHeader(profile: profile),
                if (!profile.canUseVehicle) ...[
                  const SizedBox(height: 16),
                  _CompactSetupHint(profile: profile),
                ],
                const SizedBox(height: 36),
                _ManageMenuGroup(
                  children: [
                    _ManageRow(
                      icon: Icons.apartment_rounded,
                      iconColor: const Color(0xFF5C6BC0),
                      title: '아파트 인증 관리',
                      status: profile.residentManageStatus,
                      statusComplete: profile.isResidentComplete,
                      onTap: _openResidentVerification,
                    ),
                    _ManageRow(
                      icon: Icons.badge_outlined,
                      iconColor: const Color(0xFF26A69A),
                      title: '운전면허 관리',
                      status: profile.licenseManageStatus,
                      statusComplete: profile.isLicenseApproved,
                      onTap: () => _editLicense(profile),
                    ),
                    _ManageRow(
                      icon: Icons.credit_card_rounded,
                      iconColor: const Color(0xFF42A5F5),
                      title: '결제 수단 관리',
                      status: profile.paymentManageStatus,
                      statusComplete: profile.isPaymentCardComplete,
                      onTap: () => _editPaymentCard(profile),
                    ),
                    _ManageRow(
                      icon: Icons.person_outline_rounded,
                      iconColor: const Color(0xFF78909C),
                      title: '개인정보 수정',
                      status: profile.isBasicInfoComplete ? null : '미등록',
                      statusComplete: profile.isBasicInfoComplete,
                      onTap: () => _openPersonalInfo(profile),
                      showDivider: false,
                    ),
                  ],
                ),
                const SizedBox(height: 36),
                const _SectionLabel(title: '이용'),
                const SizedBox(height: 12),
                _ManageMenuGroup(
                  children: [
                    _ManageRow(
                      icon: Icons.assignment_outlined,
                      iconColor: DanjiColors.buttonBlue,
                      title: '내 예약',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const MyReservationsScreen(),
                          ),
                        );
                      },
                    ),
                    _ManageRow(
                      icon: Icons.stars_outlined,
                      iconColor: const Color(0xFFFFB300),
                      title: '보유 포인트',
                      status: '${_formatNumber(profile.points)}P',
                      statusComplete: true,
                      onTap: () => _showInfo('포인트 적립·사용 내역은 준비 중입니다.'),
                    ),
                    _ManageRow(
                      icon: Icons.local_offer_outlined,
                      iconColor: const Color(0xFFEF5350),
                      title: '쿠폰함',
                      status: '${profile.couponCount}장',
                      statusComplete: true,
                      onTap: () => _showInfo('쿠폰함은 준비 중입니다.'),
                    ),
                    _ManageRow(
                      icon: Icons.receipt_long_outlined,
                      iconColor: const Color(0xFF8D6E63),
                      title: '이용내역',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                const MyReservationsScreen(historyOnly: true),
                          ),
                        );
                      },
                      showDivider: false,
                    ),
                  ],
                ),
                const SizedBox(height: 36),
                const _SectionLabel(title: '고객지원'),
                const SizedBox(height: 12),
                _ManageMenuGroup(
                  children: [
                    _ManageRow(
                      icon: Icons.headset_mic_outlined,
                      iconColor: DanjiColors.buttonBlue,
                      title: '고객센터',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const CustomerServiceScreen(),
                          ),
                        );
                      },
                    ),
                    _ManageRow(
                      icon: Icons.help_outline_rounded,
                      iconColor: const Color(0xFF78909C),
                      title: '자주 묻는 질문',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const FaqScreen(),
                          ),
                        );
                      },
                    ),
                    _ManageRow(
                      icon: Icons.description_outlined,
                      iconColor: const Color(0xFF78909C),
                      title: '약관 및 정책',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const TermsPolicyScreen(),
                          ),
                        );
                      },
                      showDivider: false,
                    ),
                  ],
                ),
                const SizedBox(height: 40),
                Center(
                  child: TextButton(
                    onPressed: _logout,
                    child: const Text(
                      '로그아웃',
                      style: TextStyle(
                        color: DanjiColors.textMuted,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showInfo(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _formatNumber(int n) {
    return n.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
  }
}

extension on MyPageProfile {
  String get licenseManageStatus {
    if (isLicenseApproved) return '승인 완료';
    if (!isLicenseComplete) return '미등록';
    if (licenseRejectionReason != null &&
        licenseRejectionReason!.trim().isNotEmpty) {
      return '거절';
    }
    return '심사 중';
  }

  String get residentManageStatus {
    if (isResidentComplete) {
      final unit = residentUnit?.trim();
      if (unit != null && unit.isNotEmpty) return '인증 완료($unit호)';
      return '인증 완료';
    }
    if (hasResidentRegistration) return '승인 대기';
    return '미등록';
  }

  String get paymentManageStatus {
    if (isPaymentCardComplete) return '등록 완료(**** $cardLast4)';
    return '미등록';
  }

  String? get apartmentSummary {
    final parts = <String>[];
    if (residentComplexName != null && residentComplexName!.trim().isNotEmpty) {
      parts.add(residentComplexName!.trim());
    }
    final dongHo = dongHoLabel;
    if (dongHo != null) parts.add(dongHo);
    return parts.isEmpty ? null : parts.join(' ');
  }
}

class _ProfileSummaryHeader extends StatelessWidget {
  final MyPageProfile profile;

  const _ProfileSummaryHeader({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          profile.displayName,
          style: const TextStyle(
            color: Color(0xFF263238),
            fontSize: 26,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
            height: 1.2,
          ),
        ),
        if (profile.apartmentSummary != null) ...[
          const SizedBox(height: 6),
          Text(
            profile.apartmentSummary!,
            style: const TextStyle(
              color: DanjiColors.textMuted,
              fontSize: 15,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.3,
              height: 1.4,
            ),
          ),
        ] else ...[
          const SizedBox(height: 6),
          const Text(
            '아파트 인증을 완료해주세요',
            style: TextStyle(
              color: DanjiColors.textMuted,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

class _CompactSetupHint extends StatelessWidget {
  final MyPageProfile profile;

  const _CompactSetupHint({required this.profile});

  @override
  Widget build(BuildContext context) {
    final missing = <String>[];
    if (!profile.isResidentComplete) missing.add('아파트 인증');
    if (!profile.isBasicInfoComplete) missing.add('개인정보');
    if (!profile.isLicenseComplete || !profile.isLicenseApproved) {
      missing.add('운전면허');
    }
    if (!profile.isPaymentCardComplete) missing.add('결제 수단');

    if (missing.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: DanjiColors.accentRed.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '차량 이용을 위해 ${missing.join(' · ')}을(를) 완료해주세요',
        style: const TextStyle(
          color: DanjiColors.accentRed,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          height: 1.45,
          letterSpacing: -0.2,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String title;

  const _SectionLabel({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: const TextStyle(
          color: DanjiColors.textMuted,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
    );
  }
}

class _ManageMenuGroup extends StatelessWidget {
  final List<Widget> children;

  const _ManageMenuGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: DanjiColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _ManageRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? status;
  final bool statusComplete;
  final VoidCallback onTap;
  final bool showDivider;

  const _ManageRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.status,
    this.statusComplete = false,
    required this.onTap,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = status == null
        ? DanjiColors.textMuted
        : statusComplete
            ? DanjiColors.textMuted
            : DanjiColors.accentRed;

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: iconColor, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF37474F),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  if (status != null) ...[
                    Flexible(
                      child: Text(
                        status!,
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Icon(
                    Icons.chevron_right_rounded,
                    color: DanjiColors.textMuted.withValues(alpha: 0.7),
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            thickness: 1,
            indent: 72,
            endIndent: 18,
            color: DanjiColors.border.withValues(alpha: 0.6),
          ),
      ],
    );
  }
}

class _PaymentCardSheet extends StatefulWidget {
  final String initialLast4;

  const _PaymentCardSheet({required this.initialLast4});

  @override
  State<_PaymentCardSheet> createState() => _PaymentCardSheetState();
}

class _PaymentCardSheetState extends State<_PaymentCardSheet> {
  final _service = MyPageService();
  late final TextEditingController _last4;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _last4 = TextEditingController(text: widget.initialLast4);
  }

  @override
  void dispose() {
    _last4.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final last4 = _last4.text.trim();
    if (last4.length != 4) {
      setState(() => _error = '카드 번호 뒤 4자리를 입력해주세요.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _service.savePaymentCard(cardLast4: last4);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '결제카드 등록',
            style: TextStyle(
              color: DanjiColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '테스트용 등록입니다. 실제 카드 결제는 토스페이먼츠 연동 후 적용됩니다.',
            style: TextStyle(
              color: DanjiColors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          _SheetField(
            label: '카드 뒤 4자리',
            controller: _last4,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: DanjiColors.accentRed)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: DanjiColors.rentalBlue,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('등록'),
          ),
        ],
      ),
    );
  }
}

class _SheetField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  const _SheetField({
    required this.label,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: DanjiColors.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            style: const TextStyle(color: DanjiColors.textPrimary),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: DanjiColors.textSecondary.withValues(alpha: 0.7),
              ),
              filled: true,
              fillColor: DanjiColors.skyLight,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: DanjiColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: DanjiColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: DanjiColors.primaryBlue),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
