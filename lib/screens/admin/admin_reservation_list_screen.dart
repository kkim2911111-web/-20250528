import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/admin_service.dart';
import '../../theme/danji_colors.dart';
import '../../widgets/danji_app_bar.dart';
import '../../widgets/section_card.dart';

enum _ReservationFilter { all, inUse, waiting, conflict }

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

  _ReservationFilter _filter = _ReservationFilter.all;
  Future<List<Map<String, dynamic>>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = _admin.getAdminReservationsWithConflict();
    });
  }

  List<Map<String, dynamic>> _applyFilter(List<Map<String, dynamic>> rows) {
    switch (_filter) {
      case _ReservationFilter.inUse:
        return rows.where((r) => _status(r) == 'in_use').toList();
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
        return rows;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: const DanjiAppBar(title: '예약 관리'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChip(
                    label: '전체',
                    selected: _filter == _ReservationFilter.all,
                    onTap: () => setState(() => _filter = _ReservationFilter.all),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: '대여중',
                    selected: _filter == _ReservationFilter.inUse,
                    onTap: () =>
                        setState(() => _filter = _ReservationFilter.inUse),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: '이용대기',
                    selected: _filter == _ReservationFilter.waiting,
                    onTap: () =>
                        setState(() => _filter = _ReservationFilter.waiting),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: '충돌위험',
                    selected: _filter == _ReservationFilter.conflict,
                    onTap: () =>
                        setState(() => _filter = _ReservationFilter.conflict),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: DanjiColors.buttonBlue,
              onRefresh: () async => _reload(),
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _future,
                builder: (context, snap) {
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
                  final filtered = _applyFilter(snap.data ?? []);
                  if (filtered.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 80),
                        Center(child: Text('표시할 예약이 없습니다.')),
                      ],
                    );
                  }
                  return ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      return _ReservationCard(
                        row: filtered[index],
                        dateTime: _dateTime,
                        timeOnly: _timeOnly,
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? DanjiColors.buttonBlue : DanjiColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
  }
}

class _ReservationCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final DateFormat dateTime;
  final DateFormat timeOnly;

  const _ReservationCard({
    required this.row,
    required this.dateTime,
    required this.timeOnly,
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
          ],
      ),
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
      case 'confirmed':
        return ('이용대기', DanjiColors.skyLight, DanjiColors.buttonBlue);
      case 'pending':
        return ('대기', const Color(0xFFF2F4F6), DanjiColors.textSecondary);
      default:
        return (status, const Color(0xFFF2F4F6), DanjiColors.textSecondary);
    }
  }
}

String? _str(Map<String, dynamic> row, String key) {
  final v = row[key];
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

String _status(Map<String, dynamic> row) =>
    _str(row, 'status')?.toLowerCase() ?? '';

bool _isConflictRisk(Map<String, dynamic> row) {
  final v = row['is_conflict_risk'];
  return v == true || v == 'true' || v == 1;
}

DateTime? _parseDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value.toLocal();
  return DateTime.tryParse(value.toString())?.toLocal();
}
