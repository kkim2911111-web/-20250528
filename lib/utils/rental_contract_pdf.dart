import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// contract_content → PDF 생성·저장
class RentalContractPdf {
  RentalContractPdf._();

  static String downloadFilename(String reservationId) {
    final safe = reservationId
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return '단지카_계약서_$safe.pdf';
  }

  static Future<pw.Document> buildDocument({
    required String contractText,
    required String reservationId,
    String? vehicleName,
  }) async {
    final font = await PdfGoogleFonts.notoSansKRRegular();
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        theme: pw.ThemeData.withFont(base: font),
        build: (context) => [
          pw.Text(
            '단지카 대여 계약서',
            style: pw.TextStyle(
              font: font,
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          if (vehicleName != null && vehicleName.trim().isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text(
              '차량: ${vehicleName.trim()}',
              style: pw.TextStyle(font: font, fontSize: 11),
            ),
          ],
          pw.SizedBox(height: 8),
          pw.Text(
            '예약번호: $reservationId',
            style: pw.TextStyle(font: font, fontSize: 10),
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            contractText,
            style: pw.TextStyle(font: font, fontSize: 10),
          ),
        ],
      ),
    );
    return doc;
  }

  /// Android: Downloads 폴더 저장. 그 외: 공유 시트.
  /// Android 저장 성공 시 파일 경로, 공유 시트만 열린 경우 null.
  static Future<String?> saveContractPdf({
    required String contractText,
    required String reservationId,
    String? vehicleName,
  }) async {
    final doc = await buildDocument(
      contractText: contractText,
      reservationId: reservationId,
      vehicleName: vehicleName,
    );
    final bytes = await doc.save();
    final filename = downloadFilename(reservationId);

    if (!kIsWeb && Platform.isAndroid) {
      final dir = await getDownloadsDirectory();
      if (dir == null) {
        throw Exception('다운로드 폴더를 찾을 수 없습니다.');
      }
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    }

    await Printing.sharePdf(bytes: bytes, filename: filename);
    return null;
  }
}
