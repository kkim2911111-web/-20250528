import 'package:flutter/material.dart';

import '../../models/super_admin_models.dart';
import '../../services/super_admin_service.dart';
import '../../theme/danji_colors.dart';
import '../../theme/danji_theme.dart';
import '../../utils/danji_snackbar.dart';
import '../../widgets/admin_scaffold.dart';
import '../../widgets/danji_app_bar.dart';
import '../../widgets/section_card.dart';
import 'super_admin_common.dart';

enum _CouponIssueMode { all, complex, individual }

class SuperAdminCouponsScreen extends StatefulWidget {
  final SuperAdminService service;
  const SuperAdminCouponsScreen({super.key, required this.service});
  @override
  State<SuperAdminCouponsScreen> createState() =>
      _SuperAdminCouponsScreenState();
}

class _SuperAdminCouponsScreenState extends State<SuperAdminCouponsScreen> {
  List<SuperAdminCoupon> _coupons = [];
  Object? _loadError;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final data = await widget.service.fetchCoupons();
      if (!mounted) return;
      setState(() {
        _coupons = data;
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

  Future<void> _editor([SuperAdminCoupon? c]) async {
    final title = TextEditingController(text: c?.title ?? '');
    final discount = TextEditingController(text: '${c?.discountAmount ?? 0}');
    final minPay = TextEditingController(text: '${c?.minAmount ?? 0}');

    final ok = await showSuperAdminBottomSheet<bool>(
      context,
      title: c == null ? '쿠폰 등록' : '쿠폰 수정',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: title,
            decoration: const InputDecoration(labelText: '제목'),
          ),
          TextField(
            controller: discount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '할인금액'),
          ),
          TextField(
            controller: minPay,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '최소결제금액'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: superAdminPrimaryFabStyle,
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.service.upsertCoupon(
        id: c?.id,
        title: title.text.trim(),
        discountAmount: int.tryParse(discount.text) ?? 0,
        minAmount: int.tryParse(minPay.text) ?? 0,
        code: c == null
            ? 'COUPON_${DateTime.now().millisecondsSinceEpoch}'
            : null,
      );
      if (!mounted) return;
      await _reload();
    } catch (e) {
      if (mounted) DanjiSnackBar.show(context, friendlySuperAdminError(e));
    }
  }

  Future<void> _issue(SuperAdminCoupon c) async {
    final result = await showSuperAdminBottomSheet<BulkIssueCouponResult>(
      context,
      title: '쿠폰 발급',
      child: _CouponIssueSheet(service: widget.service, coupon: c),
    );
    if (result == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('쿠폰 발급 완료'),
        content: Text('${result.issuedCount}명에게 쿠폰이 발급되었습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    await _reload();
  }

  Future<void> _openDetail(SuperAdminCoupon c) async {
    await showSuperAdminBottomSheet<void>(
      context,
      title: c.title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (c.code != null && c.code!.isNotEmpty) ...[
            Text(
              '코드: ${c.code}',
              style: const TextStyle(color: DanjiColors.textSecondary),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            '₩${superAdminWon.format(c.discountAmount)} 할인 · 최소 ₩${superAdminWon.format(c.minAmount)}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(
            c.usageSummary,
            style: const TextStyle(color: DanjiColors.textSecondary, fontSize: 13),
          ),
          if (c.expiresAt != null) ...[
            const SizedBox(height: 4),
            Text(
              c.isMasterExpired
                  ? '쿠폰 만료 ${superAdminDateTime.format(c.expiresAt!)}'
                  : '쿠폰 유효 ~${superAdminDateTime.format(c.expiresAt!)}',
              style: TextStyle(
                color: c.isMasterExpired
                    ? DanjiColors.textSecondary
                    : DanjiColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
          if (!c.isActive) ...[
            const SizedBox(height: 4),
            const Text(
              '비활성 쿠폰',
              style: TextStyle(color: DanjiColors.textSecondary, fontSize: 12),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _issue(c);
            },
            style: superAdminPrimaryFabStyle,
            child: const Text('발급'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(context);
              _editor(c);
            },
            child: const Text('수정'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              final confirm = await superAdminConfirmDialog(
                context,
                title: '쿠폰 삭제',
                message: '${c.title} 쿠폰을 삭제할까요?',
                confirmLabel: '삭제',
                danger: true,
              );
              if (!confirm) return;
              try {
                await widget.service.deleteCoupon(c.id);
                if (!mounted) return;
                await _reload();
              } catch (e) {
                if (mounted) DanjiSnackBar.show(context, friendlySuperAdminError(e));
              }
            },
            style: DanjiTheme.dangerButton,
            child: const Text('삭제'),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const SuperAdminLoadingBody();
    if (_loadError != null) {
      return Center(child: Text(friendlySuperAdminError(_loadError!)));
    }
    if (_coupons.isEmpty) {
      return RefreshIndicator(
        color: DanjiColors.buttonBlue,
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            SuperAdminEmptyState('쿠폰이 없습니다.'),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: DanjiColors.buttonBlue,
      onRefresh: _reload,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
        itemCount: _coupons.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final c = _coupons[i];
          return SuperAdminListCard(
            icon: Icons.confirmation_number_outlined,
            title: c.title,
            subtitle: '₩${superAdminWon.format(c.discountAmount)} 할인 · '
                '${c.usageSummary}',
            onTap: () => _openDetail(c),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      appBar: const DanjiAppBar(title: '쿠폰 관리'),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: DanjiColors.buttonBlue,
        onPressed: () => _editor(),
        icon: const Icon(Icons.add),
        label: const Text('쿠폰 등록'),
      ),
      body: _buildBody(),
    );
  }
}

class _CouponIssueSheet extends StatefulWidget {
  final SuperAdminService service;
  final SuperAdminCoupon coupon;

  const _CouponIssueSheet({
    required this.service,
    required this.coupon,
  });

  @override
  State<_CouponIssueSheet> createState() => _CouponIssueSheetState();
}

class _CouponIssueSheetState extends State<_CouponIssueSheet> {
  _CouponIssueMode _mode = _CouponIssueMode.all;
  List<SuperAdminComplex> _complexes = [];
  List<SuperAdminResident> _residents = [];
  bool _loading = true;
  Object? _loadError;
  bool _issuing = false;

  String? _selectedComplexId;
  final _searchController = TextEditingController();
  SuperAdminResident? _selectedResident;

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        widget.service.fetchComplexes(),
        widget.service.fetchResidents(),
      ]);
      if (!mounted) return;
      setState(() {
        _complexes = results[0] as List<SuperAdminComplex>;
        _residents = results[1] as List<SuperAdminResident>;
        _loading = false;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  List<SuperAdminResident> get _searchResults {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _residents
        .where((r) {
          final name = (r.fullName ?? '').toLowerCase();
          final email = (r.email ?? '').toLowerCase();
          return name.contains(q) || email.contains(q);
        })
        .take(20)
        .toList();
  }

  int get _allResidentCount => _residents.length;

  int get _complexResidentCount {
    final id = _selectedComplexId;
    if (id == null) return 0;
    return _residents.where((r) => r.complexId == id).length;
  }

  bool get _canIssue {
    if (_issuing || _loading || _loadError != null) return false;
    switch (_mode) {
      case _CouponIssueMode.all:
        return _allResidentCount > 0;
      case _CouponIssueMode.complex:
        return _selectedComplexId != null && _complexResidentCount > 0;
      case _CouponIssueMode.individual:
        return _selectedResident != null;
    }
  }

  String _residentLabel(SuperAdminResident r) {
    final name = r.fullName?.trim();
    final email = r.email?.trim();
    if (name != null && name.isNotEmpty && email != null && email.isNotEmpty) {
      return '$name · $email';
    }
    return name ?? email ?? '이름 미등록';
  }

  Future<void> _submit() async {
    if (!_canIssue) return;

    final confirmMessage = switch (_mode) {
      _CouponIssueMode.all =>
        '전체 입주민 $_allResidentCount명에게\n'
            '「${widget.coupon.title}」 쿠폰을 발급할까요?\n'
            '(이미 보유한 입주민은 제외됩니다)',
      _CouponIssueMode.complex => () {
          final complexName = _complexes
              .firstWhere((c) => c.id == _selectedComplexId)
              .name;
          return '$complexName 입주민 $_complexResidentCount명에게\n'
              '「${widget.coupon.title}」 쿠폰을 발급할까요?\n'
              '(이미 보유한 입주민은 제외됩니다)';
        }(),
      _CouponIssueMode.individual =>
        '${_residentLabel(_selectedResident!)}\n'
            '입주민에게 「${widget.coupon.title}」 쿠폰을 발급할까요?',
    };

    final confirmed = await superAdminConfirmDialog(
      context,
      title: '쿠폰 발급 확인',
      message: confirmMessage,
      confirmLabel: '발급',
    );
    if (!confirmed || !mounted) return;

    setState(() => _issuing = true);
    try {
      final result = await widget.service.bulkIssueCoupon(
        couponId: widget.coupon.id,
        complexId: _mode == _CouponIssueMode.complex
            ? _selectedComplexId
            : null,
        userIds: _mode == _CouponIssueMode.individual
            ? [_selectedResident!.userId]
            : null,
      );
      if (!mounted) return;
      Navigator.pop(context, result);
    } catch (e) {
      if (!mounted) return;
      DanjiSnackBar.show(context, friendlySuperAdminError(e));
      setState(() => _issuing = false);
    }
  }

  Widget _buildModeSelector() {
    return SegmentedButton<_CouponIssueMode>(
      segments: const [
        ButtonSegment(
          value: _CouponIssueMode.all,
          label: Text('전체'),
          icon: Icon(Icons.groups_outlined, size: 18),
        ),
        ButtonSegment(
          value: _CouponIssueMode.complex,
          label: Text('단지별'),
          icon: Icon(Icons.apartment_outlined, size: 18),
        ),
        ButtonSegment(
          value: _CouponIssueMode.individual,
          label: Text('개인'),
          icon: Icon(Icons.person_search_outlined, size: 18),
        ),
      ],
      selected: {_mode},
      onSelectionChanged: (s) {
        setState(() {
          _mode = s.first;
          _selectedResident = null;
        });
      },
    );
  }

  Widget _buildModeBody() {
    switch (_mode) {
      case _CouponIssueMode.all:
        return Text(
          '전체 입주민 $_allResidentCount명 대상\n'
          '이미 해당 쿠폰을 보유한 입주민은 자동으로 제외됩니다.',
          style: const TextStyle(
            color: DanjiColors.textSecondary,
            fontSize: 13,
            height: 1.45,
          ),
        );
      case _CouponIssueMode.complex:
        final sorted = List<SuperAdminComplex>.from(_complexes)
          ..sort((a, b) => a.name.compareTo(b.name));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  isExpanded: true,
                  value: _selectedComplexId,
                  hint: const Text('단지 선택'),
                  items: sorted
                      .map(
                        (c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(c.name),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _selectedComplexId = v),
                ),
              ),
            ),
            if (_selectedComplexId != null) ...[
              const SizedBox(height: 8),
              Text(
                '대상 입주민 $_complexResidentCount명 · '
                '이미 보유한 입주민은 제외됩니다.',
                style: const TextStyle(
                  color: DanjiColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        );
      case _CouponIssueMode.individual:
        final results = _searchResults;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: '이름 또는 이메일 검색',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 8),
            if (_searchController.text.trim().isEmpty)
              const Text(
                '이름 또는 이메일을 입력하세요.',
                style: TextStyle(color: DanjiColors.textSecondary, fontSize: 13),
              )
            else if (results.isEmpty)
              const Text(
                '검색 결과가 없습니다.',
                style: TextStyle(color: DanjiColors.textSecondary, fontSize: 13),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: results.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final r = results[i];
                    final selected = _selectedResident?.userId == r.userId;
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        _residentLabel(r),
                        style: TextStyle(
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        '${r.complexName} ${r.building ?? ''}동 ${r.unit ?? ''}호',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: selected
                          ? const Icon(
                              Icons.check_circle,
                              color: DanjiColors.buttonBlue,
                            )
                          : null,
                      onTap: () => setState(() => _selectedResident = r),
                    );
                  },
                ),
              ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadError != null) {
      return Text(friendlySuperAdminError(_loadError!));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.coupon.title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: DanjiColors.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        _buildModeSelector(),
        const SizedBox(height: 16),
        _buildModeBody(),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _canIssue && !_issuing ? _submit : null,
          style: superAdminPrimaryFabStyle,
          child: _issuing
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('발급'),
        ),
      ],
    );
  }
}
