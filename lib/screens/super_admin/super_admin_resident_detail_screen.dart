import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/super_admin_models.dart';
import '../../services/super_admin_service.dart';
import '../../theme/danji_colors.dart';
import '../../theme/danji_theme.dart';
import '../../utils/danji_snackbar.dart';
import '../../utils/rental_contract_parser.dart';
import '../../utils/resident_display.dart';
import '../../widgets/admin_scaffold.dart';
import '../../widgets/admin_reservation_card_extras.dart';
import '../../widgets/danji_app_bar.dart';
import '../../widgets/section_card.dart';
import 'super_admin_common.dart';

class SuperAdminResidentDetailScreen extends StatefulWidget {
  final SuperAdminService service;
  final SuperAdminResident resident;

  const SuperAdminResidentDetailScreen({
    super.key,
    required this.service,
    required this.resident,
  });

  @override
  State<SuperAdminResidentDetailScreen> createState() =>
      _SuperAdminResidentDetailScreenState();
}

class _SuperAdminResidentDetailScreenState
    extends State<SuperAdminResidentDetailScreen> {
  Future<SuperAdminResidentDetail>? _future;
  bool _rentalsExpanded = false;
  String? _openingContractId;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = widget.service.fetchResidentDetail(widget.resident.userId);
    });
  }

  String _licenseStatusLabel(String status) {
    switch (status) {
      case 'approved':
        return '승인';
      case 'pending':
        return '심사중';
      case 'rejected':
        return '거절';
      case 'none':
      default:
        return '미등록';
    }
  }

  Color _licenseStatusColor(String status) {
    switch (status) {
      case 'approved':
        return SuperAdminUiColors.availableGreen;
      case 'pending':
        return DanjiColors.buttonBlue;
      case 'rejected':
        return DanjiColors.danger;
      default:
        return DanjiColors.textMuted;
    }
  }

  Future<void> _rejectLicense(SuperAdminResidentDetail detail) async {
    final reason = TextEditingController();
    final ok = await showSuperAdminBottomSheet<bool>(
      context,
      title: '면허 강제 거절',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: reason,
            decoration: const InputDecoration(labelText: '거절 사유'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: DanjiTheme.dangerButton,
            child: const Text('거절'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.service.forceLicenseRejected(
        detail.userId,
        reason: reason.text.trim().isEmpty ? null : reason.text.trim(),
      );
      if (!mounted) return;
      _reload();
    } catch (e) {
      if (mounted) DanjiSnackBar.show(context, friendlySuperAdminError(e));
    }
  }

  Future<void> _openContract(
    SuperAdminResidentDetail detail,
    SuperAdminResidentRental rental,
  ) async {
    if (_openingContractId != null) return;
    setState(() => _openingContractId = rental.reservationId);
    try {
      await showSuperAdminReservationContract(
        context: context,
        service: widget.service,
        reservationId: rental.reservationId,
        vehicleName: rental.vehicleName,
        renterName: detail.fullName,
        secondDriverName: rental.secondDriverName,
        secondDriverLicense: rental.secondDriverLicense,
        rentalPeriodOverride: _rentalPeriodLabel(rental),
      );
    } catch (e) {
      if (mounted) DanjiSnackBar.show(context, friendlySuperAdminError(e));
    } finally {
      if (mounted) setState(() => _openingContractId = null);
    }
  }

  Widget _infoRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: const TextStyle(
                color: DanjiColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              (value == null || value.trim().isEmpty) ? '-' : value,
              style: const TextStyle(
                color: DanjiColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(
    String title,
    List<Widget> children, {
    Widget? titleTrailing,
  }) {
    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              if (titleTrailing != null) ...[
                const SizedBox(width: 8),
                titleTrailing,
              ],
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildBody(SuperAdminResidentDetail detail) {
    final joinLabel = ResidentDisplay.formatDay(detail.createdAt);
    final lastRentalLabel = detail.lastRentalAt == null
        ? '대여 이력 없음'
        : ResidentDisplay.formatDay(detail.lastRentalAt);
    final licenseExpiryLabel =
        ResidentDisplay.formatLicenseExpiry(detail.licenseExpiry) ?? '-';
    final dongHo =
        '${detail.building ?? ''}동 ${detail.unit ?? ''}호'.trim();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _section(
          '기본 정보',
          [
            _infoRow('이름', detail.fullName),
            _infoRow('이메일', detail.email),
            _infoRow('전화번호', detail.phone),
            _infoRow('단지/동호', '${detail.complexName} $dongHo'),
            _infoRow('가입일', joinLabel),
            _infoRow('최근 대여일', lastRentalLabel),
            if (detail.isBlacklisted)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SuperAdminChip(
                    label: '블랙리스트',
                    color: DanjiColors.danger,
                  ),
                ),
              ),
          ],
          titleTrailing: SuperAdminChip(
            label: detail.approved ? '승인' : '대기',
            color: detail.approved
                ? SuperAdminUiColors.availableGreen
                : DanjiColors.danger,
          ),
        ),
        const SizedBox(height: 10),
        _section(
          '면허 정보',
          [
            _infoRow('면허번호', detail.licenseNumber),
            _infoRow('만료일', licenseExpiryLabel),
          ],
          titleTrailing: SuperAdminChip(
            label: _licenseStatusLabel(detail.licenseStatus),
            color: _licenseStatusColor(detail.licenseStatus),
          ),
        ),
        const SizedBox(height: 10),
        _section('포인트/쿠폰', [
          _infoRow('보유 포인트', '${superAdminWon.format(detail.points)}P'),
          _infoRow('보유 쿠폰', '${detail.couponCount}장'),
        ]),
        const SizedBox(height: 10),
        SectionCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              InkWell(
                onTap: () =>
                    setState(() => _rentalsExpanded = !_rentalsExpanded),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '대여 이력',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Text(
                        '대여 ${detail.rentalCount}건',
                        style: const TextStyle(
                          color: DanjiColors.buttonBlue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _rentalsExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        color: DanjiColors.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
              if (_rentalsExpanded) ...[
                const Divider(height: 1),
                if (detail.rentals.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      '대여 이력이 없습니다.',
                      style: TextStyle(color: DanjiColors.textSecondary),
                    ),
                  )
                else
                  ...detail.rentals.map((rental) {
                    final period = _rentalPeriodLabel(rental);
                    final loading =
                        _openingContractId == rental.reservationId;
                    return ListTile(
                      onTap: loading ? null : () => _openContract(detail, rental),
                      title: Text(
                        '${rental.reservationNumberLabel} · ${rental.vehicleName}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        '$period · ${rental.status}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              '₩${superAdminWon.format(rental.totalPrice)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: DanjiColors.buttonBlue,
                              ),
                            ),
                    );
                  }),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (!detail.approved)
          FilledButton(
            onPressed: () async {
              await widget.service.setResidentApproved(detail.userId, true);
              if (!mounted) return;
              _reload();
            },
            style: superAdminPrimaryFabStyle,
            child: const Text('입주민 승인'),
          ),
        if (detail.approved) ...[
          OutlinedButton(
            onPressed: () async {
              await widget.service.setResidentApproved(detail.userId, false);
              if (!mounted) return;
              _reload();
            },
            child: const Text('입주민 승인 취소'),
          ),
          const SizedBox(height: 8),
        ],
        if (!detail.licenseVerified)
          OutlinedButton(
            onPressed: () async {
              await widget.service.forceLicenseApproved(detail.userId);
              if (!mounted) return;
              _reload();
            },
            child: const Text('면허 강제 승인'),
          ),
        if (detail.licenseVerified) ...[
          OutlinedButton(
            onPressed: () => _rejectLicense(detail),
            child: const Text('면허 강제 거절'),
          ),
          const SizedBox(height: 8),
        ],
        OutlinedButton(
          onPressed: () async {
            final registering = !detail.isBlacklisted;
            if (registering) {
              final confirm = await superAdminConfirmDialog(
                context,
                title: '블랙리스트 등록',
                message:
                    '${detail.fullName ?? detail.email} 계정을 블랙리스트에 등록할까요?\n'
                    '확정·대기 중인 예약은 자동 취소·환불됩니다.',
                confirmLabel: '등록',
                danger: true,
              );
              if (!confirm || !mounted) return;
            }
            final result = await widget.service.setBlacklist(
              detail.userId,
              registering,
            );
            if (!mounted) return;
            if (registering && result.cancelledCount > 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '블랙리스트 등록 완료. 예약 ${result.cancelledCount}건이 취소·환불 처리되었습니다.',
                  ),
                ),
              );
            }
            _reload();
          },
          style: detail.isBlacklisted
              ? null
              : OutlinedButton.styleFrom(
                  foregroundColor: DanjiColors.danger,
                  side: const BorderSide(color: DanjiColors.danger),
                ),
          child: Text(
            detail.isBlacklisted ? '블랙리스트 해제' : '블랙리스트 등록',
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () async {
            final confirm = await superAdminConfirmDialog(
              context,
              title: '입주민 삭제',
              message: '${detail.fullName ?? detail.email} 입주민을 삭제할까요?',
              confirmLabel: '삭제',
              danger: true,
            );
            if (!confirm || !mounted) return;
            await widget.service.deleteResident(detail.userId);
            if (!mounted) return;
            Navigator.pop(context, true);
          },
          style: DanjiTheme.dangerButton,
          child: const Text('삭제'),
        ),
      ],
    );
  }

  String _rentalPeriodLabel(SuperAdminResidentRental rental) {
    final start = rental.displayRentalStartAt;
    final end = rental.displayRentalEndAt;
    if (start == null && end == null) return '-';
    final fmt = DateFormat('yyyy-MM-dd HH:mm');
    final s = start != null ? fmt.format(start.toLocal()) : '-';
    final e = end != null ? fmt.format(end.toLocal()) : '-';
    return '$s ~ $e';
  }

  @override
  Widget build(BuildContext context) {
    final title =
        widget.resident.fullName ?? widget.resident.email ?? '입주민 상세';

    return AdminScaffold(
      appBar: DanjiAppBar(title: title),
      body: FutureBuilder<SuperAdminResidentDetail>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const SuperAdminLoadingBody();
          }
          if (snap.hasError) {
            return Center(child: Text(friendlySuperAdminError(snap.error!)));
          }
          return RefreshIndicator(
            color: DanjiColors.buttonBlue,
            onRefresh: () async => _reload(),
            child: _buildBody(snap.data!),
          );
        },
      ),
    );
  }
}

Future<void> showSuperAdminReservationContract({
  required BuildContext context,
  required SuperAdminService service,
  required String reservationId,
  String? vehicleName,
  String? renterName,
  String? secondDriverName,
  String? secondDriverLicense,
  String? rentalPeriodOverride,
}) async {
  final id = reservationId.trim();
  if (id.isEmpty) {
    DanjiSnackBar.show(context, '예약번호가 없습니다.');
    return;
  }

  final content = await service.ensureReservationContract(id);
  if (!context.mounted) return;
  if (content == null || content.isEmpty) {
    DanjiSnackBar.show(context, '계약서가 아직 준비되지 않았습니다.');
    return;
  }

  var parsed = RentalContractParsed.parse(content);
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
        contractText: content,
        displayParsed: finalParsed,
        reservationId: id,
        vehicleName: vehicleName,
      );
    },
  );
}
