import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/coupon.dart';
import '../services/coupon_service.dart';
import '../theme/danji_colors.dart';
import '../theme/danji_typography.dart';
import '../widgets/danji_app_bar.dart';

abstract final class _CouponColors {
  static const ticketBg = Color(0xFF12122A);
  static const gold = Color(0xFFD4AF37);
  static const goldMuted = Color(0x99D4AF37);
  static const ticketText = Color(0xFFF5F0E6);
  static const ticketSub = Color(0xFFB8B0A0);
}

class CouponScreen extends StatefulWidget {
  const CouponScreen({super.key});

  @override
  State<CouponScreen> createState() => _CouponScreenState();
}

class _CouponScreenState extends State<CouponScreen>
    with SingleTickerProviderStateMixin {
  final _service = CouponService();
  final _dateFormat = DateFormat('yyyy.MM.dd');

  late TabController _tabController;
  Future<List<UserCoupon>>? _future;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
              labelStyle: DanjiTypography.body.copyWith(
                fontWeight: FontWeight.w700,
              ),
              tabs: const [
                Tab(text: '사용 가능'),
                Tab(text: '사용 완료'),
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
                final available =
                    all.where((c) => c.isAvailable).toList(growable: false);
                final used = all
                    .where((c) => !c.isAvailable)
                    .toList(growable: false);

                return TabBarView(
                  controller: _tabController,
                  children: [
                    _CouponList(
                      coupons: available,
                      emptyMessage: '사용 가능한 쿠폰이 없습니다.',
                      dateFormat: _dateFormat,
                      onRefresh: () async => _reload(),
                    ),
                    _CouponList(
                      coupons: used,
                      emptyMessage: '사용 완료된 쿠폰이 없습니다.',
                      dateFormat: _dateFormat,
                      onRefresh: () async => _reload(),
                      dimmed: true,
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
  final DateFormat dateFormat;
  final Future<void> Function() onRefresh;
  final bool dimmed;

  const _CouponList({
    required this.coupons,
    required this.emptyMessage,
    required this.dateFormat,
    required this.onRefresh,
    this.dimmed = false,
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

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        itemCount: coupons.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (context, index) {
          return _CouponTicketCard(
            coupon: coupons[index],
            dateFormat: dateFormat,
            dimmed: dimmed,
          );
        },
      ),
    );
  }
}

class _CouponTicketCard extends StatelessWidget {
  final UserCoupon coupon;
  final DateFormat dateFormat;
  final bool dimmed;

  const _CouponTicketCard({
    required this.coupon,
    required this.dateFormat,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    final benefit = coupon.displayBenefit;
    final expires = coupon.expiresAt;
    final used = coupon.usedAt;

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
                    const SizedBox(height: 8),
                    if (used != null)
                      Text(
                        '사용일 ${dateFormat.format(used)}',
                        style: const TextStyle(
                          color: _CouponColors.ticketSub,
                          fontSize: 12,
                        ),
                      )
                    else if (expires != null)
                      Text(
                        coupon.isExpired
                            ? '만료 ${dateFormat.format(expires)}'
                            : '~ ${dateFormat.format(expires)} 까지',
                        style: TextStyle(
                          color: coupon.isExpired
                              ? _CouponColors.ticketSub
                              : _CouponColors.goldMuted,
                          fontSize: 12,
                        ),
                      ),
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
