import 'package:flutter/material.dart';

import '../models/inspection_photo.dart';
import '../theme/danji_colors.dart';
import 'inspection_photo_viewer.dart';

enum _CompareLayout { sideBySide, stacked }

/// 반납 검수 — 대여 전/반납 후 사진 비교 (썸네일 탭 → 전체화면 뷰어)
class ReturnInspectionPhotoCompare extends StatefulWidget {
  final List<InspectionPhotoEntry> beforePhotos;
  final List<InspectionPhotoEntry> afterPhotos;

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
    return Material(
      color: DanjiColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
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
                      const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
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
        ),
      ),
    );
  }
}

class _SideBySideCompare extends StatelessWidget {
  final List<InspectionPhotoEntry> beforePhotos;
  final List<InspectionPhotoEntry> afterPhotos;
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
                            entry: index < beforePhotos.length
                                ? beforePhotos[index]
                                : null,
                            gallery: beforePhotos,
                            galleryIndex: index,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _PhotoPanel(
                            title: '반납 후',
                            entry: index < afterPhotos.length
                                ? afterPhotos[index]
                                : null,
                            gallery: afterPhotos,
                            galleryIndex: index,
                          ),
                        ),
                      ],
                    );
                  },
                )
              : Row(
                  children: const [
                    Expanded(child: _PhotoPanel(title: '대여 전', entry: null)),
                    SizedBox(width: 8),
                    Expanded(child: _PhotoPanel(title: '반납 후', entry: null)),
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
  final List<InspectionPhotoEntry> beforePhotos;
  final List<InspectionPhotoEntry> afterPhotos;

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
  final List<InspectionPhotoEntry> photos;

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
                return InspectionPhotoThumb(
                  entry: photos[index],
                  gallery: photos,
                  galleryIndex: index,
                  width: 96,
                );
              },
            ),
          ),
      ],
    );
  }
}

class _PhotoPanel extends StatelessWidget {
  final String title;
  final InspectionPhotoEntry? entry;
  final List<InspectionPhotoEntry> gallery;
  final int galleryIndex;

  const _PhotoPanel({
    required this.title,
    this.entry,
    this.gallery = const [],
    this.galleryIndex = 0,
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
          child: entry == null
              ? const _EmptyPhotoBox()
              : InspectionPhotoThumb(
                  entry: entry!,
                  gallery: gallery.isEmpty ? [entry!] : gallery,
                  galleryIndex: gallery.isEmpty ? 0 : galleryIndex,
                  expand: true,
                ),
        ),
      ],
    );
  }
}

class _EmptyPhotoBox extends StatelessWidget {
  const _EmptyPhotoBox();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DanjiColors.skyLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DanjiColors.border),
      ),
      child: const Center(
        child: Text(
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
