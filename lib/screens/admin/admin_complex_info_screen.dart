import 'package:flutter/material.dart';

import '../../models/staff_profile.dart';
import '../../services/admin_service.dart';
import '../../theme/danji_colors.dart';
import '../../theme/danji_theme.dart';
import '../../widgets/danji_app_bar.dart';

/// 관리자 — 단지 사업자 정보 (complexes)
class AdminComplexInfoScreen extends StatefulWidget {
  final StaffProfile profile;

  const AdminComplexInfoScreen({super.key, required this.profile});

  @override
  State<AdminComplexInfoScreen> createState() => _AdminComplexInfoScreenState();
}

class _AdminComplexInfoScreenState extends State<AdminComplexInfoScreen> {
  final _admin = AdminService();
  final _businessName = TextEditingController();
  final _registrationNumber = TextEditingController();
  final _address = TextEditingController();
  final _representative = TextEditingController();
  final _phone = TextEditingController();

  AdminComplexBusinessInfo? _info;
  bool _loadingPage = true;
  bool _saving = false;
  String? _loadError;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _businessName.dispose();
    _registrationNumber.dispose();
    _address.dispose();
    _representative.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loadingPage = true;
      _loadError = null;
    });
    try {
      final info = await _admin.fetchComplexBusinessInfo();
      _applyToForm(info);
      if (!mounted) return;
      setState(() {
        _info = info;
        _loadingPage = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = friendlyAdminError(e);
        _loadingPage = false;
      });
    }
  }

  void _applyToForm(AdminComplexBusinessInfo info) {
    _businessName.text = info.businessName ?? '';
    _registrationNumber.text = info.businessRegistrationNumber ?? '';
    _address.text = info.businessAddress ?? '';
    _representative.text = info.businessRepresentative ?? '';
    _phone.text = info.businessPhone ?? '';
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _saveError = null;
    });

    try {
      final complexId = _info?.complexId ?? widget.profile.complexId;
      final updated = await _admin.updateComplexBusinessInfo(
        AdminComplexBusinessInfo(
          complexId: complexId,
          complexName: _info?.complexName ?? widget.profile.complexName,
          businessName: _businessName.text.trim(),
          businessRegistrationNumber: _registrationNumber.text.trim(),
          businessAddress: _address.text.trim(),
          businessRepresentative: _representative.text.trim(),
          businessPhone: _phone.text.trim(),
        ),
      );
      if (!mounted) return;
      _applyToForm(updated);
      setState(() => _info = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('단지 정보가 저장되었습니다.')),
      );
    } catch (e) {
      setState(() => _saveError = friendlyAdminError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final complexLabel = _info?.complexName?.trim().isNotEmpty == true
        ? _info!.complexName!.trim()
        : (widget.profile.complexName?.trim().isNotEmpty == true
            ? widget.profile.complexName!.trim()
            : '단지');

    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: const DanjiAppBar(title: '단지 정보'),
      body: _loadingPage
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _loadError != null
              ? ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      _loadError!,
                      style: const TextStyle(color: DanjiColors.accentRed),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _load,
                      child: const Text('다시 시도'),
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      complexLabel,
                      style: const TextStyle(
                        color: DanjiColors.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '계약서 임대인 표시 및 사업자 정보에 사용됩니다.',
                      style: TextStyle(
                        color: DanjiColors.textSecondary,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _field('업체명', _businessName, hint: 'GT컴퍼니'),
                    const SizedBox(height: 12),
                    _field(
                      '사업자등록번호',
                      _registrationNumber,
                      hint: '123-45-67890',
                      keyboard: TextInputType.text,
                    ),
                    const SizedBox(height: 12),
                    _field(
                      '사업장 주소',
                      _address,
                      hint: '서울특별시 ...',
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    _field('대표자명', _representative, hint: '홍길동'),
                    const SizedBox(height: 12),
                    _field(
                      '대표 전화',
                      _phone,
                      hint: '02-1234-5678',
                      keyboard: TextInputType.phone,
                    ),
                    if (_saveError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _saveError!,
                        style: const TextStyle(color: DanjiColors.accentRed),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _saving ? null : _submit,
                      style: DanjiTheme.primaryButton.copyWith(
                        minimumSize: const WidgetStatePropertyAll(
                          Size.fromHeight(52),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('저장'),
                    ),
                  ],
                ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
    TextInputType? keyboard,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: DanjiColors.skyLight,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
