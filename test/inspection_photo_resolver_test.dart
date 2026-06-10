import 'package:flutter_test/flutter_test.dart';

import 'package:danjicar_app/utils/inspection_photo_resolver.dart';

void main() {
  group('buildInspectionPhotoEntries', () {
    test('사진별 시각이 단계 폴백보다 우선', () {
      final fallback = DateTime(2026, 5, 1, 10);
      final perPhoto = DateTime(2026, 5, 1, 10, 5);

      final entries = buildInspectionPhotoEntries(
        ['https://cdn.example.com/a.jpg'],
        timestampsByUrl: {'https://cdn.example.com/a.jpg': perPhoto},
        fallbackCapturedAt: fallback,
      );

      expect(entries.single.capturedAt, perPhoto);
    });

    test('ride_photos 시각 없으면 폴백 사용', () {
      final fallback = DateTime(2026, 5, 2, 15);

      final entries = buildInspectionPhotoEntries(
        ['https://cdn.example.com/b.jpg'],
        fallbackCapturedAt: fallback,
      );

      expect(entries.single.capturedAt, fallback);
    });

    test('일부만 시각 있으면 나머지는 폴백', () {
      final fallback = DateTime(2026, 5, 3, 9);
      final perPhoto = DateTime(2026, 5, 3, 9, 30);

      final entries = buildInspectionPhotoEntries(
        [
          'https://cdn.example.com/1.jpg',
          'https://cdn.example.com/2.jpg',
        ],
        timestampsByUrl: {'https://cdn.example.com/1.jpg': perPhoto},
        fallbackCapturedAt: fallback,
      );

      expect(entries[0].capturedAt, perPhoto);
      expect(entries[1].capturedAt, fallback);
    });
  });

  group('buildInspectionPhotoSet', () {
    test('before/after 각각 사진별 시각 적용', () {
      final rentalStarted = DateTime(2026, 6, 1, 8);
      final returned = DateTime(2026, 6, 1, 20);
      final beforeShot = DateTime(2026, 6, 1, 8, 1);
      final afterShot = DateTime(2026, 6, 1, 20, 2);

      final set = buildInspectionPhotoSet(
        beforeUrls: ['https://cdn.example.com/pickup.jpg'],
        afterUrls: ['https://cdn.example.com/return.jpg'],
        rentalStartedAt: rentalStarted,
        returnedAt: returned,
        beforeTimestampsByUrl: {
          'https://cdn.example.com/pickup.jpg': beforeShot,
        },
        afterTimestampsByUrl: {
          'https://cdn.example.com/return.jpg': afterShot,
        },
      );

      expect(set.before.single.capturedAt, beforeShot);
      expect(set.after.single.capturedAt, afterShot);
    });

    test('기존 사진(ride_photos 없음)은 대여시작/반납 시각 폴백', () {
      final rentalStarted = DateTime(2026, 6, 2, 8);
      final returned = DateTime(2026, 6, 2, 18);

      final set = buildInspectionPhotoSet(
        beforeUrls: ['https://cdn.example.com/old-pickup.jpg'],
        afterUrls: ['https://cdn.example.com/old-return.jpg'],
        rentalStartedAt: rentalStarted,
        returnedAt: returned,
      );

      expect(set.before.single.capturedAt, rentalStarted);
      expect(set.after.single.capturedAt, returned);
    });
  });

  group('ridePhotoTimestampsByUrl', () {
    test('URL 정규화 후 맵 생성', () {
      final at = DateTime(2026, 7, 1, 12);

      final map = ridePhotoTimestampsByUrl([
        (url: ' https://cdn.example.com/x.jpg ', createdAt: at),
      ]);

      expect(map['https://cdn.example.com/x.jpg'], at);
    });
  });
}
