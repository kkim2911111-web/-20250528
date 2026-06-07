import 'package:flutter/material.dart';

import '../../models/super_admin_models.dart';
import '../../services/super_admin_service.dart';
import '../../theme/danji_colors.dart';
import '../../utils/danji_snackbar.dart';
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
  Future<List<SuperAdminReservation>>? _future;
  String? _complexFilter;
  late int _year = DateTime.now().year;
  late int _month = DateTime.now().month;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => setState(() => _future = widget.service.fetchReservations());

  List<SuperAdminReservation> _filter(List<SuperAdminReservation> all) {
    return all.where((r) {
      if (_complexFilter != null && _complexFilter!.isNotEmpty && r.complexId != _complexFilter) {
        return false;
      }
      final start = r.startAt;
      if (start == null) return true;
      return start.year == _year && start.month == _month;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SuperAdminReservation>>(
      future: _future,
      builder: (context, snap) {
        final all = snap.data ?? [];
        final complexes = <String, String>{};
        for (final r in all) {
          complexes[r.complexId] = r.complexName;
        }
        final filtered = _filter(all);

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                children: [
                  SuperAdminPeriodFilter(
                    year: _year,
                    month: _month,
                    onYearChanged: (y) => setState(() => _year = y),
                    onMonthChanged: (m) => setState(() => _month = m),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    value: _complexFilter,
                    decoration: const InputDecoration(labelText: '단지 필터', isDense: true, border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('전체 단지')),
                      ...complexes.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))),
                    ],
                    onChanged: (v) => setState(() => _complexFilter = v),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => _reload(),
                child: snap.connectionState == ConnectionState.waiting
                    ? const Center(child: CircularProgressIndicator())
                    : filtered.isEmpty
                        ? ListView(children: const [SizedBox(height: 120), Center(child: Text('예약 없음'))])
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final r = filtered[i];
                              return SectionCard(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('#${r.id} · ${r.vehicleName}', style: const TextStyle(fontWeight: FontWeight.w800)),
                                    Text('${r.complexName} · ${r.renterName}', style: const TextStyle(fontSize: 12, color: DanjiColors.textSecondary)),
                                    Text('${r.status} · ₩${superAdminWon.format(r.totalPrice)}', style: const TextStyle(fontSize: 12)),
                                    if (r.startAt != null)
                                      Text(superAdminDateTime.format(r.startAt!), style: const TextStyle(fontSize: 11, color: DanjiColors.textMuted)),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton(
                                          onPressed: () async {
                                            try {
                                              await widget.service.forceCancelReservation(r.id);
                                              _reload();
                                            } catch (e) {
                                              if (mounted) DanjiSnackBar.show(context, friendlySuperAdminError(e));
                                            }
                                          },
                                          child: const Text('강제취소'),
                                        ),
                                        TextButton(
                                          onPressed: () async {
                                            try {
                                              await widget.service.forceCompleteReservation(r.id);
                                              _reload();
                                            } catch (e) {
                                              if (mounted) DanjiSnackBar.show(context, friendlySuperAdminError(e));
                                            }
                                          },
                                          child: const Text('강제완료'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
            ),
          ],
        );
      },
    );
  }
}
