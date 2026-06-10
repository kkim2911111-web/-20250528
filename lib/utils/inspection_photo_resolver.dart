import '../models/inspection_photo.dart';
import '../models/staff_profile.dart';
import '../utils/reservation_display.dart';

bool isDisplayableInspectionPhotoUrl(String? url) {
  if (url == null) return false;
  final trimmed = url.trim();
  return trimmed.startsWith('http://') || trimmed.startsWith('https://');
}

List<String> normalizeInspectionPhotoUrls(Iterable<String> urls) {
  return urls
      .map((url) => url.trim())
      .where(isDisplayableInspectionPhotoUrl)
      .toList();
}

InspectionPhotoSet buildInspectionPhotoSet({
  required List<String> beforeUrls,
  required List<String> afterUrls,
  DateTime? rentalStartedAt,
  DateTime? returnedAt,
  DateTime? actualEndAt,
  String? status,
  DateTime? updatedAt,
}) {
  final afterCapturedAt = returnedAt ??
      actualEndAt ??
      resolveReturnCompletedAt(
        status: status,
        returnCompletedAt: null,
        updatedAt: updatedAt,
      );

  return InspectionPhotoSet(
    before: InspectionPhotoEntry.fromUrls(
      beforeUrls,
      capturedAt: rentalStartedAt,
    ),
    after: InspectionPhotoEntry.fromUrls(
      afterUrls,
      capturedAt: afterCapturedAt,
    ),
  );
}

InspectionPhotoSet buildInspectionPhotoSetFromRow(AdminReservationRow row) {
  return buildInspectionPhotoSet(
    beforeUrls: normalizeInspectionPhotoUrls(row.pickupPhotos),
    afterUrls: normalizeInspectionPhotoUrls(row.returnPhotos),
    rentalStartedAt: row.rentalStartedAt,
    returnedAt: row.returnedAt,
    actualEndAt: row.actualEndAt,
    status: row.status,
    updatedAt: row.updatedAt,
  );
}
