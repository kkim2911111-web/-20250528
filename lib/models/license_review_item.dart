class LicenseReviewItem {
  final String userId;
  final String? fullName;
  final String? phone;
  final String? licenseNumber;
  final String? licenseExpiry;
  final String? licensePhotoUrl;
  final bool licenseVerified;
  final DateTime? licenseSubmittedAt;
  final String? licenseRejectionReason;
  final String? building;
  final String? unit;

  const LicenseReviewItem({
    required this.userId,
    this.fullName,
    this.phone,
    this.licenseNumber,
    this.licenseExpiry,
    this.licensePhotoUrl,
    this.licenseVerified = false,
    this.licenseSubmittedAt,
    this.licenseRejectionReason,
    this.building,
    this.unit,
  });

  factory LicenseReviewItem.fromMap(Map<String, dynamic> map) {
    DateTime? submitted;
    final raw = map['license_submitted_at'];
    if (raw != null) {
      submitted = DateTime.tryParse(raw.toString())?.toLocal();
    }

    return LicenseReviewItem(
      userId: map['user_id']?.toString() ?? '',
      fullName: map['full_name']?.toString(),
      phone: map['phone']?.toString(),
      licenseNumber: map['license_number']?.toString(),
      licenseExpiry: map['license_expiry']?.toString(),
      licensePhotoUrl: map['license_photo_url']?.toString(),
      licenseVerified: map['license_verified'] == true,
      licenseSubmittedAt: submitted,
      licenseRejectionReason: map['license_rejection_reason']?.toString(),
      building: map['building']?.toString(),
      unit: map['unit']?.toString(),
    );
  }

  String get dongHoLabel {
    final parts = <String>[];
    if (building != null && building!.isNotEmpty) parts.add('${building!}동');
    if (unit != null && unit!.isNotEmpty) parts.add('${unit!}호');
    return parts.isEmpty ? '-' : parts.join(' ');
  }

  bool get isPendingReview =>
      !licenseVerified &&
      licenseNumber != null &&
      licenseNumber!.trim().isNotEmpty;
}
