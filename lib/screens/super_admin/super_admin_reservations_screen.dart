import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/super_admin_models.dart';
import '../../services/super_admin_service.dart';
import '../../theme/danji_colors.dart';
import '../../utils/danji_snackbar.dart';
import '../../widgets/admin_scaffold.dart';
import '../../widgets/danji_app_bar.dart';
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
    return all.where((r) {
      if (_complexFilter != null &&
          _complexFilter!.isNotEmpty &&
          r.complexId != _complexFilter) {
        return false;
      }
      final start = r.startAt;
      if (start == null) return _filterDate == null;

      final local = start.toLocal();
      if (local.year != _year || local.month != _month) {
        return false;
      }
      if (_filterDate != null) {
        return local.year == _filterDate!.year &&
            local.month == _filterDate!.month &&
            local.day == _filterDate!.day;
      }
      return true;
    }).toList();
  }

  Future<void> _openDetail(SuperAdminReservation r) async {
    await showSuperAdminBottomSheet<void>(
      context,
      title: r.vehicleName,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('#${r.id}', style: const TextStyle(color: DanjiColors.textMuted, fontSize: 12)),
          const SizedBox(height: 6),
          Text('${r.complexName} · ${r.renterName}',
              style: const TextStyle(color: DanjiColors.textSecondary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              SuperAdminChip(label: r.status, color: DanjiColors.buttonBlue),
              SuperAdminChip(
                label: '₩${superAdminWon.format(r.totalPrice)}',
                color: SuperAdminUiColors.revenueSky,
              ),
            ],
          ),
          if (r.displayRentalStartAt != null || r.displayRentalEndAt != null) ...[
            const SizedBox(height: 8),
            Text(
              '${r.displayRentalStartAt != null ? superAdminDateTime.format(r.displayRentalStartAt!) : '-'} ~ '
              '${r.displayRentalEndAt != null ? superAdminDateTime.format(r.displayRentalEndAt!) : '-'}',
              style: const TextStyle(color: DanjiColors.textSecondary),
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await widget.service.forceCancelReservation(r.id);
                if (!mounted) return;
                await _reload();
              } catch (e) {
                if (mounted) DanjiSnackBar.show(context, friendlySuperAdminError(e));
              }
            },
            child: const Text('강제 반납'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await widget.service.forceCompleteReservation(r.id);
                if (!mounted) return;
                await _reload();
              } catch (e) {
                if (mounted) DanjiSnackBar.show(context, friendlySuperAdminError(e));
              }
            },
            style: superAdminPrimaryFabStyle,
            child: const Text('강제 완료'),
          ),
        ],
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
        return SuperAdminListCard(
          icon: Icons.event_note_outlined,
          title: '${r.vehicleName} · ${r.renterName}',
          subtitle: '${r.complexName} · ${r.status} · '
              '₩${superAdminWon.format(r.totalPrice)}',
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
