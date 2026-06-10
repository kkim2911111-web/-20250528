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
import '../../utils/rental_detail_navigation.dart';
import '../../widgets/section_card.dart';

class AdminCustomerDetailScreen extends StatefulWidget {
  final StaffProfile profile;
  final AdminCustomer customer;

  const AdminCustomerDetailScreen({
    super.key,
    required this.profile,
    required this.customer,
  });

  @override
  State<AdminCustomerDetailScreen> createState() =>
      _AdminCustomerDetailScreenState();
}

class _AdminCustomerDetailScreenState extends State<AdminCustomerDetailScreen> {
  final _admin = AdminService();
  final _won = NumberFormat('#,###');
  final _dateTime = DateFormat('yyyy.MM.dd HH:mm');
  late AdminCustomer _customer;
  Future<List<AdminCustomerReservation>>? _future;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;
    _reload();
  }

  void _reload() {
    setState(() {
      _future = _admin.fetchCustomerReservations(_customer.userId);
    });
  }

  Future<void> _toggleBlacklist() async {
    final next = !_customer.isBlacklisted;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(next ? '블랙리스트 등록' : '블랙리스트 해제'),
        content: Text(
          next
              ? '이 고객을 블랙리스트에 등록하면 예약·결제가 제한됩니다.'
              : '블랙리스트를 해제할까요?',
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
        userId: _customer.userId,
        blacklisted: next,
      );
      if (!mounted) return;
      setState(() {
        _customer = AdminCustomer(
          userId: _customer.userId,
          fullName: _customer.fullName,
          phone: _customer.phone,
          building: _customer.building,
          unit: _customer.unit,
          rentalCount: _customer.rentalCount,
          totalPayment: _customer.totalPayment,
          lastUsedAt: _customer.lastUsedAt,
          isBlacklisted: next,
          joinedAt: _customer.joinedAt,
          lastRentalAt: _customer.lastRentalAt,
        );
        _changed = true;
      });
      DanjiSnackBar.show(
        context,
        next ? '블랙리스트에 등록했습니다.' : '블랙리스트를 해제했습니다.',
      );
    } catch (e) {
      if (mounted) DanjiSnackBar.show(context, friendlyAdminError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: AdminScaffold(
        appBar: DanjiAppBar(
          title: _customer.fullName,
          showHome: false,
          onBack: () => Navigator.pop(context, _changed),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _customer.phone.isNotEmpty
                                ? _customer.phone
                                : '연락처 미등록',
                            style: const TextStyle(
                              color: DanjiColors.textSecondary,
                            ),
                          ),
                        ),
                        if (_customer.isBlacklisted)
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
                    const SizedBox(height: 4),
                    Text(
                      _customer.unitLabel,
                      style: const TextStyle(
                        color: DanjiColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      ResidentDisplay.joinAndRentalLine(
                        joinedAt: _customer.joinedAt,
                        lastRentalAt: _customer.lastRentalAt,
                      ),
                      style: const TextStyle(
                        color: DanjiColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '대여 ${_customer.rentalCount}회 · '
                      '누적 ₩${_won.format(_customer.totalPayment)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _toggleBlacklist,
                      icon: Icon(
                        _customer.isBlacklisted
                            ? Icons.lock_open_outlined
                            : Icons.block_outlined,
                      ),
                      label: Text(
                        _customer.isBlacklisted
                            ? '블랙리스트 해제'
                            : '블랙리스트 등록',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _customer.isBlacklisted
                            ? DanjiColors.buttonBlue
                            : const Color(0xFFD32F2F),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text(
                '예약 이력',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => _reload(),
                child: FutureBuilder<List<AdminCustomerReservation>>(
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

                    final rows = snap.data ?? [];
                    if (rows.isEmpty) {
                      return ListView(
                        children: const [
                          SizedBox(height: 40),
                          Center(child: Text('예약 이력이 없습니다.')),
                        ],
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final r = rows[index];
                        return SectionCard(
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            onTap: () => openStaffRentalDetail(
                              context,
                              reservationId: r.reservationId,
                              adminService: _admin,
                            ),
                            title: Text(
                              r.vehicleName,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              '${r.statusLabel} · '
                              '${r.carNumber ?? '번호 미등록'}\n'
                              '${r.startAt != null ? _dateTime.format(r.startAt!) : '-'}'
                              '${r.endAt != null ? ' ~ ${_dateTime.format(r.endAt!)}' : ''}\n'
                              '₩${_won.format(r.totalPrice)}',
                              style: const TextStyle(height: 1.45),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
