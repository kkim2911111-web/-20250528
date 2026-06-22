import 'package:flutter/material.dart';

import '../models/local_spot.dart';
import '../services/local_spot_service.dart';
import '../theme/danji_colors.dart';

/// 홈 — 우리동네 맛집 가로 스크롤 카드 (DB: local_spots)
class HomeLocalRestaurantsSection extends StatefulWidget {
  const HomeLocalRestaurantsSection({super.key});

  static const cardWidth = 148.0;
  static const imageHeight = 96.0;
  static const cardGap = 10.0;
  static const cardRadius = 12.0;

  @override
  State<HomeLocalRestaurantsSection> createState() =>
      _HomeLocalRestaurantsSectionState();
}

class _HomeLocalRestaurantsSectionState
    extends State<HomeLocalRestaurantsSection> {
  final _service = LocalSpotService();
  late Future<List<LocalSpot>> _spotsFuture;

  @override
  void initState() {
    super.initState();
    _spotsFuture = _service.fetchLocalSpots();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '우리동네 맛집',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: DanjiColors.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '단지 주변 인기 맛집을 소개해드려요',
                    style: TextStyle(
                      fontSize: 12,
                      color: DanjiColors.textSecondary.withValues(alpha: 0.9),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const _GuideLink(),
          ],
        ),
        const SizedBox(height: 14),
        FutureBuilder<List<LocalSpot>>(
          future: _spotsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }

            final spots = snapshot.data ?? [];
            if (spots.isEmpty) return const SizedBox.shrink();

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < spots.length; i++) ...[
                    if (i > 0)
                      const SizedBox(
                        width: HomeLocalRestaurantsSection.cardGap,
                      ),
                    _LocalSpotCard(spot: spots[i]),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _GuideLink extends StatelessWidget {
  const _GuideLink();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        '차슐랭 가이드 >',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: DanjiColors.buttonBlue,
          height: 1.3,
        ),
      ),
    );
  }
}

class _LocalSpotCard extends StatelessWidget {
  final LocalSpot spot;

  const _LocalSpotCard({required this.spot});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: HomeLocalRestaurantsSection.cardWidth,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(
            HomeLocalRestaurantsSection.cardRadius,
          ),
          border: Border.all(
            color: DanjiColors.border.withValues(alpha: 0.85),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(
            HomeLocalRestaurantsSection.cardRadius,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: HomeLocalRestaurantsSection.imageHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      spot.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => ColoredBox(
                        color: DanjiColors.skyLight,
                        child: Icon(
                          Icons.restaurant,
                          color: DanjiColors.textSecondary
                              .withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                    if (spot.isFeatured)
                      const Positioned(
                        top: 8,
                        left: 8,
                        child: _FeaturedBadge(),
                      ),
                    const Positioned(
                      top: 8,
                      right: 8,
                      child: _HeartButton(),
                    ),
                  ],
                ),
              ),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          spot.shortName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: DanjiColors.textPrimary,
                            height: 1.2,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          spot.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: DanjiColors.textSecondary
                                .withValues(alpha: 0.9),
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (final tag in spot.displayTags)
                              _TagChip(label: tag),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: -10,
                    left: 10,
                    child: _RatingPill(rating: spot.rating),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeaturedBadge extends StatelessWidget {
  const _FeaturedBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFF4D4F),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Text(
          '이번주 인기',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}

class _HeartButton extends StatelessWidget {
  const _HeartButton();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        shape: BoxShape.circle,
      ),
      child: const Padding(
        padding: EdgeInsets.all(5),
        child: Icon(
          Icons.favorite_border,
          size: 14,
          color: DanjiColors.textPrimary,
        ),
      ),
    );
  }
}

class _RatingPill extends StatelessWidget {
  final double rating;

  const _RatingPill({required this.rating});

  @override
  Widget build(BuildContext context) {
    final text = rating.toStringAsFixed(1);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: DanjiColors.border.withValues(alpha: 0.9),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.star_rounded,
              size: 12,
              color: Color(0xFFFFB800),
            ),
            const SizedBox(width: 2),
            Text(
              text,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: DanjiColors.textPrimary,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;

  const _TagChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: DanjiColors.border.withValues(alpha: 0.9),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: DanjiColors.textSecondary.withValues(alpha: 0.95),
          height: 1.1,
        ),
      ),
    );
  }
}
