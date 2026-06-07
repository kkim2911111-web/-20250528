import 'package:flutter/material.dart';

import '../services/admin_service.dart' show AdminService, friendlyAdminError;
import '../theme/danji_colors.dart';
import '../theme/danji_theme.dart';
import '../utils/rental_contract_parser.dart';
import '../utils/rental_contract_pdf.dart';
import 'rental_contract_cards.dart';

/// 관리자 카드 — 제2운전자 배지
class AdminSecondDriverBadge extends StatelessWidget {
  const AdminSecondDriverBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: DanjiColors.skyLight,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: DanjiColors.buttonBlue.withValues(alpha: 0.45),
          ),
        ),
        child: const Text(
          '2운전자',
          style: TextStyle(
            color: DanjiColors.buttonBlue,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

bool adminHasSecondDriver({String? secondDriverName}) {
  final name = secondDriverName?.trim();
  return name != null && name.isNotEmpty;
}

void showAdminSecondDriverInfoSheet(
  BuildContext context, {
  required String? secondDriverName,
  required String? secondDriverLicense,
}) {
  final license = secondDriverLicense?.trim();
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: DanjiColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '제2운전자 정보',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: DanjiColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '이름: ${secondDriverName?.trim().isNotEmpty == true ? secondDriverName!.trim() : '-'}',
                style: const TextStyle(
                  fontSize: 15,
                  color: DanjiColors.textPrimary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '연락처(면허번호): ${license != null && license.isNotEmpty ? license : '-'}',
                style: const TextStyle(
                  fontSize: 15,
                  color: DanjiColors.textPrimary,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// 제2운전자 배지 + 이름 (탭 시 상세 시트)
class AdminSecondDriverSummary extends StatelessWidget {
  final String? secondDriverName;
  final String? secondDriverLicense;
  final EdgeInsetsGeometry padding;

  const AdminSecondDriverSummary({
    super.key,
    required this.secondDriverName,
    this.secondDriverLicense,
    this.padding = const EdgeInsets.only(top: 4),
  });

  @override
  Widget build(BuildContext context) {
    if (!adminHasSecondDriver(secondDriverName: secondDriverName)) {
      return const SizedBox.shrink();
    }

    final name = secondDriverName!.trim();

    return Padding(
      padding: padding,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => showAdminSecondDriverInfoSheet(
            context,
            secondDriverName: secondDriverName,
            secondDriverLicense: secondDriverLicense,
          ),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                const AdminSecondDriverBadge(),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      color: DanjiColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: DanjiColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showAdminReservationContract({
  required BuildContext context,
  required AdminService admin,
  required String reservationId,
  String? contractContent,
  String? vehicleName,
  String? renterName,
  String? secondDriverName,
  String? secondDriverLicense,
  String? rentalPeriodOverride,
}) async {
  final id = reservationId.trim();
  if (id.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('예약번호가 없습니다.')),
    );
    return;
  }

  var content = contractContent?.trim();
  if (content == null || content.isEmpty) {
    content = await admin.ensureReservationContractForStaff(id);
  }

  if (!context.mounted) return;
  if (content == null || content.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('계약서가 아직 준비되지 않았습니다.')),
    );
    return;
  }

  final contractText = content;
  var parsed = RentalContractParsed.parse(contractText);
  parsed = parsed.withSecondDriverFallback(
    secondDriverName: secondDriverName,
    secondDriverLicense: secondDriverLicense,
  );
  final displayParsed = parsed.reservationId.isEmpty
      ? RentalContractParsed(
          companyName: parsed.companyName,
          reservationId: id,
          vehicleName: parsed.vehicleName ?? vehicleName,
          rentalPeriod: parsed.rentalPeriod,
          renterName: parsed.renterName ?? renterName,
          renterPhone: parsed.renterPhone,
          licenseNumber: parsed.licenseNumber,
          secondDriverName: parsed.secondDriverName,
          secondDriverLicense: parsed.secondDriverLicense,
          originalPrice: parsed.originalPrice,
          paidPrice: parsed.paidPrice,
          extraFeeLines: parsed.extraFeeLines,
          insuranceIntro: parsed.insuranceIntro,
          insuranceCoverage: parsed.insuranceCoverage,
          insuranceNotes: parsed.insuranceNotes,
          complianceItems: parsed.complianceItems,
          generatedAt: parsed.generatedAt,
        )
      : parsed;
  final finalParsed =
      displayParsed.withRentalPeriodOverride(rentalPeriodOverride);

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return AdminReservationContractSheet(
        contractText: contractText,
        displayParsed: finalParsed,
        reservationId: id,
        vehicleName: vehicleName,
      );
    },
  );
}

/// 관리자 카드 하단 — 계약서 보기 버튼
class AdminReservationContractButton extends StatefulWidget {
  final AdminService admin;
  final String reservationId;
  final String? contractContent;
  final String? vehicleName;
  final String? renterName;
  final String? secondDriverName;
  final String? secondDriverLicense;
  final String? rentalPeriodOverride;

  const AdminReservationContractButton({
    super.key,
    required this.admin,
    required this.reservationId,
    this.contractContent,
    this.vehicleName,
    this.renterName,
    this.secondDriverName,
    this.secondDriverLicense,
    this.rentalPeriodOverride,
  });

  @override
  State<AdminReservationContractButton> createState() =>
      _AdminReservationContractButtonState();
}

class _AdminReservationContractButtonState
    extends State<AdminReservationContractButton> {
  bool _loading = false;

  Future<void> _open() async {
    if (_loading) return;
    final id = widget.reservationId.trim();
    if (id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('예약번호가 없습니다.')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await showAdminReservationContract(
        context: context,
        admin: widget.admin,
        reservationId: id,
        contractContent: widget.contractContent,
        vehicleName: widget.vehicleName,
        renterName: widget.renterName,
        secondDriverName: widget.secondDriverName,
        secondDriverLicense: widget.secondDriverLicense,
        rentalPeriodOverride: widget.rentalPeriodOverride,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyAdminError(e))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _loading ? null : _open,
      icon: _loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.description_outlined, size: 18),
      label: const Text('계약서 보기'),
      style: OutlinedButton.styleFrom(
        foregroundColor: DanjiColors.brandBlue,
        side: const BorderSide(color: DanjiColors.brandBlue),
        minimumSize: const Size.fromHeight(40),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}

class AdminReservationContractSheet extends StatefulWidget {
  final String contractText;
  final RentalContractParsed displayParsed;
  final String reservationId;
  final String? vehicleName;

  const AdminReservationContractSheet({
    super.key,
    required this.contractText,
    required this.displayParsed,
    required this.reservationId,
    this.vehicleName,
  });

  @override
  State<AdminReservationContractSheet> createState() =>
      _AdminReservationContractSheetState();
}

class _AdminReservationContractSheetState
    extends State<AdminReservationContractSheet> {
  bool _downloadingPdf = false;

  Future<void> _downloadPdf() async {
    setState(() => _downloadingPdf = true);
    try {
      final savedPath = await RentalContractPdf.saveContractPdf(
        contractText: widget.contractText,
        reservationId: widget.reservationId,
        vehicleName: widget.vehicleName,
        parsed: widget.displayParsed,
      );
      if (!mounted) return;
      if (savedPath != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('다운로드 폴더에 저장되었습니다.\n$savedPath'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF 저장 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _downloadingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: DanjiColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: DanjiColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '대여 계약서',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: DanjiColors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: widget.displayParsed.hasStructuredLayout
                      ? RentalContractCardView(parsed: widget.displayParsed)
                      : Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: DanjiColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: DanjiColors.border),
                          ),
                          child: SelectableText(
                            widget.contractText,
                            style: const TextStyle(
                              color: DanjiColors.textPrimary,
                              height: 1.5,
                            ),
                          ),
                        ),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _downloadingPdf ? null : _downloadPdf,
                      style: DanjiTheme.primaryButton,
                      icon: _downloadingPdf
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.download_outlined, size: 20),
                      label: const Text('PDF 다운로드'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
