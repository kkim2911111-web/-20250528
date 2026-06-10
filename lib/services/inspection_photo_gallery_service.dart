import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;

class InspectionPhotoGalleryException implements Exception {
  final String message;
  const InspectionPhotoGalleryException(this.message);

  @override
  String toString() => message;
}

class InspectionPhotoGalleryService {
  const InspectionPhotoGalleryService._();

  static Future<void> saveNetworkImageToGallery(String url) async {
    if (kIsWeb) {
      throw const InspectionPhotoGalleryException(
        '웹에서는 갤러리 저장을 지원하지 않습니다.',
      );
    }

    final trimmed = url.trim();
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      throw const InspectionPhotoGalleryException('저장할 수 없는 사진 주소입니다.');
    }

    if (!await Gal.hasAccess()) {
      final granted = await Gal.requestAccess();
      if (!granted) {
        throw const InspectionPhotoGalleryException(
          '사진 저장 권한이 필요합니다. 설정에서 권한을 허용해 주세요.',
        );
      }
    }

    final response = await http.get(Uri.parse(trimmed));
    if (response.statusCode != 200) {
      throw InspectionPhotoGalleryException(
        '사진을 불러오지 못했습니다. (${response.statusCode})',
      );
    }

    await Gal.putImageBytes(
      response.bodyBytes,
      name: 'danjicar_${DateTime.now().millisecondsSinceEpoch}',
    );
  }
}
