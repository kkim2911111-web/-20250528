import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../models/inspection_photo.dart';
import '../services/inspection_photo_gallery_service.dart';
import '../theme/danji_colors.dart';
import '../utils/danji_snackbar.dart';

final _viewerDateTime = DateFormat('yyyy.MM.dd HH:mm');

String _inspectionPhotoHeroTag(String url) => 'inspection_photo_$url';

/// 더블탭: 2.5배 확대 ↔ 원상복귀 토글
PhotoViewScaleState _inspectionDoubleTapScaleCycle(PhotoViewScaleState actual) {
  if (actual == PhotoViewScaleState.initial) {
    return PhotoViewScaleState.covering;
  }
  return PhotoViewScaleState.initial;
}

/// URL 목록 → 검수 사진 뷰어 (썸네일 탭 통일 진입점)
Future<void> openInspectionPhotoViewer(
  BuildContext context, {
  required List<InspectionPhotoEntry> photos,
  required int initialIndex,
}) {
  if (photos.isEmpty) return Future.value();
  final index = initialIndex.clamp(0, photos.length - 1);
  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
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
  static const _doubleTapZoomFactor = 2.5;

  late final PageController _pageController =
      PageController(initialPage: widget.initialIndex);
  late final List<PhotoViewController> _photoControllers;
  late final List<PhotoViewScaleStateController> _scaleStateControllers;
  late int _index = widget.initialIndex;
  bool _saving = false;
  double _dragOffset = 0;
  bool _photoZoomed = false;
  final Map<int, double> _containedBaseScale = {};

  InspectionPhotoEntry get _current => widget.photos[_index];

  String get _capturedAtLabel {
    final at = _current.capturedAt;
    if (at == null) return '촬영일시 미확인';
    return _viewerDateTime.format(at.toLocal());
  }

  @override
  void initState() {
    super.initState();
    final count = widget.photos.length;
    _photoControllers = List.generate(count, (_) => PhotoViewController());
    _scaleStateControllers =
        List.generate(count, (_) => PhotoViewScaleStateController());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _precacheAdjacent(_index);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final c in _photoControllers) {
      c.dispose();
    }
    for (final c in _scaleStateControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _precacheAdjacent(int index) {
    if (!mounted) return;
    for (final i in [index - 1, index, index + 1]) {
      if (i < 0 || i >= widget.photos.length) continue;
      precacheImage(NetworkImage(widget.photos[i].url), context);
    }
  }

  void _onScaleStateChanged(PhotoViewScaleState state, int pageIndex) {
    if (pageIndex != _index) return;

    final controller = _photoControllers[pageIndex];
    final scaleStateController = _scaleStateControllers[pageIndex];
    final prev = scaleStateController.prevScaleState;

    if (state == PhotoViewScaleState.initial) {
      final scale = controller.scale;
      if (scale != null && scale > 0) {
        _containedBaseScale[pageIndex] = scale;
      }
    }

    if (prev == PhotoViewScaleState.initial &&
        state == PhotoViewScaleState.covering) {
      final base = _containedBaseScale[pageIndex] ?? controller.scale;
      if (base != null && base > 0) {
        final target = (base * _doubleTapZoomFactor).clamp(base, base * 5.0);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          controller.scale = target;
          scaleStateController.scaleState = PhotoViewScaleState.zoomedIn;
        });
      }
    }

    final zoomed = state != PhotoViewScaleState.initial &&
        state != PhotoViewScaleState.zoomedOut;
    if (_photoZoomed != zoomed) {
      setState(() => _photoZoomed = zoomed);
    }
  }

  void _onPageChanged(int i) {
    setState(() {
      _index = i;
      _photoZoomed = false;
      _dragOffset = 0;
    });
    _precacheAdjacent(i);
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

  Widget _loadingIndicator(BuildContext context, ImageChunkEvent? event) {
    final total = event?.expectedTotalBytes;
    final loaded = event?.cumulativeBytesLoaded;
    return Center(
      child: SizedBox(
        width: 36,
        height: 36,
        child: CircularProgressIndicator(
          color: Colors.white,
          strokeWidth: 2.5,
          value: total != null && total > 0 ? loaded! / total : null,
        ),
      ),
    );
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
              Padding(
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
                          : const Icon(
                              Icons.download_outlined,
                              color: Colors.white,
                            ),
                      tooltip: '갤러리에 저장',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onVerticalDragUpdate: (details) {
                    if (_photoZoomed) return;
                    if (details.delta.dy > 0 || _dragOffset > 0) {
                      setState(() => _dragOffset += details.delta.dy);
                    }
                  },
                  onVerticalDragEnd: (details) {
                    if (_photoZoomed) return;
                    if (_dragOffset > 96 ||
                        (details.primaryVelocity ?? 0) > 700) {
                      _close();
                      return;
                    }
                    setState(() => _dragOffset = 0);
                  },
                  child: PhotoViewGallery.builder(
                    scrollPhysics: const BouncingScrollPhysics(),
                    pageController: _pageController,
                    itemCount: widget.photos.length,
                    onPageChanged: _onPageChanged,
                    backgroundDecoration: const BoxDecoration(color: Colors.transparent),
                    loadingBuilder: _loadingIndicator,
                    enableRotation: false,
                    gaplessPlayback: true,
                    scaleStateChangedCallback: (state) =>
                        _onScaleStateChanged(state, _index),
                    builder: (context, index) {
                      final url = widget.photos[index].url;
                      return PhotoViewGalleryPageOptions(
                        imageProvider: NetworkImage(url),
                        heroAttributes: PhotoViewHeroAttributes(
                          tag: _inspectionPhotoHeroTag(url),
                          transitionOnUserGestures: true,
                        ),
                        initialScale: PhotoViewComputedScale.contained,
                        minScale: PhotoViewComputedScale.contained,
                        maxScale: PhotoViewComputedScale.contained * 5.0,
                        controller: _photoControllers[index],
                        scaleStateController: _scaleStateControllers[index],
                        scaleStateCycle: _inspectionDoubleTapScaleCycle,
                        filterQuality: FilterQuality.high,
                        onScaleEnd: (context, details, value) {
                          if (index != _index) return;
                          final base = _containedBaseScale[index] ??
                              value.scale ??
                              1.0;
                          final zoomed = (value.scale ?? 1.0) > base * 1.02;
                          if (_photoZoomed != zoomed) {
                            setState(() => _photoZoomed = zoomed);
                          }
                        },
                        errorBuilder: (context, error, stackTrace) =>
                            const Center(
                          child: Text(
                            '사진을 불러올 수 없습니다.',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                      );
                    },
                  ),
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
    final image = Hero(
      tag: _inspectionPhotoHeroTag(entry.url),
      child: ClipRRect(
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
