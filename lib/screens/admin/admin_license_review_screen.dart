import 'package:flutter/material.dart';

import '../../models/license_review_item.dart';
import '../../models/staff_profile.dart';
import '../../services/admin_service.dart';
import '../../theme/danji_colors.dart';
import '../../widgets/admin_license_review_list.dart';
import '../../widgets/admin_scaffold.dart';
import 'admin_customer_hub_screen.dart';

/// 면허 심사 — 고객관리 허브로 이관. 알림·기존 진입 호환용 래퍼.
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

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      appBar: AppBar(
        title: const Text('면허 심사'),
        backgroundColor: DanjiColors.background,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(
                  builder: (_) => AdminCustomerHubScreen(
                    profile: widget.profile,
                    initialTab: AdminCustomerHubTab.license,
                  ),
                ),
              );
            },
            child: const Text('고객관리'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: AdminLicenseReviewList(
          admin: _admin,
          future: _future,
          onReload: _reload,
        ),
      ),
    );
  }
}
