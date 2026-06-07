import 'package:flutter/material.dart';

import '../../models/super_admin_models.dart';
import '../../services/super_admin_service.dart';
import '../../theme/danji_colors.dart';
import '../../theme/danji_theme.dart';
import '../../utils/danji_snackbar.dart';
import '../../widgets/admin_scaffold.dart';
import '../../widgets/danji_app_bar.dart';
import 'super_admin_common.dart';

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
    final desc = TextEditingController(text: c?.description ?? '');
    final discount = TextEditingController(text: '${c?.discountAmount ?? 0}');
    final minPay = TextEditingController(text: '${c?.minPaymentAmount ?? 0}');

    final ok = await showSuperAdminBottomSheet<bool>(
      context,
      title: c == null ? '쿠폰 등록' : '쿠폰 수정',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: title, decoration: const InputDecoration(labelText: '제목')),
          TextField(controller: desc, decoration: const InputDecoration(labelText: '설명')),
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
        title: title.text,
        description: desc.text,
        discountAmount: int.tryParse(discount.text) ?? 0,
        minPaymentAmount: int.tryParse(minPay.text) ?? 0,
      );
      if (!mounted) return;
      await _reload();
    } catch (e) {
      if (mounted) DanjiSnackBar.show(context, friendlySuperAdminError(e));
    }
  }

  Future<void> _issue(SuperAdminCoupon c) async {
    final userId = TextEditingController();
    final ok = await showSuperAdminBottomSheet<bool>(
      context,
      title: '쿠폰 발급',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: userId,
            decoration: const InputDecoration(labelText: 'user_id (UUID)'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: superAdminPrimaryFabStyle,
            child: const Text('발급'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.service.issueCoupon(userId: userId.text.trim(), couponId: c.id);
      if (!mounted) return;
      DanjiSnackBar.show(context, '쿠폰이 발급되었습니다.');
      await _reload();
    } catch (e) {
      if (mounted) DanjiSnackBar.show(context, friendlySuperAdminError(e));
    }
  }

  Future<void> _openDetail(SuperAdminCoupon c) async {
    await showSuperAdminBottomSheet<void>(
      context,
      title: c.title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (c.description != null && c.description!.isNotEmpty)
            Text(c.description!, style: const TextStyle(color: DanjiColors.textSecondary)),
          const SizedBox(height: 8),
          Text(
            '₩${superAdminWon.format(c.discountAmount)} 할인 · 최소 ₩${superAdminWon.format(c.minPaymentAmount)}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text('발급 ${c.issuedCount} · 사용 ${c.usedCount}',
              style: const TextStyle(color: DanjiColors.textSecondary, fontSize: 13)),
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
                '발급 ${c.issuedCount} · 사용 ${c.usedCount}',
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
