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

/// ride_photos 행 → URL별 촬영 시각 맵
Map<String, DateTime> ridePhotoTimestampsByUrl(
  Iterable<({String url, DateTime? createdAt})> records,
) {
  final map = <String, DateTime>{};
  for (final record in records) {
    final url = record.url.trim();
    if (!isDisplayableInspectionPhotoUrl(url)) continue;
    final at = record.createdAt;
    if (at == null) continue;
    map.putIfAbsent(url, () => at);
  }
  return map;
}

/// 사진별 시각 우선, 없으면 단계 폴백(대여시작/반납 등)
List<InspectionPhotoEntry> buildInspectionPhotoEntries(
  List<String> urls, {
  Map<String, DateTime>? timestampsByUrl,
  DateTime? fallbackCapturedAt,
}) {
  return urls.map((url) {
    final trimmed = url.trim();
    return InspectionPhotoEntry(
      url: trimmed,
      capturedAt: timestampsByUrl?[trimmed] ?? fallbackCapturedAt,
    );
  }).toList();
}

InspectionPhotoSet buildInspectionPhotoSet({
  required List<String> beforeUrls,
  required List<String> afterUrls,
  DateTime? rentalStartedAt,
  DateTime? returnedAt,
  DateTime? actualEndAt,
  String? status,
  DateTime? updatedAt,
  Map<String, DateTime>? beforeTimestampsByUrl,
  Map<String, DateTime>? afterTimestampsByUrl,
}) {
  final afterCapturedAt = returnedAt ??
      actualEndAt ??
      resolveReturnCompletedAt(
        status: status,
        returnCompletedAt: null,
        updatedAt: updatedAt,
      );

  return InspectionPhotoSet(
    before: buildInspectionPhotoEntries(
      beforeUrls,
      timestampsByUrl: beforeTimestampsByUrl,
      fallbackCapturedAt: rentalStartedAt,
    ),
    after: buildInspectionPhotoEntries(
      afterUrls,
      timestampsByUrl: afterTimestampsByUrl,
      fallbackCapturedAt: afterCapturedAt,
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
