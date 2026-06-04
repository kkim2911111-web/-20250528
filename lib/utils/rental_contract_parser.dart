/// `contract_content` 텍스트 → 섹션별 구조화 (generate_rental_contract 형식)
class RentalContractParsed {
  final String companyName;
  final String reservationId;
  final String? vehicleName;
  final String? rentalPeriod;
  final String? renterName;
  final String? renterPhone;
  final String? licenseNumber;
  final String? secondDriverName;
  final String? secondDriverLicense;
  final String? originalPrice;
  final String? paidPrice;
  final List<String> extraFeeLines;
  final String? insuranceIntro;
  final Map<String, String> insuranceCoverage;
  final List<String> insuranceNotes;
  final List<String> complianceItems;
  final String? generatedAt;

  const RentalContractParsed({
    this.companyName = 'GT컴퍼니',
    this.reservationId = '',
    this.vehicleName,
    this.rentalPeriod,
    this.renterName,
    this.renterPhone,
    this.licenseNumber,
    this.secondDriverName,
    this.secondDriverLicense,
    this.originalPrice,
    this.paidPrice,
    this.extraFeeLines = const [],
    this.insuranceIntro,
    this.insuranceCoverage = const {},
    this.insuranceNotes = const [],
    this.complianceItems = const [],
    this.generatedAt,
  });

  String get headerBrand => '$companyName · 단지카';

  bool get hasStructuredLayout =>
      reservationId.isNotEmpty ||
      vehicleName != null ||
      renterName != null;

  static RentalContractParsed parse(String raw) {
    final lines = raw
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    var section = '';
    String companyName = 'GT컴퍼니';
    var reservationId = '';
    String? vehicleName;
    String? rentalPeriod;
    String? renterName;
    String? renterPhone;
    String? licenseNumber;
    String? secondDriverName;
    String? secondDriverLicense;
    String? originalPrice;
    String? paidPrice;
    final extraFeeLines = <String>[];
    String? insuranceIntro;
    final insuranceCoverage = <String, String>{};
    final insuranceNotes = <String>[];
    final complianceItems = <String>[];
    String? generatedAt;
    var companyLineUsed = false;

    for (final line in lines) {
      if (line.startsWith('■ ')) {
        section = line;
        continue;
      }

      if (line.startsWith('계약서 생성일시:')) {
        generatedAt = _valueAfterColon(line) ?? line.replaceFirst('계약서 생성일시:', '').trim();
        continue;
      }

      final key = _keyBeforeColon(line);
      final value = _valueAfterColon(line);

      switch (section) {
        case '■ 예약 정보':
          switch (key) {
            case '예약번호':
              reservationId = value ?? '';
            case '차량':
              vehicleName = value;
            case '대여기간':
              rentalPeriod = value;
          }
        case '■ 임차인':
          switch (key) {
            case '성명':
              renterName = value;
            case '연락처':
              renterPhone = value;
            case '면허번호':
              licenseNumber = value;
          }
        case '■ 제2운전자':
          switch (key) {
            case '성명':
              secondDriverName = value;
            case '면허번호':
              secondDriverLicense = value;
          }
        case '■ 요금':
          switch (key) {
            case '예약 금액(정가)':
              originalPrice = value;
            case '결제 금액':
              paidPrice = value;
            default:
              if (key != null && value != null) {
                extraFeeLines.add('$key: $value');
              }
          }
        case '■ 보험 및 면책':
          if (key == '대인' || key == '대물' || key == '자손' || key == '자차') {
            if (value != null) insuranceCoverage[key!] = value;
          } else if (key == null) {
            if (insuranceIntro == null &&
                line.contains('자동차종합보험')) {
              insuranceIntro = line;
            } else if (line.startsWith('수리비')) {
              insuranceNotes.add(line);
            }
          }
        case '■ 준수사항':
          if (key == null) complianceItems.add(line);
        case '■ 회사':
          if (!companyLineUsed && key == null) {
            companyName = line;
            companyLineUsed = true;
          }
      }

      if (section == '■ 요금' && key == null) {
        extraFeeLines.add(line);
      }
    }

    if (reservationId.isEmpty) {
      for (final line in lines) {
        final m = RegExp(r'^예약번호:\s*(.+)$').firstMatch(line);
        if (m != null) {
          reservationId = m.group(1)!.trim();
          break;
        }
      }
    }

    return RentalContractParsed(
      companyName: companyName,
      reservationId: reservationId,
      vehicleName: vehicleName,
      rentalPeriod: rentalPeriod,
      renterName: renterName,
      renterPhone: renterPhone,
      licenseNumber: licenseNumber,
      secondDriverName: secondDriverName,
      secondDriverLicense: secondDriverLicense,
      originalPrice: originalPrice,
      paidPrice: paidPrice,
      extraFeeLines: extraFeeLines,
      insuranceIntro: insuranceIntro,
      insuranceCoverage: insuranceCoverage,
      insuranceNotes: insuranceNotes,
      complianceItems: complianceItems,
      generatedAt: generatedAt,
    );
  }

  static String? _keyBeforeColon(String line) {
    final i = line.indexOf(':');
    if (i <= 0) return null;
    return line.substring(0, i).trim();
  }

  static String? _valueAfterColon(String line) {
    final i = line.indexOf(':');
    if (i < 0) return null;
    final v = line.substring(i + 1).trim();
    return v.isEmpty ? null : v;
  }
}
