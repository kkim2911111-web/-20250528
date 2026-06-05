import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/danji_colors.dart';

/// 홈 — 우리동네 맛집 PageView 카드 (한 페이지 3개)
class HomeLocalRestaurantsSection extends StatefulWidget {
  const HomeLocalRestaurantsSection({super.key});

  static const _cardsPerPage = 3;
  static const _imageHeight = 90.0;
  static const _cardHeight = 210.0;
  static const _cardGap = 10.0;
  static const _cardRadius = 12.0;

  static const _restaurants = [
    _LocalRestaurant(
      category: '해물찜맛집',
      name: '유진심',
      backgroundColor: Color(0xFFFAECE7),
      icon: Icons.restaurant,
      tags: ['해물찜', '현지인맛집'],
    ),
    _LocalRestaurant(
      category: '오션뷰 레스토랑',
      name: '마레테이블',
      backgroundColor: Color(0xFFE6F1FB),
      icon: Icons.wine_bar,
      tags: ['오션뷰', '데이트'],
    ),
    _LocalRestaurant(
      category: '30년전통 굴밥',
      name: '은행나무집',
      backgroundColor: Color(0xFFEAF3DE),
      icon: Icons.rice_bowl,
      tags: ['굴밥', '30년전통'],
    ),
    _LocalRestaurant(
      category: '운서역 감성카페',
      name: '북해도스위트',
      backgroundColor: Color(0xFFEEEDFE),
      icon: Icons.local_cafe,
      tags: ['카페', '감성'],
    ),
  ];

  @override
  State<HomeLocalRestaurantsSection> createState() =>
      _HomeLocalRestaurantsSectionState();
}

class _HomeLocalRestaurantsSectionState
    extends State<HomeLocalRestaurantsSection> {
  late final PageController _pageController;
  int _currentPage = 0;

  int get _pageCount =>
      (HomeLocalRestaurantsSection._restaurants.length /
              HomeLocalRestaurantsSection._cardsPerPage)
          .ceil();

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<_LocalRestaurant> _restaurantsOnPage(int page) {
    final start = page * HomeLocalRestaurantsSection._cardsPerPage;
    final end = math.min(
      start + HomeLocalRestaurantsSection._cardsPerPage,
      HomeLocalRestaurantsSection._restaurants.length,
    );
    return HomeLocalRestaurantsSection._restaurants.sublist(start, end);
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
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = (constraints.maxWidth -
                    HomeLocalRestaurantsSection._cardGap * 2) /
                HomeLocalRestaurantsSection._cardsPerPage;

            return Column(
              children: [
                SizedBox(
                  height: HomeLocalRestaurantsSection._cardHeight,
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _pageCount,
                    onPageChanged: (index) =>
                        setState(() => _currentPage = index),
                    itemBuilder: (context, page) {
                      return _RestaurantPageRow(
                        restaurants: _restaurantsOnPage(page),
                        cardWidth: cardWidth,
                      );
                    },
                  ),
                ),
                if (_pageCount > 1) ...[
                  const SizedBox(height: 12),
                  _PageDots(count: _pageCount, index: _currentPage),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _RestaurantPageRow extends StatelessWidget {
  final List<_LocalRestaurant> restaurants;
  final double cardWidth;

  const _RestaurantPageRow({
    required this.restaurants,
    required this.cardWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < HomeLocalRestaurantsSection._cardsPerPage; i++) ...[
          if (i > 0) const SizedBox(width: HomeLocalRestaurantsSection._cardGap),
          SizedBox(
            width: cardWidth,
            child: i < restaurants.length
                ? _RestaurantCard(
                    restaurant: restaurants[i],
                    width: cardWidth,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ],
    );
  }
}

class _PageDots extends StatelessWidget {
  final int count;
  final int index;

  const _PageDots({
    required this.count,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 8 : 6,
          height: active ? 8 : 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? DanjiColors.brandBlue
                : DanjiColors.brandBlue.withValues(alpha: 0.25),
          ),
        );
      }),
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

class _LocalRestaurant {
  final String category;
  final String name;
  final Color backgroundColor;
  final IconData icon;
  final List<String> tags;

  const _LocalRestaurant({
    required this.category,
    required this.name,
    required this.backgroundColor,
    required this.icon,
    required this.tags,
  });

  String get displayName => '$category · $name';
}

class _RestaurantCard extends StatelessWidget {
  final _LocalRestaurant restaurant;
  final double width;

  const _RestaurantCard({
    required this.restaurant,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: HomeLocalRestaurantsSection._cardHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: DanjiColors.surface,
          borderRadius: BorderRadius.circular(
            HomeLocalRestaurantsSection._cardRadius,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(HomeLocalRestaurantsSection._cardRadius),
              ),
              child: SizedBox(
                height: HomeLocalRestaurantsSection._imageHeight,
                child: ColoredBox(
                  color: restaurant.backgroundColor,
                  child: Center(
                    child: Icon(
                      restaurant.icon,
                      size: 36,
                      color: DanjiColors.textPrimary.withValues(alpha: 0.35),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      restaurant.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: DanjiColors.textPrimary,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        for (var i = 0; i < restaurant.tags.length; i++) ...[
                          if (i > 0) const SizedBox(width: 4),
                          Flexible(
                            child: _TagBadge(label: restaurant.tags[i]),
                          ),
                        ],
                      ],
                    ),
                    const Spacer(),
                    const Text(
                      '★★★★★',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFFFFB800),
                        height: 1.2,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagBadge extends StatelessWidget {
  final String label;

  const _TagBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: DanjiColors.skyLight,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: DanjiColors.border.withValues(alpha: 0.7)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: DanjiColors.textSecondary,
          height: 1.1,
        ),
      ),
    );
  }
}
