import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/danji_colors.dart';

/// 운행 시작 — 사진 일괄 등록 (최소 6장, 최대 10장)
class RentalStartPhotoSection extends StatefulWidget {
  static const minPhotos = 6;
  static const maxPhotos = 10;

  final List<Uint8List> photos;
  final ValueChanged<List<Uint8List>> onChanged;

  const RentalStartPhotoSection({
    super.key,
    required this.photos,
    required this.onChanged,
  });

  @override
  State<RentalStartPhotoSection> createState() =>
      _RentalStartPhotoSectionState();
}

class _RentalStartPhotoSectionState extends State<RentalStartPhotoSection> {
  final _picker = ImagePicker();

  int get _remaining =>
      RentalStartPhotoSection.maxPhotos - widget.photos.length;

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _pickFromGallery() async {
    if (_remaining <= 0) {
      _showSnack('사진은 최대 ${RentalStartPhotoSection.maxPhotos}장까지 등록할 수 있습니다.');
      return;
    }

    final picked = await _picker.pickMultiImage(
      imageQuality: 85,
      maxWidth: 1920,
      limit: _remaining,
    );
    if (picked.isEmpty || !mounted) return;

    final bytesList = <Uint8List>[];
    for (final file in picked) {
      bytesList.add(await file.readAsBytes());
    }
    if (!mounted) return;

    widget.onChanged([...widget.photos, ...bytesList]);
  }

  Future<void> _takePhotosContinuously() async {
    if (_remaining <= 0) {
      _showSnack('사진은 최대 ${RentalStartPhotoSection.maxPhotos}장까지 등록할 수 있습니다.');
      return;
    }

    var photos = [...widget.photos];

    while (photos.length < RentalStartPhotoSection.maxPhotos && mounted) {
      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (picked == null || !mounted) break;

      photos = [...photos, await picked.readAsBytes()];
      widget.onChanged(photos);

      if (photos.length >= RentalStartPhotoSection.maxPhotos) break;

      final continueShooting = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: DanjiColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            '사진 추가',
            style: TextStyle(
              color: DanjiColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            '${photos.length}/${RentalStartPhotoSection.maxPhotos}장 등록됨\n'
            '계속 촬영하시겠습니까?',
            style: const TextStyle(
              color: DanjiColors.textSecondary,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('완료'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('계속 촬영'),
            ),
          ],
        ),
      );

      if (continueShooting != true) break;
    }
  }

  void _removePhoto(int index) {
    final next = [...widget.photos]..removeAt(index);
    widget.onChanged(next);
  }

  void _previewPhoto(int index) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: Image.memory(
                widget.photos[index],
                fit: BoxFit.contain,
              ),
            ),
            IconButton(
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '차량 사진',
              style: TextStyle(
                color: DanjiColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const Spacer(),
            Text(
              '${widget.photos.length}/${RentalStartPhotoSection.maxPhotos}',
              style: TextStyle(
                color: widget.photos.length >= RentalStartPhotoSection.minPhotos
                    ? DanjiColors.primaryBlue
                    : DanjiColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          '앞·뒤·좌·우·실내·계기판이 확인되도록 촬영해 주세요 (최소 6장)',
          style: TextStyle(
            color: DanjiColors.textSecondary,
            height: 1.45,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: DanjiColors.skyLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DanjiColors.skySoft),
          ),
          child: const Text(
            '🚗 출발 전 계기판을 꼭 찍어주세요!\n'
            '주행거리와 연료 상태를 함께 확인할 수 있도록\n'
            '계기판 전체가 나오게 촬영해 주시면 됩니다.',
            style: TextStyle(
              color: DanjiColors.textPrimary,
              height: 1.5,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _remaining > 0 ? _pickFromGallery : null,
                icon: const Icon(Icons.photo_library_outlined, size: 20),
                label: const Text('갤러리 선택'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: DanjiColors.primaryBlue,
                  side: const BorderSide(color: DanjiColors.skySoft),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: _remaining > 0 ? _takePhotosContinuously : null,
                icon: const Icon(Icons.photo_camera_outlined, size: 20),
                label: const Text('카메라 촬영'),
                style: FilledButton.styleFrom(
                  backgroundColor: DanjiColors.primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (widget.photos.isNotEmpty) ...[
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.photos.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemBuilder: (context, index) {
              return _PhotoThumbnail(
                bytes: widget.photos[index],
                onTap: () => _previewPhoto(index),
                onRemove: () => _removePhoto(index),
              );
            },
          ),
        ],
      ],
    );
  }
}

class _PhotoThumbnail extends StatelessWidget {
  final Uint8List bytes;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _PhotoThumbnail({
    required this.bytes,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(
              bytes,
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            top: -4,
            right: -4,
            child: Material(
              color: DanjiColors.textPrimary,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onRemove,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, color: Colors.white, size: 16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
