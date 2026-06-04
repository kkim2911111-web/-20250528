/// 예약 결제 전 계약·준수사항 동의
class BookingContractConsent {
  final bool termsAgreed;
  final bool addSecondDriver;
  final String? secondDriverName;
  final String? secondDriverLicense;

  const BookingContractConsent({
    required this.termsAgreed,
    this.addSecondDriver = false,
    this.secondDriverName,
    this.secondDriverLicense,
  });

  bool get hasSecondDriverInfo {
    if (!addSecondDriver) return false;
    final name = secondDriverName?.trim();
    final license = secondDriverLicense?.trim();
    return name != null &&
        name.isNotEmpty &&
        license != null &&
        license.isNotEmpty;
  }
}
