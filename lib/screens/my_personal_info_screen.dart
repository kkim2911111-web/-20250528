import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/my_page_profile.dart';
import '../services/my_page_service.dart';
import '../theme/danji_colors.dart';
import '../widgets/danji_app_bar.dart';
import '../widgets/kakao_address_field.dart';

/// 마이페이지 → 개인정보 수정 (상세 필드는 이 화면에서만 노출)
class MyPersonalInfoScreen extends StatefulWidget {
  final MyPageProfile profile;

  const MyPersonalInfoScreen({super.key, required this.profile});

  @override
  State<MyPersonalInfoScreen> createState() => _MyPersonalInfoScreenState();
}

class _MyPersonalInfoScreenState extends State<MyPersonalInfoScreen> {
  final _service = MyPageService();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.profile.name ?? '');
    _phone = TextEditingController(text: widget.profile.phone ?? '');
    _address = TextEditingController(text: widget.profile.address ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty ||
        _phone.text.trim().isEmpty ||
        _address.text.trim().isEmpty) {
      setState(() {
        _error = '이름, 휴대전화, 주소를 모두 입력해주세요.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _service.saveBasicInfo(
        name: _name.text,
        phone: _phone.text,
        address: _address.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final snsLabel = widget.profile.linkedProviders.isEmpty
        ? '미연동'
        : widget.profile.linkedProviders
            .map(MyPageProfile.providerLabel)
            .join(', ');

    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: const DanjiAppBar(
        title: '개인정보 수정',
        showBack: true,
        light: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        children: [
          _Field(label: '이름', child: _input(_name)),
          _Field(
            label: '휴대전화',
            child: _input(
              _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ),
          _Field(
            label: '이메일',
            child: _readOnly(widget.profile.email ?? '-'),
          ),
          _Field(label: 'SNS 로그인 연동', child: _readOnly(snsLabel)),
          _Field(
            label: '주소',
            child: KakaoAddressField(
              controller: _address,
              decoration: InputDecoration(
                filled: true,
                fillColor: DanjiColors.surface,
                hintText: '탭하여 주소 검색',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              textStyle: const TextStyle(
                color: DanjiColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(
                color: DanjiColors.accentRed,
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: DanjiColors.buttonBlue,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: _saving
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    '저장',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _input(
    TextEditingController controller, {
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: const TextStyle(
        color: DanjiColors.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        filled: true,
        fillColor: DanjiColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _readOnly(String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: DanjiColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        value,
        style: const TextStyle(
          color: DanjiColors.textMuted,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final Widget child;

  const _Field({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: DanjiColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
