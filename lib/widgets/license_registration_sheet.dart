import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/license_service.dart';
import '../theme/danji_colors.dart';

/// 면허증 촬영 → OCR 자동입력 → 수정 → 제출(관리자 심사)
class LicenseRegistrationSheet extends StatefulWidget {
  final String initialNumber;
  final String initialExpiry;

  const LicenseRegistrationSheet({
    super.key,
    required this.initialNumber,
    required this.initialExpiry,
  });

  @override
  State<LicenseRegistrationSheet> createState() =>
      _LicenseRegistrationSheetState();
}

class _LicenseRegistrationSheetState extends State<LicenseRegistrationSheet> {
  final _service = LicenseService();
  late final TextEditingController _number;
  late final TextEditingController _expiry;

  XFile? _photo;
  bool _scanning = false;
  bool _saving = false;
  String? _error;
  String? _ocrHint;

  @override
  void initState() {
    super.initState();
    _number = TextEditingController(text: widget.initialNumber);
    _expiry = TextEditingController(text: widget.initialExpiry);
  }

  @override
  void dispose() {
    _number.dispose();
    _expiry.dispose();
    super.dispose();
  }

  Future<void> _scanLicense() async {
    setState(() {
      _scanning = true;
      _error = null;
      _ocrHint = null;
    });

    try {
      final result = await _service.captureAndRecognize();
      if (!mounted) return;

      if (result.image == null) {
        setState(() => _scanning = false);
        return;
      }

      _photo = result.image;
      final ocr = result.ocr;

      if (ocr != null && ocr.hasAnyField) {
        if (ocr.licenseNumber != null && ocr.licenseNumber!.isNotEmpty) {
          _number.text = ocr.licenseNumber!;
        }
        if (ocr.licenseExpiry != null && ocr.licenseExpiry!.isNotEmpty) {
          _expiry.text = ocr.licenseExpiry!;
        }
        _ocrHint = 'OCR로 일부 정보를 채웠습니다. 틀리면 직접 수정해주세요.';
      } else {
        _ocrHint = '자동 인식에 실패했습니다. 면허번호·만료일을 직접 입력해주세요.';
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _submit() async {
    if (_number.text.trim().isEmpty || _expiry.text.trim().isEmpty) {
      setState(() => _error = '면허번호와 만료일을 입력해주세요.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      String? photoPath;
      if (_photo != null) {
        photoPath = await _service.uploadPhoto(_photo!);
      }

      await _service.submitLicense(
        licenseNumber: _number.text,
        licenseExpiry: _expiry.text,
        photoPath: photoPath,
      );

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '면허정보 등록',
              style: TextStyle(
                color: DanjiColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '면허증을 촬영하면 번호·만료일을 자동 입력합니다.\n제출 후 관리자 승인이 필요합니다.',
              style: TextStyle(
                color: DanjiColors.textSecondary,
                height: 1.45,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _scanning || _saving ? null : _scanLicense,
              icon: _scanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.camera_alt_outlined),
              label: Text(_photo == null ? '면허증 촬영 (OCR)' : '다시 촬영'),
              style: OutlinedButton.styleFrom(
                foregroundColor: DanjiColors.buttonBlue,
                side: const BorderSide(color: DanjiColors.buttonBlue),
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            if (_photo != null) ...[
              const SizedBox(height: 8),
              Text(
                '사진 선택됨 · ${_photo!.name}',
                style: const TextStyle(
                  color: DanjiColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
            if (_ocrHint != null) ...[
              const SizedBox(height: 10),
              Text(
                _ocrHint!,
                style: TextStyle(
                  color: DanjiColors.buttonBlue.withValues(alpha: 0.9),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 16),
            _Field(label: '면허번호', controller: _number),
            const SizedBox(height: 10),
            _Field(
              label: '만료일',
              controller: _expiry,
              hint: '예: 2030-12-31',
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: DanjiColors.accentRed),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: DanjiColors.rentalBlue,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('제출 · 심사 요청'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;

  const _Field({
    required this.label,
    required this.controller,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: DanjiColors.skyLight,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
