import 'package:flutter/material.dart';

import '../../models/super_admin_models.dart';
import '../../services/super_admin_service.dart';
import '../../theme/danji_colors.dart';
import '../../utils/danji_snackbar.dart';
import '../../widgets/section_card.dart';
import 'super_admin_common.dart';

class SuperAdminCouponsScreen extends StatefulWidget {
  final SuperAdminService service;
  const SuperAdminCouponsScreen({super.key, required this.service});
  @override
  State<SuperAdminCouponsScreen> createState() =>
      _SuperAdminCouponsScreenState();
}

class _SuperAdminCouponsScreenState extends State<SuperAdminCouponsScreen> {
  Future<List<SuperAdminCoupon>>? _future;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => setState(() => _future = widget.service.fetchCoupons());

  Future<void> _editor([SuperAdminCoupon? c]) async {
    final title = TextEditingController(text: c?.title ?? '');
    final desc = TextEditingController(text: c?.description ?? '');
    final discount = TextEditingController(text: '${c?.discountAmount ?? 0}');
    final minPay = TextEditingController(text: '${c?.minPaymentAmount ?? 0}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(c == null ? '쿠폰 등록' : '쿠폰 수정'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: '제목')),
            TextField(controller: desc, decoration: const InputDecoration(labelText: '설명')),
            TextField(controller: discount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '할인금액')),
            TextField(controller: minPay, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '최소결제금액')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('저장')),
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
      _reload();
    } catch (e) {
      if (mounted) DanjiSnackBar.show(context, friendlySuperAdminError(e));
    }
  }

  Future<void> _issue(SuperAdminCoupon c) async {
    final userId = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('쿠폰 발급'),
        content: TextField(
          controller: userId,
          decoration: const InputDecoration(labelText: 'user_id (UUID)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('발급')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.service.issueCoupon(userId: userId.text.trim(), couponId: c.id);
      if (mounted) DanjiSnackBar.show(context, '쿠폰이 발급되었습니다.');
      _reload();
    } catch (e) {
      if (mounted) DanjiSnackBar.show(context, friendlySuperAdminError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DanjiColors.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editor(),
        icon: const Icon(Icons.add),
        label: const Text('쿠폰 등록'),
      ),
      body: FutureBuilder<List<SuperAdminCoupon>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text(friendlySuperAdminError(snap.error!)));
          }
          final list = snap.data ?? [];
          if (list.isEmpty) {
            return const Center(child: Text('쿠폰이 없습니다.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final c = list[i];
              return SectionCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text('₩${superAdminWon.format(c.discountAmount)} 할인 · 최소 ₩${superAdminWon.format(c.minPaymentAmount)}',
                        style: const TextStyle(fontSize: 12, color: DanjiColors.textSecondary)),
                    Text('발급 ${c.issuedCount} · 사용 ${c.usedCount}', style: const TextStyle(fontSize: 12)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(onPressed: () => _issue(c), child: const Text('발급')),
                        TextButton(onPressed: () => _editor(c), child: const Text('수정')),
                        TextButton(
                          onPressed: () async {
                            await widget.service.deleteCoupon(c.id);
                            _reload();
                          },
                          child: const Text('삭제', style: TextStyle(color: DanjiColors.danger)),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
