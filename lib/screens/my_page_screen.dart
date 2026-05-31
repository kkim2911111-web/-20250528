import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/my_page_profile.dart';
import '../resident_profile_screen.dart';
import '../services/auth_service.dart';
import '../services/my_page_service.dart';
import '../theme/danji_colors.dart';
import '../widgets/danji_app_bar.dart';
import '../widgets/section_card.dart';
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

  Future<void> _editBasicInfo(MyPageProfile profile) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SectionCard.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _BasicInfoSheet(
        initialName: profile.name ?? '',
        initialPhone: profile.phone ?? '',
        initialAddress: profile.address ?? '',
        email: profile.email ?? '',
        linkedProviders: profile.linkedProviders,
      ),
    );
    if (saved == true) _reload();
  }

  Future<void> _editLicense(MyPageProfile profile) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SectionCard.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _LicenseSheet(
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
      backgroundColor: SectionCard.cardColor,
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
              padding: const EdgeInsets.all(20),
              children: [
                _ProfileHeaderTitle(title: profile.pageHeaderTitle),
                if (!profile.isResidentComplete) ...[
                  const SizedBox(height: 16),
                  _ResidentRequiredBanner(
                    hasRegistration: profile.hasResidentRegistration,
                    onTap: _openResidentVerification,
                  ),
                ],
                const SizedBox(height: 20),
                const _SectionTitle(title: '내 정보'),
                const SizedBox(height: 10),
                _RequiredSection(
                  icon: Icons.apartment_outlined,
                  title: '입주민 인증',
                  isComplete: profile.isResidentComplete,
                  onTap: _openResidentVerification,
                  child: Column(
                    children: [
                      _FieldRow(
                        label: '단지',
                        value: profile.hasResidentRegistration
                            ? (profile.residentComplexName ?? '등록됨')
                            : '미등록',
                        isMissing: !profile.hasResidentRegistration,
                      ),
                      _FieldRow(
                        label: '동/호',
                        value: profile.residentLocationLabel ??
                            (profile.hasResidentRegistration
                                ? '등록됨'
                                : '미등록'),
                        isMissing: !profile.hasResidentRegistration,
                      ),
                      _FieldRow(
                        label: '승인 상태',
                        value: profile.isResidentComplete
                            ? '승인 완료'
                            : profile.hasResidentRegistration
                                ? '승인 대기'
                                : '미등록',
                        isMissing: !profile.isResidentComplete,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _RequiredSection(
                  icon: Icons.person_outline,
                  title: '기본정보',
                  isComplete: profile.isBasicInfoComplete,
                  onTap: () => _editBasicInfo(profile),
                  child: Column(
                    children: profile.basicInfoFields
                        .map(
                          (field) => _FieldRow(
                            label: field.label,
                            value: field.isComplete
                                ? field.value
                                : '미등록',
                            isMissing: !field.isComplete,
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(height: 10),
                _RequiredSection(
                  icon: Icons.badge_outlined,
                  title: '면허정보',
                  isComplete: profile.isLicenseComplete,
                  onTap: () => _editLicense(profile),
                  child: Column(
                    children: [
                      _FieldRow(
                        label: '면허번호',
                        value: profile.hasLicenseNumber
                            ? profile.licenseNumber
                            : '미등록',
                        isMissing: !profile.hasLicenseNumber,
                      ),
                      _FieldRow(
                        label: '만료일',
                        value: profile.hasLicenseExpiry
                            ? profile.licenseExpiry
                            : '미등록',
                        isMissing: !profile.hasLicenseExpiry,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _RequiredSection(
                  icon: Icons.credit_card_outlined,
                  title: '결제카드 등록',
                  isComplete: profile.isPaymentCardComplete,
                  onTap: () => _editPaymentCard(profile),
                  child: _FieldRow(
                    label: '등록 카드',
                    value: profile.isPaymentCardComplete
                        ? '**** ${profile.cardLast4}'
                        : '미등록',
                    isMissing: !profile.isPaymentCardComplete,
                  ),
                ),
                if (!profile.canUseVehicle) ...[
                  const SizedBox(height: 16),
                  _WarningBanner(profile: profile),
                ],
                const SizedBox(height: 20),
                _OptionalTile(
                  icon: Icons.assignment_outlined,
                  title: '내 예약',
                  trailing: null,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MyReservationsScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                _OptionalTile(
                  icon: Icons.stars_outlined,
                  title: '보유 포인트',
                  trailing: '${_formatNumber(profile.points)}P',
                  onTap: () => _showInfo('포인트 적립·사용 내역은 준비 중입니다.'),
                ),
                const SizedBox(height: 8),
                _OptionalTile(
                  icon: Icons.local_offer_outlined,
                  title: '쿠폰함',
                  trailing: '${profile.couponCount}장',
                  onTap: () => _showInfo('쿠폰함은 준비 중입니다.'),
                ),
                const SizedBox(height: 8),
                _OptionalTile(
                  icon: Icons.receipt_long_outlined,
                  title: '이용내역',
                  trailing: null,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            const MyReservationsScreen(historyOnly: true),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 28),
                const _SectionTitle(title: '고객지원'),
                const SizedBox(height: 10),
                _OptionalTile(
                  icon: Icons.headset_mic_outlined,
                  title: '고객센터',
                  trailing: null,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CustomerServiceScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                _OptionalTile(
                  icon: Icons.help_outline,
                  title: '자주 묻는 질문',
                  trailing: null,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const FaqScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                _OptionalTile(
                  icon: Icons.description_outlined,
                  title: '약관 및 정책',
                  trailing: null,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const TermsPolicyScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 28),
                OutlinedButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout, color: DanjiColors.accentRed),
                  label: const Text(
                    '로그아웃',
                    style: TextStyle(
                      color: DanjiColors.accentRed,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    side: const BorderSide(color: DanjiColors.accentRed),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
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
  bool get hasLicenseNumber =>
      licenseNumber != null && licenseNumber!.trim().isNotEmpty;

  bool get hasLicenseExpiry =>
      licenseExpiry != null && licenseExpiry!.trim().isNotEmpty;
}

class _ProfileHeaderTitle extends StatelessWidget {
  final String title;

  const _ProfileHeaderTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: DanjiColors.textPrimary,
        fontSize: 22,
        fontWeight: FontWeight.w800,
        height: 1.35,
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  final MyPageProfile profile;

  const _WarningBanner({required this.profile});

  @override
  Widget build(BuildContext context) {
    final missing = <String>[];
    if (!profile.isResidentComplete) missing.add('입주민 인증');
    if (!profile.isBasicInfoComplete) missing.add('기본정보');
    if (!profile.isLicenseComplete) missing.add('면허정보');
    if (!profile.isPaymentCardComplete) missing.add('결제카드');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DanjiColors.accentRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DanjiColors.accentRed.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: DanjiColors.accentRed, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              missing.isEmpty
                  ? '현재 차량을 이용할 수 없습니다.'
                  : '차량 이용 전 필수 등록이 필요합니다: ${missing.join(', ')}',
              style: const TextStyle(
                color: DanjiColors.accentRed,
                fontWeight: FontWeight.w700,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResidentRequiredBanner extends StatelessWidget {
  final bool hasRegistration;
  final VoidCallback onTap;

  const _ResidentRequiredBanner({
    required this.hasRegistration,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final message = hasRegistration
        ? '입주민 인증 승인 대기 중입니다. 승인 후 예약·이용이 가능합니다.'
        : '입주민 인증이 필요합니다. 초대코드와 동/호수를 등록해주세요.';

    return Material(
      color: DanjiColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: DanjiColors.accentRed.withValues(alpha: 0.5)),
            color: DanjiColors.accentRed.withValues(alpha: 0.06),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.apartment, color: DanjiColors.accentRed, size: 24),
                  SizedBox(width: 10),
                  Text(
                    '입주민 인증 필요',
                    style: TextStyle(
                      color: DanjiColors.accentRed,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: const TextStyle(
                  color: DanjiColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onTap,
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: Text(hasRegistration ? '인증 상태 확인' : '입주민 인증하기'),
                style: FilledButton.styleFrom(
                  backgroundColor: DanjiColors.accentRed,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(44),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: DanjiColors.textPrimary,
        fontSize: 17,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _RequiredSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool isComplete;
  final VoidCallback onTap;
  final Widget child;

  const _RequiredSection({
    required this.icon,
    required this.title,
    required this.isComplete,
    required this.onTap,
    required this.child,
  });

  static const _success = DanjiColors.primaryBlue;

  @override
  Widget build(BuildContext context) {
    final statusColor = isComplete ? _success : DanjiColors.accentRed;
    final statusLabel = isComplete ? '등록완료' : '미등록';

    return SectionCard(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: statusColor, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: isComplete
                          ? DanjiColors.textPrimary
                          : DanjiColors.accentRed,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  color: DanjiColors.textMuted,
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: DanjiColors.border),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  final String label;
  final String? value;
  final bool isMissing;

  const _FieldRow({
    required this.label,
    required this.value,
    required this.isMissing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                color: DanjiColors.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value ?? '미등록',
              style: TextStyle(
                color: isMissing
                    ? DanjiColors.accentRed
                    : DanjiColors.textPrimary,
                fontWeight: isMissing ? FontWeight.w700 : FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionalTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? trailing;
  final VoidCallback onTap;

  const _OptionalTile({
    required this.icon,
    required this.title,
    required this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: DanjiColors.primaryBlue),
        title: Text(
          title,
          style: const TextStyle(
            color: DanjiColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (trailing != null)
              Text(
                trailing!,
                style: const TextStyle(
                  color: DanjiColors.textMuted,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            const Icon(Icons.chevron_right, color: DanjiColors.textMuted),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _BasicInfoSheet extends StatefulWidget {
  final String initialName;
  final String initialPhone;
  final String initialAddress;
  final String email;
  final List<String> linkedProviders;

  const _BasicInfoSheet({
    required this.initialName,
    required this.initialPhone,
    required this.initialAddress,
    required this.email,
    required this.linkedProviders,
  });

  @override
  State<_BasicInfoSheet> createState() => _BasicInfoSheetState();
}

class _BasicInfoSheetState extends State<_BasicInfoSheet> {
  final _service = MyPageService();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName);
    _phone = TextEditingController(text: widget.initialPhone);
    _address = TextEditingController(text: widget.initialAddress);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty ||
        _phone.text.trim().isEmpty ||
        _address.text.trim().isEmpty) {
      setState(() => _error = '이름, 휴대전화, 주소를 모두 입력해주세요.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _service.saveBasicInfo(
        name: _name.text,
        phone: _phone.text,
        address: _address.text,
      );
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
    final snsLabel = widget.linkedProviders.isEmpty
        ? '미연동'
        : widget.linkedProviders
            .map(MyPageProfile.providerLabel)
            .join(', ');

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '기본정보 등록',
            style: TextStyle(
              color: DanjiColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          _SheetField(label: '이름', controller: _name),
          _SheetField(
            label: '휴대전화',
            controller: _phone,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          _SheetReadOnlyField(label: '이메일', value: widget.email),
          _SheetReadOnlyField(label: 'SNS 로그인 연동', value: snsLabel),
          _SheetField(label: '주소', controller: _address),
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
                : const Text('저장'),
          ),
        ],
      ),
    );
  }
}

class _LicenseSheet extends StatefulWidget {
  final String initialNumber;
  final String initialExpiry;

  const _LicenseSheet({
    required this.initialNumber,
    required this.initialExpiry,
  });

  @override
  State<_LicenseSheet> createState() => _LicenseSheetState();
}

class _LicenseSheetState extends State<_LicenseSheet> {
  final _service = MyPageService();
  late final TextEditingController _number;
  late final TextEditingController _expiry;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _number = TextEditingController(text: widget.initialNumber);
    _expiry = TextEditingController(text: widget.initialExpiry);
  }

  @override
  void dispose() {
    _number.dispose();
    _expiry.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_number.text.trim().isEmpty || _expiry.text.trim().isEmpty) {
      setState(() => _error = '면허번호와 만료일을 입력해주세요.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _service.saveLicense(
        licenseNumber: _number.text,
        licenseExpiry: _expiry.text,
      );
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
            '면허정보 등록',
            style: TextStyle(
              color: DanjiColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          _SheetField(label: '면허번호', controller: _number),
          _SheetField(
            label: '만료일',
            controller: _expiry,
            hint: '예: 2030-12-31',
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
                : const Text('저장'),
          ),
        ],
      ),
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

class _SheetReadOnlyField extends StatelessWidget {
  final String label;
  final String value;

  const _SheetReadOnlyField({required this.label, required this.value});

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
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: DanjiColors.skyLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: DanjiColors.border),
            ),
            child: Text(
              value,
              style: const TextStyle(color: DanjiColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
