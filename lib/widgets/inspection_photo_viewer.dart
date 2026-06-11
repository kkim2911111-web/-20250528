import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/inspection_photo.dart';
import '../services/inspection_photo_gallery_service.dart';
import '../theme/danji_colors.dart';
import '../utils/danji_snackbar.dart';

final _viewerDateTime = DateFormat('yyyy.MM.dd HH:mm');

/// URL 목록 → 검수 사진 뷰어 (썸네일 탭 통일 진입점)
Future<void> openInspectionPhotoViewer(
  BuildContext context, {
  required List<InspectionPhotoEntry> photos,
  required int initialIndex,
}) {
  if (photos.isEmpty) return Future.value();
  final index = initialIndex.clamp(0, photos.length - 1);
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (_, __, ___) => InspectionPhotoViewerScreen(
        photos: photos,
        initialIndex: index,
      ),
      transitionsBuilder: (_, animation, __, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    ),
  );
}

Future<void> openInspectionPhotoViewerFromUrls(
  BuildContext context, {
  required List<String> urls,
  required int initialIndex,
  DateTime? capturedAt,
}) {
  return openInspectionPhotoViewer(
    context,
    photos: InspectionPhotoEntry.fromUrls(urls, capturedAt: capturedAt),
    initialIndex: initialIndex,
  );
}

class InspectionPhotoViewerScreen extends StatefulWidget {
  final List<InspectionPhotoEntry> photos;
  final int initialIndex;

  const InspectionPhotoViewerScreen({
    super.key,
    required this.photos,
    required this.initialIndex,
  });

  @override
  State<InspectionPhotoViewerScreen> createState() =>
      _InspectionPhotoViewerScreenState();
}

class _InspectionPhotoViewerScreenState extends State<InspectionPhotoViewerScreen> {
  late final PageController _pageController =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  bool _saving = false;
  double _dragOffset = 0;
  bool _photoZoomed = false;

  InspectionPhotoEntry get _current => widget.photos[_index];

  String get _capturedAtLabel {
    final at = _current.capturedAt;
    if (at == null) return '촬영일시 미확인';
    return _viewerDateTime.format(at.toLocal());
  }

  Future<void> _saveCurrentPhoto() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await InspectionPhotoGalleryService.saveNetworkImageToGallery(
        _current.url,
      );
      if (mounted) {
        DanjiSnackBar.show(context, '사진이 갤러리에 저장되었습니다.');
      }
    } on InspectionPhotoGalleryException catch (e) {
      if (mounted) DanjiSnackBar.show(context, e.message);
    } catch (e) {
      if (mounted) {
        DanjiSnackBar.show(context, '사진 저장에 실패했습니다. ($e)');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _close() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.96),
      child: SafeArea(
        child: Transform.translate(
          offset: Offset(0, _dragOffset),
          child: Column(
            children: [
              GestureDetector(
                onVerticalDragUpdate: (details) {
                  if (_photoZoomed) return;
                  if (details.delta.dy > 0 || _dragOffset > 0) {
                    setState(() => _dragOffset += details.delta.dy);
                  }
                },
                onVerticalDragEnd: (details) {
                  if (_photoZoomed) return;
                  if (_dragOffset > 96 || (details.primaryVelocity ?? 0) > 700) {
                    _close();
                    return;
                  }
                  setState(() => _dragOffset = 0);
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: _close,
                        icon: const Icon(Icons.close, color: Colors.white),
                        tooltip: '닫기',
                      ),
                      Expanded(
                        child: Text(
                          _capturedAtLabel,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _saving ? null : _saveCurrentPhoto,
                        icon: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.download_outlined,
                                color: Colors.white),
                        tooltip: '갤러리에 저장',
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  physics: _photoZoomed
                      ? const NeverScrollableScrollPhysics()
                      : const PageScrollPhysics(),
                  itemCount: widget.photos.length,
                  onPageChanged: (i) => setState(() {
                    _index = i;
                    _photoZoomed = false;
                  }),
                  itemBuilder: (_, i) {
                    return _ZoomablePhotoPage(
                      url: widget.photos[i].url,
                      onZoomChanged: i == _index
                          ? (zoomed) {
                              if (_photoZoomed != zoomed) {
                                setState(() => _photoZoomed = zoomed);
                              }
                            }
                          : null,
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Text(
                  '${_index + 1} / ${widget.photos.length}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZoomablePhotoPage extends StatefulWidget {
  final String url;
  final ValueChanged<bool>? onZoomChanged;

  const _ZoomablePhotoPage({
    required this.url,
    this.onZoomChanged,
  });

  @override
  State<_ZoomablePhotoPage> createState() => _ZoomablePhotoPageState();
}

class _ZoomablePhotoPageState extends State<_ZoomablePhotoPage>
    with SingleTickerProviderStateMixin {
  final TransformationController _controller = TransformationController();
  TapDownDetails? _doubleTapDetails;
  static const _zoomedScale = 3.0;
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleTransformChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTransformChanged);
    _controller.dispose();
    super.dispose();
  }

  void _handleTransformChanged() {
    final zoomed = _controller.value.getMaxScaleOnAxis() > 1.02;
    if (zoomed == _isZoomed) return;
    _isZoomed = zoomed;
    widget.onZoomChanged?.call(zoomed);
  }

  void _handleDoubleTap() {
    final position = _doubleTapDetails?.localPosition;
    if (position == null) return;

    final current = _controller.value.getMaxScaleOnAxis();
    if (current > 1.05) {
      _controller.value = Matrix4.identity();
      return;
    }

    final x = -position.dx * (_zoomedScale - 1);
    final y = -position.dy * (_zoomedScale - 1);
    final matrix = Matrix4.identity()
      ..translateByDouble(x, y, 0, 1)
      ..scaleByDouble(_zoomedScale, _zoomedScale, 1, 1);
    _controller.value = matrix;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (details) => _doubleTapDetails = details,
      onDoubleTap: _handleDoubleTap,
      behavior: HitTestBehavior.deferToChild,
      child: InteractiveViewer(
        transformationController: _controller,
        minScale: 1,
        maxScale: 5,
        panEnabled: true,
        scaleEnabled: true,
        clipBehavior: Clip.none,
        boundaryMargin: const EdgeInsets.all(48),
        child: SizedBox.expand(
          child: Image.network(
            widget.url,
            fit: BoxFit.contain,
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            },
            errorBuilder: (_, __, ___) => const Center(
              child: Text(
                '사진을 불러올 수 없습니다.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 검수 사진 썸네일 — 탭 시 전체화면 뷰어
class InspectionPhotoThumb extends StatelessWidget {
  final InspectionPhotoEntry entry;
  final List<InspectionPhotoEntry> gallery;
  final int galleryIndex;
  final double? width;
  final bool expand;

  const InspectionPhotoThumb({
    super.key,
    required this.entry,
    required this.gallery,
    required this.galleryIndex,
    this.width,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: ColoredBox(
        color: DanjiColors.skyLight,
        child: Image.network(
          entry.url,
          width: expand ? double.infinity : width,
          height: expand ? double.infinity : 96,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const _EmptyPhotoBox(),
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return const _EmptyPhotoBox(showProgress: true);
          },
        ),
      ),
    );

    final child = expand
        ? SizedBox.expand(child: image)
        : SizedBox(width: width, height: 96, child: image);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => openInspectionPhotoViewer(
          context,
          photos: gallery,
          initialIndex: galleryIndex,
        ),
        child: child,
      ),
    );
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
