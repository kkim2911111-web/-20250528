import 'package:flutter/material.dart';

import '../models/inspection_photo.dart';
import 'return_inspection_photo_compare.dart';

/// 검수 사진 비교 패널 — 단지/최고관리자 공통
class InspectionPhotoComparePanel extends StatelessWidget {
  final Future<InspectionPhotoSet> future;

  const InspectionPhotoComparePanel({super.key, required this.future});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<InspectionPhotoSet>(
      future: future,
      builder: (context, snap) {
        final photos = snap.data ?? InspectionPhotoSet.empty;
        if (!photos.hasAny && snap.connectionState == ConnectionState.waiting) {
          return const ReturnInspectionPhotoCompare(
            beforePhotos: [],
            afterPhotos: [],
          );
        }
        if (!photos.hasAny) {
          return const SizedBox.shrink();
        }
        return ReturnInspectionPhotoCompare(
          beforePhotos: photos.before,
          afterPhotos: photos.after,
        );
      },
    );
  }
}
