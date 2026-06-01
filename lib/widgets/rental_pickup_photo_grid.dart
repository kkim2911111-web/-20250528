import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/danji_typography.dart';
import '../services/rental_start_service.dart';
import '../theme/danji_colors.dart';

/// 대여하기 STEP 1 — 일괄 선택 + 순서대로 표시 (앞 6장 라벨)
class RentalPickupPhotoGrid extends StatelessWidget {
  static const slotLabels = RentalStartService.pickupSlotLabels;

  final List<Uint8List> photos;
  final bool locked;
  final bool uploading;
  final int uploadProgress;
  final int uploadTotal;
  final VoidCallback? onBulkGallery;
  final VoidCallback? onCamera;
  final VoidCallback? onRetryUpload;
  final ValueChanged<int>? onRemove;

  const RentalPickupPhotoGrid({
    super.key,
    required this.photos,
    this.locked = false,
    this.uploading = false,
    this.uploadProgress = 0,
    this.uploadTotal = 6,
    this.onBulkGallery,
    this.onCamera,
    this.onRetryUpload,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '차량 사진',
              style: DanjiTypography.subtitle,
            ),
            const Spacer(),
            Text(
              '${photos.length}/${RentalStartService.maxPhotos}',
              style: DanjiTypography.secondaryMedium.copyWith(
                color: photos.length >= RentalStartService.minPhotos
                    ? DanjiColors.rentalBlue
                    : DanjiColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '앞·뒤·좌·우·실내·계기판 순으로 최소 6장, 최대 10장 등록해 주세요.',
          style: DanjiTypography.secondary.copyWith(height: 1.45),
        ),
        const SizedBox(height: 6),
        Text(
          '갤러리에서 한꺼번에 선택하면 순서대로 채워집니다.',
          style: DanjiTypography.caption,
        ),
        if (!locked) ...[
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: uploading ? null : onBulkGallery,
            icon: uploading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.photo_library_outlined),
            label: Text(
              uploading
                  ? '업로드 중 $uploadProgress/$uploadTotal'
                  : '갤러리에서 일괄 선택 (최대 10장)',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: DanjiColors.buttonBlue,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: uploading ? null : onCamera,
            icon: const Icon(Icons.photo_camera_outlined, size: 20),
            label: const Text('카메라로 1장 추가'),
            style: OutlinedButton.styleFrom(
              foregroundColor: DanjiColors.buttonBlue,
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
        if (photos.isNotEmpty) ...[
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: photos.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1,
            ),
            itemBuilder: (context, index) {
              final label = index < slotLabels.length ? slotLabels[index] : null;
              return _PhotoTile(
                bytes: photos[index],
                label: label,
                index: index,
                locked: locked,
                onRemove: locked ? null : () => onRemove?.call(index),
              );
            },
          ),
        ],
        if (!locked &&
            !uploading &&
            photos.length >= RentalStartService.minPhotos &&
            onRetryUpload != null) ...[
          const SizedBox(height: 10),
          TextButton(
            onPressed: onRetryUpload,
            child: const Text('업로드 다시 시도'),
          ),
        ],
      ],
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final Uint8List bytes;
  final String? label;
  final int index;
  final bool locked;
  final VoidCallback? onRemove;

  const _PhotoTile({
    required this.bytes,
    required this.label,
    required this.index,
    required this.locked,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(bytes, fit: BoxFit.cover),
        ),
        if (label != null)
          Positioned(
            left: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                label!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        if (!locked && onRemove != null)
          Positioned(
            top: 2,
            right: 2,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onRemove,
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(Icons.close, color: Colors.white, size: 14),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
