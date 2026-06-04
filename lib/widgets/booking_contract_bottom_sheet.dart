import 'package:flutter/material.dart';

import '../models/booking_contract_consent.dart';
import '../theme/danji_colors.dart';
import '../theme/danji_theme.dart';

/// 예약 결제 직전 — 제2운전자·준수사항 동의
class BookingContractBottomSheet extends StatefulWidget {
  const BookingContractBottomSheet({super.key});

  static Future<BookingContractConsent?> show(BuildContext context) {
    return showModalBottomSheet<BookingContractConsent>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const BookingContractBottomSheet(),
    );
  }

  static const complianceItems = [
    '본인은 유효한 운전면허를 보유하고 있으며, 음주·무면허·면허정지 상태에서 운전하지 않습니다.',
    '차량은 승인된 입주민 및 등록된 제2운전자만 운전할 수 있으며, 타인에게 양도·대여하지 않습니다.',
    '교통법규 및 도로교통법을 준수하고, 안전운전 의무를 다합니다.',
    '차량 내 흡연, 애완동물 동반(단지 규정 허용 시 제외), 불법 물품 적재를 하지 않습니다.',
    '사고·파손·분실 발생 시 즉시 고객센터에 연락하고, 보험·면책 규정에 따릅니다.',
    '주유 상태·주행거리·반납 시간을 확인하고, 지정 장소에 정해진 방식으로 반납합니다.',
    '서비스 이용약관·개인정보 처리방침·대여 계약 조건을 확인하였으며 이에 동의합니다.',
  ];

  @override
  State<BookingContractBottomSheet> createState() =>
      _BookingContractBottomSheetState();
}

class _BookingContractBottomSheetState extends State<BookingContractBottomSheet> {
  bool _addSecondDriver = false;
  bool _termsAgreed = false;
  final _secondName = TextEditingController();
  final _secondLicense = TextEditingController();

  @override
  void dispose() {
    _secondName.dispose();
    _secondLicense.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    if (!_termsAgreed) return false;
    if (!_addSecondDriver) return true;
    return _secondName.text.trim().isNotEmpty &&
        _secondLicense.text.trim().isNotEmpty;
  }

  void _submit() {
    if (!_canSubmit) return;
    Navigator.of(context).pop(
      BookingContractConsent(
        termsAgreed: true,
        addSecondDriver: _addSecondDriver,
        secondDriverName:
            _addSecondDriver ? _secondName.text.trim() : null,
        secondDriverLicense:
            _addSecondDriver ? _secondLicense.text.trim() : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        decoration: const BoxDecoration(
          color: DanjiColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: DanjiColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '대여 계약 동의',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: DanjiColors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CheckboxListTile(
                        value: _addSecondDriver,
                        onChanged: (v) =>
                            setState(() => _addSecondDriver = v ?? false),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text(
                          '제2운전자 추가 (선택)',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (_addSecondDriver) ...[
                        TextField(
                          controller: _secondName,
                          decoration: _fieldDeco('제2운전자 성명'),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _secondLicense,
                          decoration: _fieldDeco('제2운전자 면허번호'),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 12),
                      ],
                      const Text(
                        '준수사항',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: DanjiColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 200),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: DanjiColors.skyLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: DanjiColors.border),
                        ),
                        child: Scrollbar(
                          thumbVisibility: true,
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount:
                                BookingContractBottomSheet.complianceItems.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              return Text(
                                '${index + 1}. ${BookingContractBottomSheet.complianceItems[index]}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  height: 1.45,
                                  color: DanjiColors.textSecondary,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      CheckboxListTile(
                        value: _termsAgreed,
                        onChanged: (v) =>
                            setState(() => _termsAgreed = v ?? false),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text(
                          '위 내용을 확인하였으며 동의합니다',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: _canSubmit ? _submit : null,
                    style: DanjiTheme.primaryButton,
                    child: const Text('동의하고 결제하기'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDeco(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: DanjiColors.skyLight,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: DanjiColors.border),
      ),
    );
  }
}
