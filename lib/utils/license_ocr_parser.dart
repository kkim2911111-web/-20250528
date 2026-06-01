/// ML Kit OCR 텍스트에서 면허번호·만료일 추출
class LicenseOcrParser {
  static final _licensePattern = RegExp(
    r'(\d{2}-\d{2}-\d{6}-\d{2})|(\d{2}\s*\d{2}\s*\d{6}\s*\d{2})|(\d{10,12})',
  );

  static final _expiryPattern = RegExp(
    r'(\d{4})\s*[.\-/년]\s*(\d{1,2})\s*[.\-/월]\s*(\d{1,2})',
  );

  static final _expiryCompact = RegExp(r'(\d{4})(\d{2})(\d{2})');

  static ({String? number, String? expiry}) parse(String raw) {
    final text = raw.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ');

    String? number;
    final licenseMatch = _licensePattern.firstMatch(text);
    if (licenseMatch != null) {
      number = licenseMatch.group(0)?.replaceAll(RegExp(r'\s+'), '');
      if (number != null && number.length >= 10 && !number.contains('-')) {
        // 12자리 → 11-XX-XXXXXX-XX 형식 시도
        if (number.length == 12) {
          number =
              '${number.substring(0, 2)}-${number.substring(2, 4)}-${number.substring(4, 10)}-${number.substring(10)}';
        }
      }
    }

    String? expiry;
    final expiryMatch = _expiryPattern.firstMatch(text);
    if (expiryMatch != null) {
      final y = expiryMatch.group(1)!;
      final m = expiryMatch.group(2)!.padLeft(2, '0');
      final d = expiryMatch.group(3)!.padLeft(2, '0');
      expiry = '$y-$m-$d';
    } else {
      final compact = _expiryCompact.firstMatch(text);
      if (compact != null) {
        final y = int.tryParse(compact.group(1)!);
        if (y != null && y >= 2020 && y <= 2099) {
          expiry =
              '${compact.group(1)}-${compact.group(2)!}-${compact.group(3)!}';
        }
      }
    }

    return (number: number, expiry: expiry);
  }
}
