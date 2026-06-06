import 'package:flutter/material.dart';

import '../../models/license_review_item.dart';
import '../../models/staff_profile.dart';
import '../../services/admin_service.dart';
import '../../theme/danji_colors.dart';
import '../../widgets/admin_scaffold.dart';
import '../../widgets/section_card.dart';

class AdminLicenseReviewScreen extends StatefulWidget {
  final StaffProfile profile;

  const AdminLicenseReviewScreen({super.key, required this.profile});

  @override
  State<AdminLicenseReviewScreen> createState() =>
      _AdminLicenseReviewScreenState();
}

class _AdminLicenseReviewScreenState extends State<AdminLicenseReviewScreen> {
  final _admin = AdminService();
  Future<List<LicenseReviewItem>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = _admin.fetchLicenseReviews();
    });
  }

  Future<void> _approve(LicenseReviewItem item) async {
    try {
      await _admin.reviewLicense(
        userId: item.userId,
        approved: true,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${item.fullName ?? '입주민'} 면허 승인 완료')),
        );
        _reload();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  Future<void> _reject(LicenseReviewItem item) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('면허 거절'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: '거절 사유',
              hintText: '예: 면허증 사진이 흐릿합니다',
            ),
            maxLines: 2,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('거절'),
            ),
          ],
        );
      },
    );

    if (reason == null) return;

    try {
      await _admin.reviewLicense(
        userId: item.userId,
        approved: false,
        rejectionReason: reason.isEmpty ? '면허 정보 확인 불가' : reason,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('면허 거절 처리되었습니다')),
        );
        _reload();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      appBar: AppBar(
        title: const Text('면허 심사'),
        backgroundColor: DanjiColors.background,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<LicenseReviewItem>>(
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
                    child: Text('목록을 불러오지 못했습니다.\n${snap.error}'),
                  ),
                ],
              );
            }

            final items = snap.data ?? [];
            final pending = items.where((e) => e.isPendingReview).toList();
            final approved = items.where((e) => e.licenseVerified).toList();

            if (items.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 80),
                  Center(child: Text('제출된 면허 정보가 없습니다')),
                ],
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                Text(
                  '심사 대기 ${pending.length}건 · 승인 ${approved.length}건',
                  style: const TextStyle(
                    color: DanjiColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                ...items.map((item) => _ReviewCard(
                      item: item,
                      onApprove: item.isPendingReview
                          ? () => _approve(item)
                          : null,
                      onReject: item.isPendingReview
                          ? () => _reject(item)
                          : null,
                    )),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final LicenseReviewItem item;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const _ReviewCard({
    required this.item,
    this.onApprove,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = item.licenseVerified
        ? const Color(0xFF43A047)
        : (item.licenseRejectionReason != null
            ? DanjiColors.accentRed
            : DanjiColors.buttonBlue);
    final statusLabel = item.licenseVerified
        ? '승인됨'
        : (item.licenseRejectionReason != null ? '거절됨' : '심사 대기');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.fullName ?? '이름 미등록',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${item.dongHoLabel} · ${item.phone ?? '-'}',
              style: const TextStyle(color: DanjiColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Text('면허번호: ${item.licenseNumber ?? '-'}'),
            Text('만료일: ${item.licenseExpiry ?? '-'}'),
            if (item.licenseRejectionReason != null) ...[
              const SizedBox(height: 6),
              Text(
                '거절 사유: ${item.licenseRejectionReason}',
                style: const TextStyle(color: DanjiColors.accentRed),
              ),
            ],
            if (onApprove != null || onReject != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (onReject != null)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onReject,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: DanjiColors.accentRed,
                          side: BorderSide(
                            color: DanjiColors.accentRed.withValues(alpha: 0.6),
                          ),
                        ),
                        child: const Text('거절'),
                      ),
                    ),
                  if (onReject != null && onApprove != null)
                    const SizedBox(width: 8),
                  if (onApprove != null)
                    Expanded(
                      child: FilledButton(
                        onPressed: onApprove,
                        style: FilledButton.styleFrom(
                          backgroundColor: DanjiColors.buttonBlue,
                        ),
                        child: const Text('승인'),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
