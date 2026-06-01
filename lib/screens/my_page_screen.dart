import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/my_page_profile.dart';
import '../services/auth_service.dart';
import '../services/my_page_service.dart';
import '../theme/danji_colors.dart';
import '../theme/danji_typography.dart';
import '../widgets/danji_app_bar.dart';
import 'license_info_readonly_screen.dart';
import 'my_personal_info_screen.dart';
import 'my_reservations_screen.dart';
import 'resident_info_readonly_screen.dart';
import 'support_pages.dart';

const _pageBg = Color(0xFFEBF2FF);
const _sectionTitle = Color(0xFF5B8DEF);
const _trailingComplete = Color(0xFF2D6AE0);
const _trailingDefault = Color(0xFF8B95A1);

/// 마이페이지 — 토스 스타일
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

  Future<void> _refresh() async {
    final next = _service.fetchProfile();
    if (!mounted) return;
    setState(() {
      _future = next;
    });
    await next;
  }

  Future<void> _editPaymentCard(MyPageProfile profile) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: DanjiColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PaymentCardSheet(initialLast4: profile.cardLast4 ?? ''),
    );
    if (saved == true) _reload();
  }

  Future<void> _openPersonalInfo(MyPageProfile profile) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MyPersonalInfoScreen(profile: profile),
      ),
    );
    if (saved == true) _reload();
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

  void _showInfo(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _formatPoints(int n) {
    return n.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
  }

  @override
  Widget build(BuildContext context) {
    final topPad = widget.embedded ? MediaQuery.of(context).padding.top : 0.0;

    return Scaffold(
      backgroundColor: _pageBg,
      appBar: widget.embedded
          ? null
          : const DanjiAppBar(title: '마이페이지', showBack: true, light: true),
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
                    FilledButton(
                      onPressed: _reload,
                      child: const Text('다시 시도'),
                    ),
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
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(20, 16 + topPad, 20, 32),
              children: [
                _ProfileHeader(profile: profile),
                const SizedBox(height: 28),
                const _SectionLabel(title: '내 정보'),
                const SizedBox(height: 8),
                _MenuCard(
                  items: [
                    _MenuItem(
                      icon: Icons.apartment_outlined,
                      iconColor: Color(0xFF4CAF50),
                      title: '주민인증',
                      trailing: profile.isResidentComplete
                          ? '인증 완료'
                          : profile.hasResidentRegistration
                              ? '승인 대기'
                              : '미등록',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                ResidentInfoReadOnlyScreen(profile: profile),
                          ),
                        );
                      },
                    ),
                    _MenuItem(
                      icon: Icons.badge_outlined,
                      iconColor: Color(0xFF2196F3),
                      title: '운전면허',
                      trailing: profile.isLicenseApproved
                          ? '승인 완료'
                          : !profile.isLicenseComplete
                              ? '미등록'
                              : '심사 중',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                LicenseInfoReadOnlyScreen(profile: profile),
                          ),
                        );
                      },
                    ),
                    _MenuItem(
                      icon: Icons.credit_card_outlined,
                      iconColor: Color(0xFF9C27B0),
                      title: '결제수단',
                      trailing: profile.isPaymentCardComplete ? '등록 완료' : '미등록',
                      onTap: () => _editPaymentCard(profile),
                    ),
                    _MenuItem(
                      icon: Icons.person_outline,
                      iconColor: Color(0xFFFF9800),
                      title: '개인정보',
                      onTap: () => _openPersonalInfo(profile),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const _SectionLabel(title: '이용'),
                const SizedBox(height: 8),
                _MenuCard(
                  items: [
                    _MenuItem(
                      icon: Icons.calendar_month_outlined,
                      iconColor: Color(0xFF2196F3),
                      title: '내 예약',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const MyReservationsScreen(),
                          ),
                        );
                      },
                    ),
                    _MenuItem(
                      icon: Icons.monetization_on_outlined,
                      iconColor: Color(0xFFFFC107),
                      title: '보유 포인트',
                      trailing: '${_formatPoints(profile.points)}P',
                      onTap: () =>
                          _showInfo('포인트 적립·사용 내역은 준비 중입니다.'),
                    ),
                    _MenuItem(
                      icon: Icons.local_offer_outlined,
                      iconColor: Color(0xFFF44336),
                      title: '쿠폰함',
                      trailing: '${profile.couponCount}장',
                      onTap: () => _showInfo('쿠폰함은 준비 중입니다.'),
                    ),
                    _MenuItem(
                      icon: Icons.receipt_long_outlined,
                      iconColor: Color(0xFF607D8B),
                      title: '이용내역',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const MyReservationsScreen(
                              historyOnly: true,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const _SectionLabel(title: '고객지원'),
                const SizedBox(height: 8),
                _MenuCard(
                  items: [
                    _MenuItem(
                      icon: Icons.headset_mic_outlined,
                      iconColor: Color(0xFF00BCD4),
                      title: '고객센터',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const CustomerServiceScreen(),
                          ),
                        );
                      },
                    ),
                    _MenuItem(
                      icon: Icons.help_outline,
                      iconColor: Color(0xFFFF9800),
                      title: '자주 묻는 질문',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const FaqScreen(),
                          ),
                        );
                      },
                    ),
                    _MenuItem(
                      icon: Icons.description_outlined,
                      iconColor: Color(0xFF9E9E9E),
                      title: '약관 및 정책',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const TermsPolicyScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                OutlinedButton(
                  onPressed: _logout,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    foregroundColor: DanjiColors.accentRed,
                    side: const BorderSide(color: DanjiColors.accentRed),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    backgroundColor: Colors.white,
                  ),
                  child: const Text(
                    '로그아웃',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final MyPageProfile profile;

  const _ProfileHeader({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          profile.displayName,
          style: DanjiTypography.headline,
        ),
        if (profile.dongHoLabel != null) ...[
          const SizedBox(height: 6),
          Text(
            profile.dongHoLabel!,
            style: DanjiTypography.secondary,
          ),
        ],
      ],
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
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: _sectionTitle,
          letterSpacing: -0.2,
        ),
      ),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? trailing;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.trailing,
    required this.onTap,
  });
}

class _MenuCard extends StatelessWidget {
  final List<_MenuItem> items;

  const _MenuCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                thickness: 1,
                color: Color(0xFFF2F4F6),
                indent: 56,
              ),
            _MenuRow(item: items[i]),
          ],
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final _MenuItem item;

  const _MenuRow({required this.item});

  static const _completeStatuses = {'인증 완료', '승인 완료', '등록 완료'};

  Color get _trailingColor {
    final t = item.trailing;
    if (t != null && _completeStatuses.contains(t)) {
      return _trailingComplete;
    }
    return _trailingDefault;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(
            children: [
              Icon(
                item.icon,
                size: 22,
                color: item.iconColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.title,
                  style: DanjiTypography.body,
                ),
              ),
              if (item.trailing != null) ...[
                Text(
                  item.trailing!,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: _trailingColor,
                  ),
                ),
                const SizedBox(width: 2),
              ],
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: Color(0xFFB0B8C1),
              ),
            ],
          ),
        ),
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
      setState(() {
        _error = '카드 번호 뒤 4자리를 입력해주세요.';
      });
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
      if (!mounted) return;
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
            '결제수단 등록',
            style: TextStyle(
              color: DanjiColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _last4,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            decoration: const InputDecoration(
              labelText: '카드 뒤 4자리',
              filled: true,
              fillColor: Color(0xFFF2F4F6),
              border: OutlineInputBorder(borderSide: BorderSide.none),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: DanjiColors.accentRed)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: DanjiColors.buttonBlue,
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
