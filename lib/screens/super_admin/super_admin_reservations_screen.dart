import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/super_admin_models.dart';
import '../../services/super_admin_service.dart';
import '../../theme/danji_colors.dart';
import '../../utils/danji_snackbar.dart';
import '../../utils/reservation_status_badge.dart';
import '../../utils/refund_status_display.dart';
import '../../utils/super_admin_reservation_sort.dart';
import '../../widgets/admin_scaffold.dart';
import '../../widgets/danji_app_bar.dart';
import '../../widgets/inspection_photo_compare_panel.dart';
import '../../widgets/rental_type_badge.dart';
import '../../utils/rental_detail_navigation.dart';
import '../../widgets/section_card.dart';
import 'super_admin_common.dart';

class SuperAdminReservationsScreen extends StatefulWidget {
  final SuperAdminService service;
  const SuperAdminReservationsScreen({super.key, required this.service});
  @override
  State<SuperAdminReservationsScreen> createState() =>
      _SuperAdminReservationsScreenState();
}

class _SuperAdminReservationsScreenState
    extends State<SuperAdminReservationsScreen> {
  List<SuperAdminReservation> _reservations = [];
  Object? _loadError;
  bool _loading = true;

  String? _complexFilter;
  late int _year = DateTime.now().year;
  late int _month = DateTime.now().month;
  DateTime? _filterDate;

  static final _dateLabel = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final data = await widget.service.fetchReservations();
      if (!mounted) return;
      setState(() {
        _reservations = data;
        _loadError = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  void _syncFilterDateWithMonth() {
    final d = _filterDate;
    if (d == null) return;
    if (d.year != _year || d.month != _month) {
      _filterDate = null;
    }
  }

  Future<void> _pickFilterDate() async {
    final monthStart = DateTime(_year, _month, 1);
    final monthEnd = DateTime(_year, _month + 1, 0);
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterDate ?? monthStart,
      firstDate: monthStart,
      lastDate: monthEnd,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _filterDate = DateTime(picked.year, picked.month, picked.day);
    });
  }

  List<SuperAdminReservation> _filter(List<SuperAdminReservation> all) {
    final filtered = all.where((r) {
      if (_complexFilter != null &&
          _complexFilter!.isNotEmpty &&
          r.complexId != _complexFilter) {
        return false;
      }
      return superAdminReservationMatchesMonth(
        reservation: r,
        year: _year,
        month: _month,
        filterDate: _filterDate,
      );
    }).toList();
    sortSuperAdminReservations(filtered, filterDate: _filterDate);
    return filtered;
  }

  Future<bool> _confirmAction({
    required String title,
    required String message,
    required String confirmLabel,
    Color? confirmColor,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('닫기'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: confirmColor != null
                ? FilledButton.styleFrom(backgroundColor: confirmColor)
                : null,
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _openDetail(SuperAdminReservation r) async {
    await showSuperAdminBottomSheet<void>(
      context,
      title: r.vehicleName,
      child: _SuperAdminReservationDetailSheet(
        reservation: r,
        service: widget.service,
        onForceReturn: () async {
          Navigator.pop(context);
          final confirmed = await _confirmAction(
            title: '강제 반납',
            message:
                '대여 중인 예약을 반납 처리하여 반납 검수 화면으로 이동합니다.\n'
                '계속하시겠습니까?',
            confirmLabel: '강제 반납',
          );
          if (!confirmed || !mounted) return;
          try {
            await widget.service.forceReturnReservation(r.id);
            if (!mounted) return;
            DanjiSnackBar.show(context, '반납 검수 대기로 이동했습니다');
            await _reload();
          } catch (e) {
            if (mounted) {
              DanjiSnackBar.show(context, friendlySuperAdminError(e));
            }
          }
        },
        onPaymentCancel: () async {
          Navigator.pop(context);
          final confirmed = await _confirmAction(
            title: '결제취소',
            message:
                '결제를 환불하고 예약을 취소 상태로 변경합니다.\n'
                '차량은 즉시 이용 가능으로 전환됩니다.\n'
                '계속하시겠습니까?',
            confirmLabel: '결제취소',
            confirmColor: DanjiColors.accentRed,
          );
          if (!confirmed || !mounted) return;
          try {
            await widget.service.forcePaymentCancelReservation(r.id);
            if (!mounted) return;
            DanjiSnackBar.show(context, '결제 취소 및 환불 처리되었습니다');
            await _reload();
          } catch (e) {
            if (mounted) {
              DanjiSnackBar.show(context, friendlySuperAdminError(e));
            }
          }
        },
      ),
    );
  }

  Widget _buildList(List<SuperAdminReservation> filtered) {
    if (filtered.isEmpty) {
      final emptyMessage = _reservations.isEmpty
          ? '예약이 없습니다.'
          : '조건에 맞는 예약이 없습니다.';
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          SuperAdminEmptyState(emptyMessage),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final r = filtered[i];
        final axisLabel = superAdminReservationAxisLabel(r);
        return SuperAdminListCard(
          icon: Icons.event_note_outlined,
          title: '${r.vehicleName} · ${r.renterName}',
          subtitle: '$axisLabel · ${r.complexName} · '
              '₩${superAdminWon.format(r.totalPrice)}',
          titleSuffix: ReservationDisplayBadgeRow(
            status: r.status,
            isNoShow: r.isNoShow,
            paidAmount: r.paidAmount,
            refundAmount: r.refundAmount,
          ),
          onTap: () => _openDetail(r),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AdminScaffold(
        appBar: DanjiAppBar(title: '전체 예약'),
        body: SuperAdminLoadingBody(),
      );
    }
    if (_loadError != null) {
      return AdminScaffold(
        appBar: const DanjiAppBar(title: '전체 예약'),
        body: Center(child: Text(friendlySuperAdminError(_loadError!))),
      );
    }

    final complexes = <String, String>{};
    for (final r in _reservations) {
      complexes[r.complexId] = r.complexName;
    }
    final filtered = _filter(_reservations);

    return AdminScaffold(
      appBar: const DanjiAppBar(title: '전체 예약'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              children: [
                SuperAdminMonthFilter(
                  year: _year,
                  month: _month,
                  onYearChanged: (y) => setState(() {
                    _year = y;
                    _syncFilterDateWithMonth();
                  }),
                  onMonthChanged: (m) => setState(() {
                    _month = m;
                    _syncFilterDateWithMonth();
                  }),
                ),
                const SizedBox(height: 8),
                SectionCard(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      isExpanded: true,
                      value: _complexFilter,
                      hint: const Text('전체 단지'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('전체 단지')),
                        ...complexes.entries.map(
                          (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                        ),
                      ],
                      onChanged: (v) => setState(() => _complexFilter = v),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SectionCard(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickFilterDate,
                          icon: const Icon(Icons.calendar_today_outlined, size: 16),
                          label: Text(
                            _filterDate == null
                                ? '날짜 선택'
                                : _dateLabel.format(_filterDate!),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: DanjiColors.buttonBlue,
                            side: const BorderSide(color: DanjiColors.buttonBlue),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                      if (_filterDate != null) ...[
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => setState(() => _filterDate = null),
                          child: const Text('초기화'),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    superAdminReservationSortHint(filterDate: _filterDate),
                    style: const TextStyle(
                      color: DanjiColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: DanjiColors.buttonBlue,
              onRefresh: _reload,
              child: _buildList(filtered),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuperAdminReservationDetailSheet extends StatefulWidget {
  final SuperAdminReservation reservation;
  final SuperAdminService service;
  final VoidCallback onForceReturn;
  final VoidCallback onPaymentCancel;

  const _SuperAdminReservationDetailSheet({
    required this.reservation,
    required this.service,
    required this.onForceReturn,
    required this.onPaymentCancel,
  });

  @override
  State<_SuperAdminReservationDetailSheet> createState() =>
      _SuperAdminReservationDetailSheetState();
}

class _SuperAdminReservationDetailSheetState
    extends State<_SuperAdminReservationDetailSheet> {
  late Future<SuperAdminRenterUsageStats> _usageFuture;

  @override
  void initState() {
    super.initState();
    _usageFuture = widget.service.fetchRenterUsageStats(
      reservationId: widget.reservation.id,
    );
  }

  Widget _timeLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          color: DanjiColors.textSecondary,
          fontSize: 13,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reservation;
    final hasReservationTime = r.startAt != null || r.endAt != null;
    final actualPickup = r.rentalStartedAt;
    final actualReturn = r.actualReturnAt;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          r.reservationNumberLabel,
          style: const TextStyle(color: DanjiColors.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Text(
          r.complexName,
          style: const TextStyle(color: DanjiColors.textSecondary),
        ),
        const SizedBox(height: 4),
        FutureBuilder<SuperAdminRenterUsageStats>(
          future: _usageFuture,
          builder: (context, snap) {
            final stats = snap.data ?? SuperAdminRenterUsageStats.empty;
            final renterLine = snap.connectionState == ConnectionState.waiting
                ? r.renterName
                : stats.formatLine(r.renterName);
            return Text(
              renterLine,
              style: const TextStyle(
                color: DanjiColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ReservationStatusBadge(
              status: r.status,
              isNoShow: r.isNoShow,
            ),
            RentalTypeBadge(rentalType: r.rentalType),
            SuperAdminChip(
              label: '₩${superAdminWon.format(r.totalPrice)}',
              color: SuperAdminUiColors.revenueSky,
            ),
          ],
        ),
        if (hasReservationTime)
          _timeLine(
            '예약 시간',
            '${r.startAt != null ? superAdminDateTime.format(r.startAt!) : '-'} ~ '
            '${r.endAt != null ? superAdminDateTime.format(r.endAt!) : '-'}',
          ),
        if (actualPickup != null)
          _timeLine(
            '실제 출고',
            superAdminDateTime.format(actualPickup),
          ),
        if (actualReturn != null)
          _timeLine(
            '실제 반납',
            superAdminDateTime.format(actualReturn),
          ),
        const SizedBox(height: 12),
        InspectionPhotoComparePanel(
          future: widget.service.fetchInspectionPhotoSet(r),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () {
            Navigator.pop(context);
            openSuperAdminRentalDetail(
              context,
              reservationId: r.id,
              service: widget.service,
            );
          },
          child: const Text('상세'),
        ),
        if (r.showForceActionButtons) ...[
          const SizedBox(height: 8),
          if (r.canShowForceReturnButton) ...[
            OutlinedButton(
              onPressed: widget.onForceReturn,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFE65100),
                side: const BorderSide(color: Color(0xFFE65100)),
              ),
              child: const Text('강제 반납'),
            ),
            if (r.canShowPaymentCancelButton) const SizedBox(height: 8),
          ],
          if (r.canShowPaymentCancelButton)
            OutlinedButton(
              onPressed: widget.onPaymentCancel,
              style: OutlinedButton.styleFrom(
                foregroundColor: DanjiColors.accentRed,
                side: const BorderSide(color: DanjiColors.accentRed),
              ),
              child: const Text('결제취소'),
            ),
        ],
      ],
    );
  }
}
