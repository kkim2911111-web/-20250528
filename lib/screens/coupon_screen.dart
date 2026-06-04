import 'package:flutter/material.dart';

import '../models/coupon.dart';
import '../services/coupon_service.dart';
import '../theme/danji_colors.dart';
import '../theme/danji_typography.dart';
import '../widgets/danji_app_bar.dart';

abstract final class _CouponColors {
  static const ticketBg = Color(0xFF12122A);
  static const gold = Color(0xFFD4AF37);
  static const ticketText = Color(0xFFF5F0E6);
  static const ticketSub = Color(0xFFB8B0A0);
  static const expiryGray = Color(0xFF8B95A1);
  static const expiryOrange = Color(0xFFFF9800);
  static const expiryRed = DanjiColors.toneRed;
}

class CouponScreen extends StatefulWidget {
  const CouponScreen({super.key});

  @override
  State<CouponScreen> createState() => _CouponScreenState();
}

class _CouponScreenState extends State<CouponScreen>
    with SingleTickerProviderStateMixin {
  final _service = CouponService();
  late TabController _tabController;
  Future<List<UserCoupon>>? _future;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _reload();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _future = _service.fetchMyCoupons();
    });
  }

  static List<UserCoupon> _sortAvailable(List<UserCoupon> list) {
    final copy = List<UserCoupon>.from(list);
    copy.sort((a, b) {
      final aUrgent = a.isExpiringWithin7Days;
      final bUrgent = b.isExpiringWithin7Days;
      if (aUrgent != bUrgent) return aUrgent ? -1 : 1;
      final ad = a.daysUntilExpiry ?? 99999;
      final bd = b.daysUntilExpiry ?? 99999;
      if (ad != bd) return ad.compareTo(bd);
      return b.createdAt?.compareTo(a.createdAt ?? DateTime(1970)) ?? 0;
    });
    return copy;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: DanjiAppBar(
        title: '쿠폰함',
        showHome: false,
        extraActions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: DanjiColors.surface,
            child: TabBar(
              controller: _tabController,
              labelColor: DanjiColors.brandBlue,
              unselectedLabelColor: DanjiColors.textSecondary,
              indicatorColor: DanjiColors.brandBlue,
              indicatorWeight: 2.5,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelStyle: DanjiTypography.body.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
              tabs: const [
                Tab(text: '사용 가능'),
                Tab(text: '사용 완료'),
                Tab(text: '만료됨'),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<UserCoupon>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return _ErrorBody(
                    message: snap.error.toString(),
                    onRetry: _reload,
                  );
                }

                final all = snap.data ?? [];
                final available = _sortAvailable(
                  all.where((c) => c.isCouponAvailableTab).toList(),
                );
                final used = all
                    .where((c) => c.isCouponUsedTab)
                    .toList(growable: false);
                final expired = all
                    .where((c) => c.isCouponExpiredTab)
                    .toList(growable: false);

                return TabBarView(
                  controller: _tabController,
                  children: [
                    _CouponList(
                      coupons: available,
                      emptyMessage: '사용 가능한 쿠폰이 없습니다.',
                      onRefresh: () async => _reload(),
                      groupExpiringSoon: true,
                    ),
                    _CouponList(
                      coupons: used,
                      emptyMessage: '사용 완료된 쿠폰이 없습니다.',
                      onRefresh: () async => _reload(),
                      dimmed: true,
                      preferUsedDate: true,
                    ),
                    _CouponList(
                      coupons: expired,
                      emptyMessage: '만료된 쿠폰이 없습니다.',
                      onRefresh: () async => _reload(),
                      dimmed: true,
                      preferUsedDate: true,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CouponList extends StatelessWidget {
  final List<UserCoupon> coupons;
  final String emptyMessage;
  final Future<void> Function() onRefresh;
  final bool dimmed;
  final bool preferUsedDate;
  final bool groupExpiringSoon;

  const _CouponList({
    required this.coupons,
    required this.emptyMessage,
    required this.onRefresh,
    this.dimmed = false,
    this.preferUsedDate = false,
    this.groupExpiringSoon = false,
  });

  @override
  Widget build(BuildContext context) {
    if (coupons.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
            Center(
              child: Text(
                emptyMessage,
                style: DanjiTypography.secondary,
              ),
            ),
          ],
        ),
      );
    }

    final urgent = groupExpiringSoon
        ? coupons.where((c) => c.isExpiringWithin7Days).toList()
        : const <UserCoupon>[];
    final rest = groupExpiringSoon
        ? coupons.where((c) => !c.isExpiringWithin7Days).toList()
        : coupons;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          if (urgent.isNotEmpty) ...[
            _SectionLabel(text: '만료 임박'),
            for (var i = 0; i < urgent.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              _CouponTicketCard(
                coupon: urgent[i],
                dimmed: dimmed,
                preferUsedDate: preferUsedDate,
              ),
            ],
            if (rest.isNotEmpty) ...[
              const SizedBox(height: 22),
              _SectionLabel(text: '사용 가능'),
            ],
          ],
          for (var i = 0; i < rest.length; i++) ...[
            if (i > 0 || urgent.isNotEmpty) const SizedBox(height: 14),
            _CouponTicketCard(
              coupon: rest[i],
              dimmed: dimmed,
              preferUsedDate: preferUsedDate,
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: DanjiTypography.subtitle.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: DanjiColors.textPrimary,
        ),
      ),
    );
  }
}

class _CouponTicketCard extends StatelessWidget {
  final UserCoupon coupon;
  final bool dimmed;
  final bool preferUsedDate;

  const _CouponTicketCard({
    required this.coupon,
    this.dimmed = false,
    this.preferUsedDate = false,
  });

  Color _validityColor(CouponValidityTone tone) {
    switch (tone) {
      case CouponValidityTone.urgentRed:
        return _CouponColors.expiryRed;
      case CouponValidityTone.urgentOrange:
        return _CouponColors.expiryOrange;
      case CouponValidityTone.normal:
        return _CouponColors.expiryGray;
      case CouponValidityTone.muted:
        return _CouponColors.ticketSub;
    }
  }

  @override
  Widget build(BuildContext context) {
    final benefit = coupon.displayBenefit;
    final validity = CouponValidityDisplay.forCoupon(
      coupon,
      preferUsedDate: preferUsedDate,
    );

    return Opacity(
      opacity: dimmed ? 0.72 : 1,
      child: CustomPaint(
        painter: _TicketPainter(
          color: _CouponColors.ticketBg,
          accent: _CouponColors.gold,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _CouponColors.gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _CouponColors.gold.withValues(alpha: 0.45),
                  ),
                ),
                child: const Icon(
                  Icons.local_offer_rounded,
                  color: _CouponColors.gold,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      coupon.displayTitle,
                      style: const TextStyle(
                        color: _CouponColors.ticketText,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                    if (benefit != null && benefit.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        benefit,
                        style: const TextStyle(
                          color: _CouponColors.gold,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    if (validity != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        validity.text,
                        style: TextStyle(
                          color: _validityColor(validity.tone),
                          fontSize: validity.tone == CouponValidityTone.urgentRed
                              ? 13
                              : 12,
                          fontWeight:
                              validity.tone == CouponValidityTone.urgentRed ||
                                      validity.tone ==
                                          CouponValidityTone.urgentOrange
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TicketPainter extends CustomPainter {
  final Color color;
  final Color accent;

  const _TicketPainter({required this.color, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    const radius = 14.0;
    const notchR = 7.0;
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(radius),
    );

    final fill = Paint()..color = color;
    canvas.drawRRect(rect, fill);

    final border = Paint()
      ..color = accent.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRRect(rect, border);

    final notchY = size.height * 0.55;
    final notch = Paint()
      ..color = DanjiColors.background
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(-2, notchY), notchR, notch);
    canvas.drawCircle(Offset(size.width + 2, notchY), notchR, notch);

    final dashX = size.width * 0.22;
    final dash = Paint()
      ..color = accent.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    for (var y = 12.0; y < size.height - 12; y += 6) {
      canvas.drawLine(Offset(dashX, y), Offset(dashX, y + 3), dash);
    }
  }

  @override
  bool shouldRepaint(covariant _TicketPainter oldDelegate) => false;
}

class _ErrorBody extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBody({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: DanjiColors.accentRed),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('다시 시도')),
          ],
        ),
      ),
    );
  }
}
