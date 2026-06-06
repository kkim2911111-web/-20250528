import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/staff_profile.dart';
import '../../services/admin_service.dart';
import '../../theme/danji_colors.dart';
import '../../utils/danji_snackbar.dart';
import '../../widgets/admin_scaffold.dart';
import '../../widgets/danji_app_bar.dart';
import '../../widgets/section_card.dart';

enum _ReservationFilter { all, inUse, waiting, conflict, completed }

class _AdminReservationLists {
  final List<Map<String, dynamic>> active;
  final List<Map<String, dynamic>> completed;

  const _AdminReservationLists({
    required this.active,
    required this.completed,
  });
}

class AdminReservationListScreen extends StatefulWidget {
  const AdminReservationListScreen({super.key});

  @override
  State<AdminReservationListScreen> createState() =>
      _AdminReservationListScreenState();
}

class _AdminReservationListScreenState
    extends State<AdminReservationListScreen> {
  final _admin = AdminService();
  final _dateTime = DateFormat('yyyy-MM-dd HH:mm');
  final _timeOnly = DateFormat('HH:mm');
  final _won = NumberFormat('#,###');

  _ReservationFilter _filter = _ReservationFilter.all;
  Future<_AdminReservationLists>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<_AdminReservationLists> _load() async {
    final results = await Future.wait([
      _admin.getAdminReservationsWithConflict(),
      _admin.getAdminCompletedReservations(),
    ]);
    return _AdminReservationLists(
      active: results[0],
      completed: results[1],
    );
  }

  List<Map<String, dynamic>> _applyFilter(_AdminReservationLists data) {
    if (_filter == _ReservationFilter.completed) {
      return data.completed;
    }

    final rows = data.active;
    switch (_filter) {
      case _ReservationFilter.inUse:
        return rows.where((r) {
          final s = _status(r);
          return s == 'in_use' || s == 'returning';
        }).toList();
      case _ReservationFilter.waiting:
        return rows
            .where((r) {
              final s = _status(r);
              return s == 'confirmed' || s == 'pending';
            })
            .toList();
      case _ReservationFilter.conflict:
        return rows.where((r) => _isConflictRisk(r)).toList();
      case _ReservationFilter.all:
      case _ReservationFilter.completed:
        return rows;
    }
  }

  Future<void> _confirmForceComplete(Map<String, dynamic> row) async {
    final id = _reservationId(row);
    if (id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('강제 완료'),
        content: const Text('이 예약을 강제 완료 처리하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _admin.forceCompleteReservation(id);
      if (!mounted) return;
      DanjiSnackBar.show(context, '강제 완료 처리되었습니다');
      _reload();
    } catch (e) {
      if (!mounted) return;
      DanjiSnackBar.show(context, friendlyAdminError(e));
    }
  }

  int _conflictCount(_AdminReservationLists? data) {
    if (data == null) return 0;
    return data.active.where(_isConflictRisk).length;
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      appBar: const DanjiAppBar(title: '예약 관리'),
      body: FutureBuilder<_AdminReservationLists>(
        future: _future,
        builder: (context, snap) {
          final conflictCount = _conflictCount(snap.data);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      children: [
                      _FilterChip(
                        label: '전체',
                        selected: _filter == _ReservationFilter.all,
                        onTap: () =>
                            setState(() => _filter = _ReservationFilter.all),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: '진행중',
                        selected: _filter == _ReservationFilter.inUse,
                        onTap: () =>
                            setState(() => _filter = _ReservationFilter.inUse),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: '예정',
                        selected: _filter == _ReservationFilter.waiting,
                        onTap: () => setState(
                          () => _filter = _ReservationFilter.waiting,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: '충돌위험',
                        selected: _filter == _ReservationFilter.conflict,
                        badgeCount: conflictCount,
                        onTap: () => setState(
                          () => _filter = _ReservationFilter.conflict,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: '완료',
                        selected: _filter == _ReservationFilter.completed,
                        onTap: () => setState(
                          () => _filter = _ReservationFilter.completed,
                        ),
                      ),
                    ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  color: DanjiColors.buttonBlue,
                  onRefresh: () async => _reload(),
                  child: _buildReservationList(snap),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildReservationList(
    AsyncSnapshot<_AdminReservationLists> snap,
  ) {
    if (snap.connectionState == ConnectionState.waiting) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (snap.hasError) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          Text(friendlyAdminError(snap.error!)),
        ],
      );
    }
    final filtered = _applyFilter(snap.data!);
    if (filtered.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 80),
          Center(child: Text('표시할 예약이 없습니다.')),
        ],
      );
    }
    final isCompletedTab = _filter == _ReservationFilter.completed;

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final row = filtered[index];
        if (isCompletedTab) {
          return _CompletedReservationCard(
            row: row,
            dateTime: _dateTime,
            won: _won,
          );
        }
        return _ReservationCard(
          row: row,
          dateTime: _dateTime,
          timeOnly: _timeOnly,
          won: _won,
          showForceComplete: _isStuckReservation(row),
          onForceComplete: () => _confirmForceComplete(row),
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badgeCount;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final chip = Material(
      color: selected ? DanjiColors.buttonBlue : DanjiColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            16,
            10,
            badgeCount > 0 ? 22 : 16,
            10,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? DanjiColors.buttonBlue : DanjiColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : DanjiColors.textPrimary,
            ),
          ),
        ),
      ),
    );

    if (badgeCount < 1) return chip;

    final badgeLabel = badgeCount > 99 ? '99+' : '$badgeCount';

    return Stack(
      clipBehavior: Clip.none,
      children: [
        chip,
        Positioned(
          right: 0,
          top: -8,
          child: Container(
            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: DanjiColors.accentRed,
              shape: BoxShape.circle,
              border: Border.all(color: DanjiColors.background, width: 1.5),
            ),
            alignment: Alignment.center,
            child: Text(
              badgeLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CompletedReservationCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final DateFormat dateTime;
  final NumberFormat won;

  const _CompletedReservationCard({
    required this.row,
    required this.dateTime,
    required this.won,
  });

  @override
  Widget build(BuildContext context) {
    final vehicleName = _str(row, 'vehicle_name') ?? '차량';
    final renterName = AdminReservationRow.resolveRenterDisplayName(
      directRenterName: _str(row, 'renter_name'),
    );
    final status = _status(row);
    final start = _parseDate(row['start_at']);
    final end = _parseDate(row['end_at']);
    final totalPrice = (row['total_price'] as num?)?.toInt() ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SectionCard.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DanjiColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  vehicleName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: DanjiColors.textPrimary,
                  ),
                ),
              ),
              _StatusBadge(status: status),
            ],
          ),
          const SizedBox(height: 8),
          _ReservationRenterSummary(
            row: row,
            won: won,
            renterName: renterName,
            totalPrice: totalPrice,
          ),
          const SizedBox(height: 6),
          Text(
            '대여기간: ${start != null ? dateTime.format(start) : '-'} ~ '
            '${end != null ? dateTime.format(end) : '-'}',
            style: const TextStyle(
              color: DanjiColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReservationCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final DateFormat dateTime;
  final DateFormat timeOnly;
  final NumberFormat won;
  final bool showForceComplete;
  final VoidCallback? onForceComplete;

  const _ReservationCard({
    required this.row,
    required this.dateTime,
    required this.timeOnly,
    required this.won,
    this.showForceComplete = false,
    this.onForceComplete,
  });

  @override
  Widget build(BuildContext context) {
    final conflict = _isConflictRisk(row);
    final vehicleName = _str(row, 'vehicle_name') ?? '차량';
    final carNumber = _str(row, 'car_number');
    final status = _status(row);
    final start = _parseDate(row['start_at']);
    final end = _parseDate(row['end_at']);
    final nextStart = _parseDate(row['next_start_at']);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SectionCard.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: conflict ? DanjiColors.accentRed : DanjiColors.border,
          width: conflict ? 2 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  vehicleName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: DanjiColors.textPrimary,
                  ),
                ),
              ),
              _StatusBadge(status: status),
            ],
          ),
          if (carNumber != null && carNumber.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              carNumber,
              style: const TextStyle(color: DanjiColors.textSecondary),
            ),
          ],
          const SizedBox(height: 8),
          _ReservationRenterSummary(
            row: row,
            won: won,
            renterName: AdminReservationRow.resolveRenterDisplayName(
              directRenterName: _str(row, 'renter_name'),
            ),
            totalPrice: (row['total_price'] as num?)?.toInt() ?? 0,
          ),
          const SizedBox(height: 6),
          Text(
            '${start != null ? dateTime.format(start) : '-'} ~ '
            '${end != null ? dateTime.format(end) : '-'}',
            style: const TextStyle(
              color: DanjiColors.textSecondary,
              height: 1.4,
            ),
          ),
          if (nextStart != null) ...[
            const SizedBox(height: 6),
            Text(
              '다음예약: ${timeOnly.format(nextStart)}',
              style: const TextStyle(
                color: DanjiColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
          if (conflict) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0F0),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '⚠️ 충돌위험',
                style: TextStyle(
                  color: DanjiColors.accentRed,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ],
          if (showForceComplete && onForceComplete != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: onForceComplete,
                style: OutlinedButton.styleFrom(
                  foregroundColor: DanjiColors.accentRed,
                  side: const BorderSide(color: DanjiColors.accentRed),
                ),
                child: const Text('강제 완료'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReservationRenterSummary extends StatelessWidget {
  final Map<String, dynamic> row;
  final NumberFormat won;
  final String renterName;
  final int totalPrice;

  const _ReservationRenterSummary({
    required this.row,
    required this.won,
    required this.renterName,
    required this.totalPrice,
  });

  @override
  Widget build(BuildContext context) {
    final phone = _renterPhoneLabel(row);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '임차인: $renterName',
          style: const TextStyle(
            color: DanjiColors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '전화번호: $phone',
          style: const TextStyle(
            color: DanjiColors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '결제 금액: ₩${won.format(totalPrice)}',
          style: const TextStyle(
            color: DanjiColors.textPrimary,
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = _style(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  (String, Color, Color) _style(String status) {
    switch (status) {
      case 'in_use':
        return ('대여중', const Color(0xFFFFF3E0), const Color(0xFFFB8C00));
      case 'returning':
        return ('반납중', const Color(0xFFFFF8E1), const Color(0xFFF9A825));
      case 'returned':
        return ('반납완료', const Color(0xFFE8F5E9), const Color(0xFF43A047));
      case 'confirmed':
        return ('이용대기', DanjiColors.skyLight, DanjiColors.buttonBlue);
      case 'pending':
        return ('대기', const Color(0xFFF2F4F6), DanjiColors.textSecondary);
      case 'completed':
        return ('완료', const Color(0xFFE8F5E9), const Color(0xFF2E7D32));
      case 'cancelled':
        return ('취소', const Color(0xFFF2F4F6), DanjiColors.textSecondary);
      default:
        return (status, const Color(0xFFF2F4F6), DanjiColors.textSecondary);
    }
  }
}

String _renterPhoneLabel(Map<String, dynamic> row) {
  final phone = _str(row, 'renter_phone');
  if (phone != null && phone != '미등록') return phone;
  return '미등록';
}

String? _str(Map<String, dynamic> row, String key) {
  final v = row[key];
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

String? _reservationId(Map<String, dynamic> row) =>
    _str(row, 'reservation_id') ?? _str(row, 'id');

String _status(Map<String, dynamic> row) =>
    _str(row, 'status')?.toLowerCase() ?? '';

bool _isConflictRisk(Map<String, dynamic> row) {
  final v = row['is_conflict_risk'];
  return v == true || v == 'true' || v == 1;
}

bool _isStuckReservation(Map<String, dynamic> row) {
  final status = _status(row);
  if (status != 'in_use' && status != 'returning') {
    return false;
  }

  final anchor = _parseDate(row['end_at']) ??
      _parseDate(row['rental_started_at']) ??
      _parseDate(row['updated_at']);
  if (anchor == null) return false;

  return DateTime.now().isAfter(anchor.add(const Duration(hours: 24)));
}

DateTime? _parseDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value.toLocal();
  return DateTime.tryParse(value.toString())?.toLocal();
}
