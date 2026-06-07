import 'package:flutter/material.dart';
import '../services/rental_service.dart';
import '../utils/rental_contract_pdf.dart';
import '../theme/danji_colors.dart';
import '../theme/danji_theme.dart';
import '../utils/rental_contract_parser.dart';
import '../widgets/danji_app_bar.dart';
import '../widgets/rental_contract_cards.dart';

/// 대여 계약서 열람·PDF 저장
class RentalContractScreen extends StatefulWidget {
  final String reservationId;
  final String? vehicleName;
  final String? initialContent;
  final String? secondDriverName;
  final String? secondDriverLicense;
  final String? rentalPeriodOverride;

  const RentalContractScreen({
    super.key,
    required this.reservationId,
    this.vehicleName,
    this.initialContent,
    this.secondDriverName,
    this.secondDriverLicense,
    this.rentalPeriodOverride,
  });

  @override
  State<RentalContractScreen> createState() => _RentalContractScreenState();
}

class _RentalContractScreenState extends State<RentalContractScreen> {
  final _rentalService = RentalService();
  String? _content;
  bool _loading = true;
  String? _error;
  bool _sharingPdf = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cached = widget.initialContent?.trim();
    if (cached != null && cached.isNotEmpty) {
      setState(() {
        _content = cached;
        _loading = false;
      });
      return;
    }

    try {
      final text = await _rentalService.fetchContractContent(
        widget.reservationId,
      );
      if (!mounted) return;
      setState(() {
        _content = text;
        _loading = false;
        _error = text == null ? '계약서가 아직 준비되지 않았습니다.' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  RentalContractParsed _parsedContent() {
    var parsed = RentalContractParsed.parse(_content ?? '');
    parsed = parsed.withSecondDriverFallback(
      secondDriverName: widget.secondDriverName,
      secondDriverLicense: widget.secondDriverLicense,
    );
    if (parsed.vehicleName == null &&
        widget.vehicleName?.trim().isNotEmpty == true) {
      parsed = RentalContractParsed(
        companyName: parsed.companyName,
        reservationId:
            parsed.reservationId.isNotEmpty ? parsed.reservationId : widget.reservationId,
        vehicleName: widget.vehicleName,
        rentalPeriod: parsed.rentalPeriod,
        renterName: parsed.renterName,
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
      );
    } else if (parsed.reservationId.isEmpty) {
      parsed = RentalContractParsed(
        companyName: parsed.companyName,
        reservationId: widget.reservationId,
        vehicleName: parsed.vehicleName ?? widget.vehicleName,
        rentalPeriod: parsed.rentalPeriod,
        renterName: parsed.renterName,
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
      );
    }
    return parsed.withRentalPeriodOverride(widget.rentalPeriodOverride);
  }

  Future<void> _downloadPdf() async {
    final text = _content?.trim();
    if (text == null || text.isEmpty) return;

    setState(() => _sharingPdf = true);
    try {
      final savedPath = await RentalContractPdf.saveContractPdf(
        contractText: text,
        reservationId: widget.reservationId,
        vehicleName: widget.vehicleName,
        parsed: _parsedContent(),
      );
      if (!mounted) return;
      if (savedPath != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('다운로드 폴더에 저장되었습니다.\n$savedPath')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF 저장 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _sharingPdf = false);
    }
  }

  bool get _hasContractContent {
    final text = _content?.trim();
    return text != null && text.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: const DanjiAppBar(title: '대여 계약서'),
      body: Column(
        children: [
          Expanded(child: _buildBody()),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _hasContractContent && !_sharingPdf
                      ? _downloadPdf
                      : null,
                  style: DanjiTheme.primaryButton,
                  child: _sharingPdf
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('PDF 다운로드'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: DanjiColors.textSecondary),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _load();
                },
                style: DanjiTheme.primaryButton,
                child: const Text('다시 불러오기'),
              ),
            ],
          ),
        ),
      );
    }

    final parsed = _parsedContent();

    if (!parsed.hasStructuredLayout) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: DanjiColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DanjiColors.border),
          ),
          child: SelectableText(
            _content!,
            style: const TextStyle(
              color: DanjiColors.textPrimary,
              fontSize: 14,
              height: 1.55,
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: RentalContractCardView(parsed: parsed),
    );
  }
}
