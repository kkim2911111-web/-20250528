import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/inspection_photo.dart';
import '../../models/rental_detail.dart';
import '../../models/staff_profile.dart';
import '../../models/super_admin_models.dart';
import '../../services/admin_service.dart';
import '../../services/rental_detail_service.dart';
import '../../services/super_admin_service.dart';
import '../../theme/danji_colors.dart';
import '../../utils/danji_snackbar.dart';
import '../../utils/phone_launcher.dart';
import '../../utils/reservation_display.dart';
import '../../utils/reservation_status_badge.dart';
import '../../widgets/admin_scaffold.dart';
import '../../widgets/danji_app_bar.dart';
import '../../widgets/rental_type_badge.dart';
import '../../widgets/reservation_times_panel.dart';
import '../../widgets/return_inspection_photo_compare.dart';
import '../../widgets/section_card.dart';

/// 단지·최고 관리자 공용 대여 상세
class RentalDetailScreen extends StatefulWidget {
  final String reservationId;
  final RentalDetailScope scope;
  final AdminService? adminService;
  final SuperAdminService? superAdminService;
  final RentalDetailPrefetch? prefetch;

  const RentalDetailScreen({
    super.key,
    required this.reservationId,
    required this.scope,
    this.adminService,
    this.superAdminService,
    this.prefetch,
  });

  @override
  State<RentalDetailScreen> createState() => _RentalDetailScreenState();
}

class _RentalDetailScreenState extends State<RentalDetailScreen> {
  static final _won = NumberFormat('#,###');
  static final _dateTime = DateFormat('yyyy-MM-dd HH:mm');

  late final RentalDetailService _loader = RentalDetailService(
    adminService: widget.adminService,
    superAdminService: widget.superAdminService,
  );

  late Future<RentalDetailData> _detailFuture;
  late Future<InspectionPhotoSet> _photosFuture;
  bool _actionRunning = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _detailFuture = _loader.load(
      reservationId: widget.reservationId,
      scope: widget.scope,
      prefetch: widget.prefetch,
    );
    _photosFuture = _detailFuture.then(_loadPhotos);
  }

  Future<InspectionPhotoSet> _loadPhotos(RentalDetailData detail) async {
    final row = _adminRowFromDetail(detail);
    if (widget.scope == RentalDetailScope.staff) {
      final admin = widget.adminService ?? AdminService();
      return admin.resolveInspectionPhotoSet(row);
    }
    final service = widget.superAdminService;
    if (service == null) return InspectionPhotoSet.empty;
    final reservation = SuperAdminReservation(
      id: detail.id,
      reservationNumber: detail.reservationNumber,
      complexId: '',
      complexName: detail.complexName ?? '',
      vehicleId: '',
      vehicleName: detail.vehicleName,
      carNumber: detail.carNumber,
      renterName: detail.renterName,
      renterPhone: detail.renterPhone ?? '미등록',
      status: detail.status,
      isNoShow: detail.isNoShow,
      startAt: detail.startAt,
      endAt: detail.endAt,
      rentalStartedAt: detail.rentalStartedAt,
      returnedAt: detail.returnedAt,
      actualEndAt: detail.actualEndAt,
      totalPrice: detail.payment.totalPrice,
      pickupPhotos: row.pickupPhotos,
      returnPhotos: row.returnPhotos,
      rentalType: detail.rentalType,
    );
    return service.fetchInspectionPhotoSet(reservation);
  }

  AdminReservationRow _adminRowFromDetail(RentalDetailData detail) {
    return AdminReservationRow(
      id: detail.id,
      reservationNumber: detail.reservationNumber,
      status: detail.status,
      totalPrice: detail.payment.totalPrice,
      startAt: detail.startAt,
      endAt: detail.endAt,
      rentalStartedAt: detail.rentalStartedAt,
      actualEndAt: detail.actualEndAt,
      returnedAt: detail.returnedAt,
      updatedAt: detail.updatedAt,
      vehicleName: detail.vehicleName,
      carNumber: detail.carNumber,
      isAccident: detail.isAccident,
      accidentNote: detail.accidentNote,
      pickupPhotos: const [],
      returnPhotos: const [],
      renterName: detail.renterName,
      isNoShow: detail.isNoShow,
      rentalType: detail.rentalType,
    );
  }

  Future<void> _confirmForceReturn() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('강제 반납'),
        content: const Text(
          '대여 중인 예약을 반납 처리하여 반납 검수 화면으로 이동합니다.\n'
          '계속하시겠습니까?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('닫기'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('강제 반납'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _actionRunning = true);
    try {
      if (widget.scope == RentalDetailScope.staff) {
        await (widget.adminService ?? AdminService())
            .forceReturnReservation(widget.reservationId);
      } else {
        await widget.superAdminService!
            .forceReturnReservation(widget.reservationId);
      }
      if (!mounted) return;
      DanjiSnackBar.show(context, '반납 검수 대기로 이동했습니다');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      DanjiSnackBar.show(context, _friendlyError(e));
    } finally {
      if (mounted) setState(() => _actionRunning = false);
    }
  }

  Future<void> _confirmPaymentCancel() async {
    final isSuper = widget.scope == RentalDetailScope.superAdmin;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isSuper ? '결제취소' : '강제결제취소'),
        content: const Text(
          '결제를 환불하고 예약을 취소 상태로 변경합니다.\n'
          '차량은 즉시 이용 가능으로 전환됩니다.\n'
          '계속하시겠습니까?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('닫기'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: DanjiColors.accentRed,
            ),
            child: Text(isSuper ? '결제취소' : '강제결제취소'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _actionRunning = true);
    try {
      if (widget.scope == RentalDetailScope.staff) {
        await (widget.adminService ?? AdminService())
            .forcePaymentCancelReservation(widget.reservationId);
      } else {
        await widget.superAdminService!
            .forcePaymentCancelReservation(widget.reservationId);
      }
      if (!mounted) return;
      DanjiSnackBar.show(context, '결제 취소 및 환불 처리되었습니다');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      DanjiSnackBar.show(context, _friendlyError(e));
    } finally {
      if (mounted) setState(() => _actionRunning = false);
    }
  }

  String _friendlyError(Object e) {
    if (widget.scope == RentalDetailScope.staff) {
      return friendlyAdminError(e);
    }
    return friendlySuperAdminError(e);
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      appBar: const DanjiAppBar(title: '대여 상세', showBack: true),
      body: FutureBuilder<RentalDetailData>(
        future: _detailFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _friendlyError(snap.error!),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final detail = snap.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              _HeaderSection(detail: detail),
              const SizedBox(height: 12),
              SectionCard(child: _CustomerSection(detail: detail)),
              const SizedBox(height: 12),
              SectionCard(child: _RentalSection(detail: detail)),
              if (detail.showReturnInspectionSection) ...[
                const SizedBox(height: 12),
                SectionCard(
                  child: _InspectionSection(
                    detail: detail,
                    photosFuture: _photosFuture,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SectionCard(child: _SettlementSection(detail: detail)),
              if (detail.showForceActionButtons) ...[
                const SizedBox(height: 20),
                _ActionSection(
                  detail: detail,
                  scope: widget.scope,
                  running: _actionRunning,
                  onForceReturn: _confirmForceReturn,
                  onPaymentCancel: _confirmPaymentCancel,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _HeaderSection extends StatelessWidget {
  final RentalDetailData detail;

  const _HeaderSection({required this.detail});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    detail.vehicleName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: DanjiColors.textPrimary,
                    ),
                  ),
                  if (detail.carNumber != null &&
                      detail.carNumber!.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      detail.carNumber!,
                      style: const TextStyle(color: DanjiColors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ReservationStatusBadge(
                  status: detail.isNoShow ? 'completed' : detail.status,
                  isNoShow: detail.isNoShow,
                ),
                RentalTypeBadge(rentalType: detail.rentalType),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          detail.reservationNumberLabel,
          style: const TextStyle(
            color: DanjiColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (detail.complexName != null &&
            detail.complexName!.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            detail.complexName!,
            style: const TextStyle(
              color: DanjiColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ],
    );
  }
}

class _CustomerSection extends StatelessWidget {
  final RentalDetailData detail;

  const _CustomerSection({required this.detail});

  @override
  Widget build(BuildContext context) {
    final phone = detail.renterPhone?.trim() ?? '';
    final canCall = phone.isNotEmpty && phone != '미등록';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle('고객'),
        Text(
          detail.renterLine,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: DanjiColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        if (canCall)
          InkWell(
            onTap: () => launchPhoneCall(phone),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  const Text(
                    '전화 ',
                    style: TextStyle(color: DanjiColors.textSecondary),
                  ),
                  Text(
                    phone,
                    style: const TextStyle(
                      color: DanjiColors.buttonBlue,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.phone_outlined,
                    size: 16,
                    color: DanjiColors.buttonBlue,
                  ),
                ],
              ),
            ),
          )
        else
          const _InfoLine(label: '전화', value: '미등록'),
        const SizedBox(height: 6),
        _InfoLine(label: '면허', value: detail.licenseStatusLabel),
        _InfoLine(
          label: '블랙리스트',
          value: detail.isBlacklisted ? '등록' : '아니오',
          valueColor: detail.isBlacklisted ? DanjiColors.accentRed : null,
        ),
      ],
    );
  }
}

class _RentalSection extends StatelessWidget {
  final RentalDetailData detail;

  const _RentalSection({required this.detail});

  @override
  Widget build(BuildContext context) {
    final payment = detail.payment;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle('대여'),
        ReservationTimesPanel(
          formatter: _RentalDetailScreenState._dateTime,
          mode: ReservationTimesMode.admin,
          layout: ReservationTimesLayout.detail,
          scheduledStartAt: detail.startAt,
          scheduledEndAt: detail.endAt,
          rentalStartedAt: detail.rentalStartedAt,
          returnedAt: detail.returnedAt ?? detail.actualEndAt,
          isNoShow: detail.isNoShow,
          status: detail.status,
        ),
        const SizedBox(height: 8),
        _InfoLine(
          label: '결제 금액',
          value: '₩${_RentalDetailScreenState._won.format(payment.totalPrice)}',
        ),
        if (payment.couponDiscount != null && payment.couponDiscount! > 0)
          _InfoLine(
            label: '쿠폰',
            value: '-₩${_RentalDetailScreenState._won.format(payment.couponDiscount)}',
          ),
        if (payment.pointsUsed != null && payment.pointsUsed! > 0)
          _InfoLine(
            label: '포인트',
            value: '${_RentalDetailScreenState._won.format(payment.pointsUsed)}P',
          ),
        _InfoLine(label: '결제 상태', value: detail.paymentStatusLabel),
      ],
    );
  }
}

class _InspectionSection extends StatelessWidget {
  final RentalDetailData detail;
  final Future<InspectionPhotoSet> photosFuture;

  const _InspectionSection({
    required this.detail,
    required this.photosFuture,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle('반납·검수'),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (detail.isNoShow) const _TagBadge(label: '노쇼', color: Color(0xFFE65100)),
            if (detail.isAccident)
              const _TagBadge(label: '파손·사고', color: DanjiColors.accentRed),
          ],
        ),
        if (detail.isAccident &&
            detail.accidentNote != null &&
            detail.accidentNote!.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            detail.accidentNote!.trim(),
            style: const TextStyle(
              color: DanjiColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
        const SizedBox(height: 10),
        FutureBuilder<InspectionPhotoSet>(
          future: photosFuture,
          builder: (context, snap) {
            final photos = snap.data ?? InspectionPhotoSet.empty;
            if (!photos.hasAny) {
              return const Text(
                '검수 사진이 없습니다.',
                style: TextStyle(color: DanjiColors.textSecondary),
              );
            }
            return ReturnInspectionPhotoCompare(
              beforePhotos: photos.before,
              afterPhotos: photos.after,
            );
          },
        ),
      ],
    );
  }
}

class _SettlementSection extends StatelessWidget {
  final RentalDetailData detail;

  const _SettlementSection({required this.detail});

  @override
  Widget build(BuildContext context) {
    final isCancelled = detail.status.trim().toLowerCase() == 'cancelled';
    final isCompleted = detail.status.trim().toLowerCase() == 'completed';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle('정산'),
        if (isCompleted && detail.salesRecognitionMonth != null)
          _InfoLine(
            label: '매출 인식',
            value: detail.salesRecognitionMonth!,
          )
        else if (!isCancelled)
          const _InfoLine(label: '매출 인식', value: '-'),
        if (isCancelled) ...[
          _InfoLine(
            label: '취소 사유',
            value: detail.cancelReasonLabel ?? '-',
          ),
          if (detail.paidAmount != null)
            _InfoLine(
              label: '결제',
              value: '₩${_RentalDetailScreenState._won.format(detail.paidAmount)}',
            ),
          if (detail.refundAmount != null)
            _InfoLine(
              label: '환불',
              value: '₩${_RentalDetailScreenState._won.format(detail.refundAmount)}',
            ),
        ],
        if (!isCompleted && !isCancelled)
          const Text(
            '완료·취소 후 정산 정보가 표시됩니다.',
            style: TextStyle(color: DanjiColors.textMuted, fontSize: 12),
          ),
      ],
    );
  }
}

class _ActionSection extends StatelessWidget {
  final RentalDetailData detail;
  final RentalDetailScope scope;
  final bool running;
  final VoidCallback onForceReturn;
  final VoidCallback onPaymentCancel;

  const _ActionSection({
    required this.detail,
    required this.scope,
    required this.running,
    required this.onForceReturn,
    required this.onPaymentCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (detail.canShowForceReturnButton) ...[
          OutlinedButton(
            onPressed: running ? null : onForceReturn,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFE65100),
              side: const BorderSide(color: Color(0xFFE65100)),
            ),
            child: const Text('강제 반납'),
          ),
          if (detail.canShowPaymentCancelButton) const SizedBox(height: 8),
        ],
        if (detail.canShowPaymentCancelButton)
          OutlinedButton(
            onPressed: running ? null : onPaymentCancel,
            style: OutlinedButton.styleFrom(
              foregroundColor: DanjiColors.accentRed,
              side: const BorderSide(color: DanjiColors.accentRed),
            ),
            child: Text(
              scope == RentalDetailScope.superAdmin
                  ? '결제취소'
                  : '강제결제취소',
            ),
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 15,
          color: DanjiColors.textPrimary,
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoLine({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
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
              value,
              style: TextStyle(
                color: valueColor ?? DanjiColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TagBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _TagBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
