import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_client.dart';
import '../utils/license_ocr_parser.dart';

class LicenseOcrResult {
  final String? licenseNumber;
  final String? licenseExpiry;
  final String rawText;

  const LicenseOcrResult({
    this.licenseNumber,
    this.licenseExpiry,
    this.rawText = '',
  });

  bool get hasAnyField =>
      (licenseNumber?.isNotEmpty ?? false) ||
      (licenseExpiry?.isNotEmpty ?? false);
}

class LicenseService {
  final _picker = ImagePicker();

  /// 카메라 촬영 후 OCR (웹은 null → 수동 입력)
  Future<({XFile? image, LicenseOcrResult? ocr})> captureAndRecognize() async {
    final image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (image == null) return (image: null, ocr: null);

    if (kIsWeb) {
      return (image: image, ocr: null);
    }

    final ocr = await recognizeFromFile(image);
    return (image: image, ocr: ocr);
  }

  Future<LicenseOcrResult?> recognizeFromFile(XFile image) async {
    if (kIsWeb) return null;

    try {
      final input = InputImage.fromFilePath(image.path);
      final recognizer = TextRecognizer(
        script: TextRecognitionScript.korean,
      );
      try {
        final result = await recognizer.processImage(input);
        final parsed = LicenseOcrParser.parse(result.text);
        return LicenseOcrResult(
          licenseNumber: parsed.number,
          licenseExpiry: parsed.expiry,
          rawText: result.text,
        );
      } finally {
        await recognizer.close();
      }
    } catch (e) {
      debugPrint('[license] OCR failed: $e');
      return null;
    }
  }

  /// Storage 업로드 — bucket: license-photos, path: {userId}/{ts}.jpg
  Future<String?> uploadPhoto(XFile image) async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;

    final ext = image.path.split('.').last.toLowerCase();
    final safeExt = ext == 'jpg' || ext == 'jpeg' || ext == 'png' ? ext : 'jpg';
    final path = '${user.id}/${DateTime.now().millisecondsSinceEpoch}.$safeExt';

    try {
      final bytes = kIsWeb ? await image.readAsBytes() : null;
      if (kIsWeb && bytes != null) {
        await supabase.storage.from('license-photos').uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(
                contentType: safeExt == 'png' ? 'image/png' : 'image/jpeg',
                upsert: true,
              ),
            );
      } else {
        await supabase.storage.from('license-photos').upload(
              path,
              File(image.path),
              fileOptions: const FileOptions(upsert: true),
            );
      }
      return path;
    } on StorageException catch (e) {
      debugPrint('[license] upload failed: ${e.message}');
      return null;
    }
  }

  /// RPC submit_license_for_me
  Future<void> submitLicense({
    required String licenseNumber,
    required String licenseExpiry,
    String? photoPath,
  }) async {
    await supabase.rpc('submit_license_for_me', params: {
      'p_license_number': licenseNumber.trim(),
      'p_license_expiry': licenseExpiry.trim(),
      'p_license_photo_url': photoPath,
    });
  }

  Future<bool> isLicenseVerified() async {
    try {
      final result = await supabase.rpc('is_my_license_verified');
      return result == true;
    } catch (_) {
      return false;
    }
  }
}
