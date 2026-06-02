import 'package:flutter/material.dart';

import '../models/my_page_profile.dart';
import '../services/my_page_service.dart';
import '../theme/danji_colors.dart';
import '../widgets/danji_app_bar.dart';

/// 입주민 인증 정보 — 읽기 전용
class ResidentInfoReadOnlyScreen extends StatefulWidget {
  final MyPageProfile profile;

  const ResidentInfoReadOnlyScreen({super.key, required this.profile});

  @override
  State<ResidentInfoReadOnlyScreen> createState() =>
      _ResidentInfoReadOnlyScreenState();
}

class _ResidentInfoReadOnlyScreenState extends State<ResidentInfoReadOnlyScreen> {
  final _myPage = MyPageService();
  late MyPageProfile _profile;
  String? _complexName;
  var _loading = true;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final fresh = await _myPage.fetchProfile();
      if (!mounted) return;
      setState(() {
        _profile = fresh;
        _complexName = fresh.residentComplexName;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: const DanjiAppBar(
        title: '주민인증',
        showBack: true,
        light: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('정보를 불러오지 못했습니다.\n$_loadError'),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _refresh,
                          child: const Text('다시 시도'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                  children: [
                    const Text(
                      '입주민 인증 정보는 가입 시 등록되며 수정할 수 없습니다.\n'
                      '변경이 필요하면 고객센터로 문의해주세요.',
                      style: TextStyle(
                        color: DanjiColors.textSecondary,
                        height: 1.45,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _ReadOnlyField(
                      label: '아파트',
                      value: _apartmentLabel(_profile, _complexName),
                    ),
                    _ReadOnlyField(
                      label: '동/호',
                      value: _profile.dongHoLabel ?? '-',
                    ),
                    _ReadOnlyField(
                      label: '인증 상태',
                      value: _profile.isResidentComplete
                          ? '인증완료'
                          : _profile.hasResidentRegistration
                              ? '승인대기'
                              : '미등록',
                      valueColor: _profile.isResidentComplete
                          ? DanjiColors.buttonBlue
                          : _profile.hasResidentRegistration
                              ? DanjiColors.accentRed
                              : DanjiColors.textMuted,
                    ),
                  ],
                ),
    );
  }

  static String _apartmentLabel(MyPageProfile profile, String? loadedName) {
    final name = loadedName?.trim() ?? profile.residentComplexName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return '-';
  }
}

class _ReadOnlyField extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _ReadOnlyField({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: DanjiColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: DanjiColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? DanjiColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
