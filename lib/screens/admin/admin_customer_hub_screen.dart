import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/admin_customer.dart';
import '../../models/license_review_item.dart';
import '../../models/resident_review_item.dart';
import '../../models/staff_profile.dart';
import '../../services/admin_service.dart';
import '../../theme/danji_colors.dart';
import '../../utils/danji_snackbar.dart';
import '../../utils/resident_display.dart';
import '../../utils/reservation_status_badge.dart';
import '../../widgets/admin_license_review_list.dart';
import '../../widgets/admin_scaffold.dart';
import '../../widgets/danji_app_bar.dart';
import '../../widgets/section_card.dart';
import 'admin_customer_detail_screen.dart';
import 'admin_resident_review_screen.dart';

enum AdminCustomerHubTab {
  residents,
  residentReview,
  license,
  usageHistory,
  blacklist,
}

class AdminCustomerHubScreen extends StatefulWidget {
  final StaffProfile profile;
  final AdminCustomerHubTab initialTab;

  const AdminCustomerHubScreen({
    super.key,
    required this.profile,
    this.initialTab = AdminCustomerHubTab.residents,
  });

  @override
  State<AdminCustomerHubScreen> createState() => _AdminCustomerHubScreenState();
}

class _AdminCustomerHubScreenState extends State<AdminCustomerHubScreen> {
  final _admin = AdminService();
  final _won = NumberFormat('#,###');
  final _date = DateFormat('yyyy.MM.dd');
  final _dateTime = DateFormat('yyyy.MM.dd HH:mm');

  Future<List<AdminCustomer>>? _customersFuture;
  Future<List<LicenseReviewItem>>? _licenseFuture;
  Future<List<ResidentReviewItem>>? _residentReviewFuture;
  Future<List<Map<String, dynamic>>>? _usageFuture;

  @override
  void initState() {
    super.initState();
    _reloadAll();
  }

  void _reloadAll() {
    setState(() {
      _customersFuture = _admin.fetchCustomers();
      _licenseFuture = _admin.fetchLicenseReviews();
      _residentReviewFuture = _admin.fetchResidentReviews();
      _usageFuture = _admin.getAdminCompletedReservations();
    });
  }

  void _reloadResidentReviews() {
    setState(() {
      _residentReviewFuture = _admin.fetchResidentReviews();
    });
  }

  void _reloadCustomers() {
    setState(() {
      _customersFuture = _admin.fetchCustomers();
    });
  }

  void _reloadLicense() {
    setState(() {
      _licenseFuture = _admin.fetchLicenseReviews();
    });
  }

  Future<void> _toggleBlacklist(AdminCustomer customer) async {
    final next = !customer.isBlacklisted;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(next ? '블랙리스트 등록' : '블랙리스트 해제'),
        content: Text(
          next
              ? '${customer.fullName} 고객을 블랙리스트에 등록하면 예약·결제가 제한됩니다. 계속할까요?'
              : '${customer.fullName} 고객의 블랙리스트를 해제할까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(next ? '등록' : '해제'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _admin.setCustomerBlacklist(
        userId: customer.userId,
        blacklisted: next,
      );
      if (mounted) {
        DanjiSnackBar.show(
          context,
          next ? '블랙리스트에 등록했습니다.' : '블랙리스트를 해제했습니다.',
        );
        _reloadCustomers();
      }
    } catch (e) {
      if (mounted) DanjiSnackBar.show(context, friendlyAdminError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      initialIndex: widget.initialTab.index,
      child: AdminScaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight + 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DanjiAppBar(title: '고객 관리'),
              Material(
                color: DanjiColors.background,
                child: TabBar(
                  isScrollable: true,
                  labelColor: DanjiColors.buttonBlue,
                  unselectedLabelColor: DanjiColors.textMuted,
                  indicatorColor: DanjiColors.buttonBlue,
                  labelStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  tabs: const [
                    Tab(text: '입주민'),
                    Tab(text: '입주민 심사'),
                    Tab(text: '면허심사'),
                    Tab(text: '이용이력'),
                    Tab(text: '블랙리스트'),
                  ],
                ),
              ),
            ],
          ),
        ),
        body: TabBarView(
          clipBehavior: Clip.hardEdge,
          children: [
            _ResidentsTab(
              future: _customersFuture,
              won: _won,
              profile: widget.profile,
              onReload: _reloadCustomers,
            ),
            RefreshIndicator(
              onRefresh: () async => _reloadResidentReviews(),
              child: AdminResidentReviewScreen(
                admin: _admin,
                future: _residentReviewFuture,
                onReload: _reloadResidentReviews,
              ),
            ),
            RefreshIndicator(
              onRefresh: () async => _reloadLicense(),
              child: AdminLicenseReviewList(
                admin: _admin,
                future: _licenseFuture,
                onReload: _reloadLicense,
              ),
            ),
            _UsageHistoryTab(future: _usageFuture, won: _won, dateTime: _dateTime),
            _BlacklistTab(
              future: _customersFuture,
              won: _won,
              date: _date,
              profile: widget.profile,
              onToggleBlacklist: _toggleBlacklist,
              onReload: _reloadCustomers,
            ),
          ],
        ),
      ),
    );
  }
}

class _ResidentsTab extends StatelessWidget {
  final Future<List<AdminCustomer>>? future;
  final NumberFormat won;
  final StaffProfile profile;
  final VoidCallback onReload;

  const _ResidentsTab({
    required this.future,
    required this.won,
    required this.profile,
    required this.onReload,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => onReload(),
      child: FutureBuilder<List<AdminCustomer>>(
        future: future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(friendlyAdminError(snap.error!)),
                ),
              ],
            );
          }

          final customers = snap.data ?? [];
          if (customers.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 80),
                Center(child: Text('등록된 입주민이 없습니다.')),
              ],
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: customers.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final c = customers[index];
              return SectionCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.fullName,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (c.isBlacklisted)
                        const _BlacklistChip(),
                    ],
                  ),
                  subtitle: Text(
                    '${c.phone.isNotEmpty ? c.phone : '연락처 미등록'} · ${c.unitLabel}\n'
                    '${ResidentDisplay.joinAndRentalLine(joinedAt: c.joinedAt, lastRentalAt: c.lastRentalAt)}\n'
                    '대여 ${c.rentalCount}회 · 누적 ₩${won.format(c.totalPayment)}',
                    style: const TextStyle(height: 1.45),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: DanjiColors.textMuted,
                  ),
                  onTap: () async {
                    final changed = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => AdminCustomerDetailScreen(
                          profile: profile,
                          customer: c,
                        ),
                      ),
                    );
                    if (changed == true) onReload();
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _BlacklistTab extends StatelessWidget {
  final Future<List<AdminCustomer>>? future;
  final NumberFormat won;
  final DateFormat date;
  final StaffProfile profile;
  final Future<void> Function(AdminCustomer) onToggleBlacklist;
  final VoidCallback onReload;

  const _BlacklistTab({
    required this.future,
    required this.won,
    required this.date,
    required this.profile,
    required this.onToggleBlacklist,
    required this.onReload,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => onReload(),
      child: FutureBuilder<List<AdminCustomer>>(
        future: future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(friendlyAdminError(snap.error!)),
                ),
              ],
            );
          }

          final customers =
              (snap.data ?? []).where((c) => c.isBlacklisted).toList();
          if (customers.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 80),
                Center(child: Text('블랙리스트 등록 고객이 없습니다.')),
              ],
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: customers.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final c = customers[index];
              return SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            c.fullName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const _BlacklistChip(),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${c.phone.isNotEmpty ? c.phone : '연락처 미등록'} · ${c.unitLabel}',
                      style: const TextStyle(
                        color: DanjiColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '대여 ${c.rentalCount}회 · 누적 ₩${won.format(c.totalPayment)}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => onToggleBlacklist(c),
                      icon: const Icon(Icons.lock_open_outlined, size: 18),
                      label: const Text('블랙리스트 해제'),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _UsageHistoryTab extends StatelessWidget {
  final Future<List<Map<String, dynamic>>>? future;
  final NumberFormat won;
  final DateFormat dateTime;

  const _UsageHistoryTab({
    required this.future,
    required this.won,
    required this.dateTime,
  });

  DateTime? _parse(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    return DateTime.tryParse(raw.toString());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(friendlyAdminError(snap.error!)),
              ),
            ],
          );
        }

        final rows = snap.data ?? [];
        if (rows.isEmpty) {
          return ListView(
            children: const [
              SizedBox(height: 80),
              Center(child: Text('이용 이력이 없습니다.')),
            ],
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final r = rows[index];
            final start = _parse(r['start_at']);
            final end = _parse(r['end_at']);
            final status = r['status']?.toString() ?? '';
            final isNoShow = r['is_no_show'] == true;
            final price = (r['total_price'] as num?)?.toInt() ?? 0;
            return SectionCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        r['vehicle_name']?.toString() ?? '차량',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    ReservationStatusBadge(
                      status: status,
                      isNoShow: isNoShow,
                    ),
                  ],
                ),
                subtitle: Text(
                  '${r['renter_name'] ?? '—'} · '
                  '${r['car_number'] ?? '번호 미등록'}\n'
                  '${start != null ? dateTime.format(start) : '-'}'
                  '${end != null ? ' ~ ${dateTime.format(end)}' : ''}\n'
                  '₩${won.format(price)}',
                  style: const TextStyle(height: 1.45),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _BlacklistChip extends StatelessWidget {
  const _BlacklistChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        '블랙리스트',
        style: TextStyle(
          color: Color(0xFFD32F2F),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
