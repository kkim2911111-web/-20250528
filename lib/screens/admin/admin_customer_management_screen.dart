import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/admin_customer.dart';
import '../../models/staff_profile.dart';
import '../../services/admin_service.dart';
import '../../theme/danji_colors.dart';
import '../../utils/danji_snackbar.dart';
import '../../utils/resident_display.dart';
import '../../widgets/admin_scaffold.dart';
import '../../widgets/danji_app_bar.dart';
import '../../widgets/section_card.dart';
import 'admin_customer_detail_screen.dart';

class AdminCustomerManagementScreen extends StatefulWidget {
  final StaffProfile profile;

  const AdminCustomerManagementScreen({super.key, required this.profile});

  @override
  State<AdminCustomerManagementScreen> createState() =>
      _AdminCustomerManagementScreenState();
}

class _AdminCustomerManagementScreenState
    extends State<AdminCustomerManagementScreen> {
  final _admin = AdminService();
  final _won = NumberFormat('#,###');
  final _date = DateFormat('yyyy.MM.dd');
  Future<List<AdminCustomer>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = _admin.fetchCustomers();
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
        _reload();
      }
    } catch (e) {
      if (mounted) DanjiSnackBar.show(context, friendlyAdminError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      appBar: const DanjiAppBar(title: '고객 관리'),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<AdminCustomer>>(
          future: _future,
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
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      final changed = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => AdminCustomerDetailScreen(
                            profile: widget.profile,
                            customer: c,
                          ),
                        ),
                      );
                      if (changed == true) _reload();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
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
                              if (c.isBlacklisted)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
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
                                ),
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
                            '대여 ${c.rentalCount}회 · '
                            '누적 ₩${_won.format(c.totalPayment)} · '
                            '마지막 이용 ${c.lastUsedAt != null ? _date.format(c.lastUsedAt!) : '-'}',
                            style: const TextStyle(
                              color: DanjiColors.textPrimary,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _toggleBlacklist(c),
                                  icon: Icon(
                                    c.isBlacklisted
                                        ? Icons.lock_open_outlined
                                        : Icons.block_outlined,
                                    size: 18,
                                  ),
                                  label: Text(
                                    c.isBlacklisted ? '블랙리스트 해제' : '블랙리스트 등록',
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: c.isBlacklisted
                                        ? DanjiColors.buttonBlue
                                        : const Color(0xFFD32F2F),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.chevron_right,
                                color: DanjiColors.textMuted,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
