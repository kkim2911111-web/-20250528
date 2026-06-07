import 'package:flutter/material.dart';

import '../theme/danji_colors.dart';
import '../utils/rental_contract_parser.dart';

const _headerDark = Color(0xFF1E2A3A);
const _circledNumbers = ['①', '②', '③', '④', '⑤'];

/// 계약서 구조화 카드 UI
class RentalContractCardView extends StatelessWidget {
  final RentalContractParsed parsed;

  const RentalContractCardView({super.key, required this.parsed});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DarkHeader(parsed: parsed),
        const SizedBox(height: 16),
        _SectionCard(
          title: '예약 정보',
          icon: Icons.event_note_outlined,
          children: [
            _InfoRow(label: '차량', value: parsed.vehicleName),
            _InfoRow(label: '예약번호', value: parsed.reservationId),
            _InfoRow(label: '대여기간', value: parsed.rentalPeriod),
          ],
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: '임차인',
          icon: Icons.person_outline,
          children: [
            _InfoRow(label: '성명', value: parsed.renterName),
            _InfoRow(label: '연락처', value: parsed.renterPhone),
            _InfoRow(label: '면허번호', value: parsed.licenseNumber),
          ],
        ),
        if (parsed.hasSecondDriver) ...[
          const SizedBox(height: 12),
          _SectionCard(
            title: '제2운전자',
            icon: Icons.group_outlined,
            children: [
              _InfoRow(label: '성명', value: parsed.secondDriverName),
              _InfoRow(label: '면허번호', value: parsed.secondDriverLicense),
            ],
          ),
        ],
        const SizedBox(height: 12),
        _FeeSection(parsed: parsed),
        const SizedBox(height: 12),
        _InsuranceSection(parsed: parsed),
        const SizedBox(height: 12),
        _ComplianceSection(items: parsed.complianceItems),
        const SizedBox(height: 12),
        _AgreementFooter(parsed: parsed),
      ],
    );
  }
}

class _DarkHeader extends StatelessWidget {
  final RentalContractParsed parsed;

  const _DarkHeader({required this.parsed});

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (parsed.reservationId.isNotEmpty) '계약번호 ${parsed.reservationId}',
      if (parsed.generatedAt != null) parsed.generatedAt!,
    ].join(' · ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        color: _headerDark,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _headerDark.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            parsed.headerBrand,
            style: const TextStyle(
              color: Color(0xFF9BB5D4),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '자동차 대여 계약서',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              meta,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DanjiColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DanjiColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: DanjiColors.buttonBlue),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: DanjiColors.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String? value;

  const _InfoRow({required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    final display = value?.trim().isNotEmpty == true ? value!.trim() : '—';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                color: DanjiColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              display,
              style: const TextStyle(
                color: DanjiColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeeSection extends StatelessWidget {
  final RentalContractParsed parsed;

  const _FeeSection({required this.parsed});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '요금',
      icon: Icons.payments_outlined,
      children: [
        _FeeRow(
          label: '정가',
          amount: parsed.originalPrice,
          emphasized: false,
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Divider(height: 1, color: DanjiColors.border),
        ),
        _FeeRow(
          label: '결제금액',
          amount: parsed.paidPrice,
          emphasized: true,
        ),
        for (final line in parsed.extraFeeLines) ...[
          const SizedBox(height: 8),
          Text(
            line,
            style: const TextStyle(
              color: DanjiColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ],
    );
  }
}

class _FeeRow extends StatelessWidget {
  final String label;
  final String? amount;
  final bool emphasized;

  const _FeeRow({
    required this.label,
    this.amount,
    required this.emphasized,
  });

  @override
  Widget build(BuildContext context) {
    final display = amount?.trim().isNotEmpty == true ? amount!.trim() : '—';
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            color: DanjiColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          display,
          style: TextStyle(
            color: emphasized ? DanjiColors.buttonBlue : DanjiColors.textPrimary,
            fontSize: emphasized ? 18 : 15,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _InsuranceSection extends StatelessWidget {
  final RentalContractParsed parsed;

  const _InsuranceSection({required this.parsed});

  static const _keys = ['대인', '대물', '자손', '자차'];

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '보험',
      icon: Icons.shield_outlined,
      children: [
        if (parsed.insuranceIntro != null) ...[
          Text(
            parsed.insuranceIntro!,
            style: const TextStyle(
              color: DanjiColors.textSecondary,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
        ],
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.45,
          children: [
            for (final key in _keys)
              _InsuranceTile(
                label: key,
                value: parsed.insuranceCoverage[key] ?? '—',
              ),
          ],
        ),
        for (final note in parsed.insuranceNotes) ...[
          const SizedBox(height: 12),
          Text(
            note,
            style: const TextStyle(
              color: DanjiColors.textSecondary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }
}

class _InsuranceTile extends StatelessWidget {
  final String label;
  final String value;

  const _InsuranceTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DanjiColors.skyLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DanjiColors.border.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: DanjiColors.buttonBlue,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: DanjiColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _ComplianceSection extends StatelessWidget {
  final List<String> items;

  const _ComplianceSection({required this.items});

  @override
  Widget build(BuildContext context) {
    final list = items.isEmpty
        ? const ['계약 준수사항을 확인해주세요.']
        : items;

    return _SectionCard(
      title: '준수사항',
      icon: Icons.fact_check_outlined,
      children: [
        for (var i = 0; i < list.length && i < _circledNumbers.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _circledNumbers[i],
                  style: const TextStyle(
                    color: DanjiColors.buttonBlue,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    list[i],
                    style: const TextStyle(
                      color: DanjiColors.textPrimary,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AgreementFooter extends StatelessWidget {
  final RentalContractParsed parsed;

  const _AgreementFooter({required this.parsed});

  @override
  Widget build(BuildContext context) {
    final agreedAt = parsed.generatedAt ?? '—';
    final name = parsed.renterName?.trim().isNotEmpty == true
        ? parsed.renterName!.trim()
        : '—';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DanjiColors.skyLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DanjiColors.buttonBlue.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '동의 확인',
            style: TextStyle(
              color: DanjiColors.buttonBlue,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          _InfoRow(label: '동의일시', value: agreedAt),
          _InfoRow(label: '임차인', value: name),
        ],
      ),
    );
  }
}
