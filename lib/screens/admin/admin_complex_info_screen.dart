import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/staff_profile.dart';
import '../../services/admin_service.dart';
import '../../theme/danji_colors.dart';
import '../../theme/danji_theme.dart';
import '../../widgets/admin_scaffold.dart';
import '../../widgets/danji_app_bar.dart';
import '../../widgets/kakao_address_field.dart';

/// 관리자 — 단지 사업자 정보 (complexes)
class AdminComplexInfoScreen extends StatefulWidget {
  final StaffProfile profile;

  const AdminComplexInfoScreen({super.key, required this.profile});

  @override
  State<AdminComplexInfoScreen> createState() => _AdminComplexInfoScreenState();
}

class _AdminComplexInfoScreenState extends State<AdminComplexInfoScreen> {
  final _admin = AdminService();
  final _picker = ImagePicker();
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
  String? _licenseDisplayUrl;
  XFile? _pendingLicenseImage;
  Uint8List? _pendingLicenseBytes;

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
      final displayUrl =
          await _admin.resolveBusinessLicenseDisplayUrl(info.businessLicenseUrl);
      _applyToForm(info);
      if (!mounted) return;
      setState(() {
        _info = info;
        _licenseDisplayUrl = displayUrl;
        _pendingLicenseImage = null;
        _pendingLicenseBytes = null;
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

  Future<void> _pickBusinessLicense() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      _pendingLicenseImage = picked;
      _pendingLicenseBytes = bytes;
      _licenseDisplayUrl = null;
    });
  }

  void _openLicenseFullScreen() {
    if (_pendingLicenseBytes != null) {
      _showLicenseViewer(Image.memory(_pendingLicenseBytes!, fit: BoxFit.contain));
      return;
    }
    final url = _licenseDisplayUrl;
    if (url == null || url.isEmpty) return;
    _showLicenseViewer(Image.network(url, fit: BoxFit.contain));
  }

  void _showLicenseViewer(Widget image) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (ctx) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: const Text('사업자등록증'),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: image,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _saveError = null;
    });

    try {
      final complexId = _info?.complexId ?? widget.profile.complexId;
      var licenseUrl = _info?.businessLicenseUrl;

      if (_pendingLicenseImage != null) {
        licenseUrl = await _admin.uploadBusinessLicense(
          complexId: complexId,
          image: _pendingLicenseImage!,
        );
      }

      final updated = await _admin.updateComplexBusinessInfo(
        AdminComplexBusinessInfo(
          complexId: complexId,
          complexName: _info?.complexName ?? widget.profile.complexName,
          businessName: _businessName.text.trim(),
          businessRegistrationNumber: _registrationNumber.text.trim(),
          businessAddress: _address.text.trim(),
          businessRepresentative: _representative.text.trim(),
          businessPhone: _phone.text.trim(),
          businessLicenseUrl: licenseUrl,
        ),
      );

      final displayUrl = await _admin.resolveBusinessLicenseDisplayUrl(
        updated.businessLicenseUrl,
      );

      if (!mounted) return;
      _applyToForm(updated);
      setState(() {
        _info = updated;
        _licenseDisplayUrl = displayUrl;
        _pendingLicenseImage = null;
        _pendingLicenseBytes = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('단지 정보가 저장되었습니다.')),
      );
    } catch (e) {
      setState(() => _saveError = friendlyAdminError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildBusinessLicenseSection() {
    final hasPreview =
        _pendingLicenseBytes != null ||
        (_licenseDisplayUrl != null && _licenseDisplayUrl!.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '사업자등록증',
          style: TextStyle(
            color: DanjiColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '단지 사업자 확인용 서류입니다.',
          style: TextStyle(
            color: DanjiColors.textSecondary,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        if (hasPreview)
          GestureDetector(
            onTap: _openLicenseFullScreen,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                height: 180,
                color: DanjiColors.skyLight,
                child: _pendingLicenseBytes != null
                    ? Image.memory(
                        _pendingLicenseBytes!,
                        fit: BoxFit.cover,
                      )
                    : Image.network(
                        _licenseDisplayUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: DanjiColors.textSecondary,
                            size: 40,
                          ),
                        ),
                      ),
              ),
            ),
          )
        else
          Container(
            width: double.infinity,
            height: 120,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: DanjiColors.skyLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: DanjiColors.border),
            ),
            child: const Text(
              '등록된 사업자등록증이 없습니다.',
              style: TextStyle(color: DanjiColors.textSecondary),
            ),
          ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _saving ? null : _pickBusinessLicense,
          icon: const Icon(Icons.photo_library_outlined, size: 20),
          label: Text(hasPreview ? '사진 변경' : '사진 등록'),
          style: OutlinedButton.styleFrom(
            foregroundColor: DanjiColors.brandBlue,
            side: const BorderSide(color: DanjiColors.brandBlue),
            minimumSize: const Size.fromHeight(44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final complexLabel = _info?.complexName?.trim().isNotEmpty == true
        ? _info!.complexName!.trim()
        : (widget.profile.complexName?.trim().isNotEmpty == true
            ? widget.profile.complexName!.trim()
            : '단지');

    return AdminScaffold(
      appBar: const DanjiAppBar(title: '사업자 정보'),
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
                    KakaoAddressField(
                      controller: _address,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: '사업장 주소',
                        hintText: '탭하여 주소 검색',
                        filled: true,
                        fillColor: DanjiColors.skyLight,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
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
                    const SizedBox(height: 20),
                    _buildBusinessLicenseSection(),
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
