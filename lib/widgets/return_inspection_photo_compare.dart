import 'package:flutter/material.dart';

import '../theme/danji_colors.dart';

enum _CompareLayout { sideBySide, stacked }

/// 반납 검수 — 대여 전/반납 후 사진 비교
class ReturnInspectionPhotoCompare extends StatefulWidget {
  final List<String> beforePhotos;
  final List<String> afterPhotos;

  const ReturnInspectionPhotoCompare({
    super.key,
    required this.beforePhotos,
    required this.afterPhotos,
  });

  @override
  State<ReturnInspectionPhotoCompare> createState() =>
      _ReturnInspectionPhotoCompareState();
}

class _ReturnInspectionPhotoCompareState
    extends State<ReturnInspectionPhotoCompare> {
  _CompareLayout _layout = _CompareLayout.sideBySide;
  late final PageController _pageController;
  int _pageIndex = 0;

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

  int get _pageCount {
    final max = [
      widget.beforePhotos.length,
      widget.afterPhotos.length,
    ].reduce((a, b) => a > b ? a : b);
    return max == 0 ? 1 : max;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text(
              '사진 비교',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: DanjiColors.textPrimary,
              ),
            ),
            const Spacer(),
            SegmentedButton<_CompareLayout>(
              segments: const [
                ButtonSegment(
                  value: _CompareLayout.sideBySide,
                  label: Text('좌우'),
                ),
                ButtonSegment(
                  value: _CompareLayout.stacked,
                  label: Text('상하'),
                ),
              ],
              selected: {_layout},
              onSelectionChanged: (value) {
                setState(() => _layout = value.first);
              },
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                textStyle: WidgetStateProperty.all(
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_layout == _CompareLayout.sideBySide)
          _SideBySideCompare(
            beforePhotos: widget.beforePhotos,
            afterPhotos: widget.afterPhotos,
            pageController: _pageController,
            pageIndex: _pageIndex,
            pageCount: _pageCount,
            onPageChanged: (index) => setState(() => _pageIndex = index),
          )
        else
          _StackedCompare(
            beforePhotos: widget.beforePhotos,
            afterPhotos: widget.afterPhotos,
          ),
      ],
    );
  }
}

class _SideBySideCompare extends StatelessWidget {
  final List<String> beforePhotos;
  final List<String> afterPhotos;
  final PageController pageController;
  final int pageIndex;
  final int pageCount;
  final ValueChanged<int> onPageChanged;

  const _SideBySideCompare({
    required this.beforePhotos,
    required this.afterPhotos,
    required this.pageController,
    required this.pageIndex,
    required this.pageCount,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    final hasAny = beforePhotos.isNotEmpty || afterPhotos.isNotEmpty;

    return Column(
      children: [
        SizedBox(
          height: 160,
          child: hasAny
              ? PageView.builder(
                  controller: pageController,
                  itemCount: pageCount,
                  onPageChanged: onPageChanged,
                  itemBuilder: (context, index) {
                    return Row(
                      children: [
                        Expanded(
                          child: _PhotoPanel(
                            title: '대여 전',
                            url: index < beforePhotos.length
                                ? beforePhotos[index]
                                : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _PhotoPanel(
                            title: '반납 후',
                            url: index < afterPhotos.length
                                ? afterPhotos[index]
                                : null,
                          ),
                        ),
                      ],
                    );
                  },
                )
              : Row(
                  children: const [
                    Expanded(child: _PhotoPanel(title: '대여 전', url: null)),
                    SizedBox(width: 8),
                    Expanded(child: _PhotoPanel(title: '반납 후', url: null)),
                  ],
                ),
        ),
        if (pageCount > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(pageCount, (i) {
              final active = i == pageIndex;
              return Container(
                width: active ? 8 : 6,
                height: active ? 8 : 6,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active
                      ? DanjiColors.buttonBlue
                      : DanjiColors.buttonBlue.withValues(alpha: 0.25),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }
}

class _StackedCompare extends StatelessWidget {
  final List<String> beforePhotos;
  final List<String> afterPhotos;

  const _StackedCompare({
    required this.beforePhotos,
    required this.afterPhotos,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PhotoStripSection(title: '대여 전 사진', photos: beforePhotos),
        const SizedBox(height: 12),
        _PhotoStripSection(title: '반납 후 사진', photos: afterPhotos),
      ],
    );
  }
}

class _PhotoStripSection extends StatelessWidget {
  final String title;
  final List<String> photos;

  const _PhotoStripSection({
    required this.title,
    required this.photos,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: DanjiColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        if (photos.isEmpty)
          const _EmptyPhotoBox()
        else
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                return _NetworkPhotoThumb(url: photos[index], width: 96);
              },
            ),
          ),
      ],
    );
  }
}

class _PhotoPanel extends StatelessWidget {
  final String title;
  final String? url;

  const _PhotoPanel({
    required this.title,
    this.url,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: DanjiColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: url == null
              ? const _EmptyPhotoBox()
              : _NetworkPhotoThumb(url: url!, expand: true),
        ),
      ],
    );
  }
}

class _NetworkPhotoThumb extends StatelessWidget {
  final String url;
  final double? width;
  final bool expand;

  const _NetworkPhotoThumb({
    required this.url,
    this.width,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        url,
        width: expand ? double.infinity : width,
        height: expand ? double.infinity : 96,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const _EmptyPhotoBox(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const _EmptyPhotoBox(showProgress: true);
        },
      ),
    );

    if (expand) {
      return SizedBox.expand(child: image);
    }
    return SizedBox(width: width, height: 96, child: image);
  }
}

class _EmptyPhotoBox extends StatelessWidget {
  final bool showProgress;

  const _EmptyPhotoBox({this.showProgress = false});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DanjiColors.skyLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DanjiColors.border),
      ),
      child: Center(
        child: showProgress
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text(
                '사진 없음',
                style: TextStyle(
                  fontSize: 12,
                  color: DanjiColors.textMuted,
                ),
              ),
      ),
    );
  }
}
