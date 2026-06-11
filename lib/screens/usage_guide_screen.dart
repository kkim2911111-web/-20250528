import 'package:flutter/material.dart';

import '../theme/danji_colors.dart';
import '../widgets/danji_app_bar.dart';
import '../widgets/rental_inquiry_button.dart';
import 'support_pages.dart';

class _GuideSection {
  final String title;
  final IconData icon;
  final String body;

  const _GuideSection({
    required this.title,
    required this.icon,
    required this.body,
  });
}

/// 이용안내 — 예약·대여·반납·정책 안내
class UsageGuideScreen extends StatelessWidget {
  final bool embedded;

  const UsageGuideScreen({super.key, this.embedded = false});

  static final _sections = [
    _GuideSection(
      title: '예약 방법',
      icon: Icons.event_available_outlined,
      body:
          '1. 홈 또는 예약 메뉴에서 원하는 날짜와 시간(또는 일/월 단위)을 선택합니다.\n'
          '2. 해당 시간에 이용 가능한 차량 목록에서 차량을 선택합니다.\n'
          '3. 쿠폰·포인트 적용 후 결제하면 예약이 확정됩니다.\n'
          '4. 예약 확정 후「내 예약」에서 일정을 확인할 수 있습니다.',
    ),
    _GuideSection(
      title: '대여 시작 방법',
      icon: Icons.directions_car_outlined,
      body:
          '1. 대여 시작은 예약 시작 시각 30분 전부터 가능합니다.\n'
          '2.「내 예약」→ 해당 예약의「대여하기」를 선택합니다.\n'
          '3. 안내에 따라 차량 외관·내부 사진을 촬영합니다.\n'
          '4. 주행거리·연료(또는 배터리) 상태를 입력합니다.\n'
          '5. 스마트키 탭에서 도어락을 해제하고 운행을 시작합니다.',
    ),
    _GuideSection(
      title: '반납 방법',
      icon: Icons.local_parking_outlined,
      body:
          '1. 지정 주차 구역에 차량을 주차합니다.\n'
          '2. 반납 화면에서 차량 상태 사진을 촬영합니다.\n'
          '3. 최종 주행거리와 연료(또는 배터리) 잔량을 입력합니다.\n'
          '4. 반납 완료 후 이용이 종료되며, 포인트가 적립될 수 있습니다.',
    ),
    _GuideSection(
      title: '취소 정책',
      icon: Icons.cancel_schedule_send_outlined,
      body:
          '· 대여 시작 전까지 앱에서 언제든 예약 취소가 가능합니다.\n'
          '· 카셰어링(시간): 출고 1시간 전까지 전액 환불, 이후 환불 없음.\n'
          '· 일·월 렌트: 출고 72시간 전 전액, 72~24시간 50%, 24시간 이내 환불 없음.\n'
          '· 환불 없이 취소해도 차량 슬롯은 해제됩니다.\n'
          '· 전액 환불 시에만 사용한 쿠폰·포인트가 복구됩니다.',
    ),
    _GuideSection(
      title: '포인트/쿠폰 사용 방법',
      icon: Icons.local_offer_outlined,
      body:
          '· 포인트는 5,000원 이상부터 사용할 수 있습니다.\n'
          '· 포인트·쿠폰 유효기간은 발급일로부터 1년입니다.\n'
          '· 예약 결제 단계에서 쿠폰 선택 및 포인트 사용이 가능합니다.\n'
          '· 반납 완료 시 결제 금액의 일부가 포인트로 적립됩니다(쿠폰·포인트 결제 제외).',
    ),
    _GuideSection(
      title: '장기 대여 안내',
      icon: Icons.date_range_outlined,
      body:
          '· 반납 일자를 시작일과 다른 날로 선택하면 자동으로 일/월 요금이 적용됩니다.\n'
          '· 하루든 한 달이든, 기간만 선택하시면 이용 가능한 차량과 요금이 표시됩니다.\n'
          '· 11개월을 초과하는 장기 대여는 전화로 문의해 주세요.\n'
          '· 배달형 렌트 차량은 예약하신 단지로 차량을 준비해 드립니다.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final topPad = embedded ? MediaQuery.of(context).padding.top : 0.0;

    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: embedded
          ? null
          : const DanjiAppBar(title: '이용안내', showBack: true, light: true),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, topPad + (embedded ? 16 : 20), 20, 28),
        children: [
          if (embedded) ...[
            const Text(
              '이용안내',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: DanjiColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '단지카 이용 방법을 안내해 드립니다.',
              style: TextStyle(
                fontSize: 14,
                color: DanjiColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
          ],
          const _GuideAccordionTile(
            title: '자동차사고 보험대차',
            icon: Icons.shield_outlined,
            body:
                '자동차 사고로 차량 이용이 필요할 때, 단지 내 보험대차 차량을 '
                '바로 예약·이용할 수 있습니다.\n'
                '보험사 대차 승인 후 전화 문의를 주시면 안내해 드립니다.',
          ),
          const SizedBox(height: 12),
          const RentalInquiryButton(),
          const SizedBox(height: 20),
          for (final section in _sections) ...[
            _GuideAccordionTile(
              title: section.title,
              icon: section.icon,
              body: section.body,
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 6),
          _GuideNavTile(
            title: '자주 묻는 질문',
            icon: Icons.help_outline,
            emphasized: true,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FaqScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _GuideAccordionTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final String body;

  const _GuideAccordionTile({
    required this.title,
    required this.icon,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: DanjiColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DanjiColors.border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
          iconColor: DanjiColors.buttonBlue,
          collapsedIconColor: DanjiColors.textMuted,
          leading: Icon(icon, color: DanjiColors.buttonBlue, size: 22),
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: DanjiColors.textPrimary,
            ),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                body,
                style: const TextStyle(
                  color: DanjiColors.textSecondary,
                  height: 1.55,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideNavTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final bool emphasized;

  const _GuideNavTile({
    required this.title,
    required this.icon,
    required this.onTap,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = emphasized ? const Color(0xFFE8F1FF) : DanjiColors.surface;
    final border = emphasized ? DanjiColors.buttonBlue : DanjiColors.border;
    final titleColor =
        emphasized ? DanjiColors.buttonBlue : DanjiColors.textPrimary;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: DanjiColors.buttonBlue, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: titleColor,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: emphasized
                    ? DanjiColors.buttonBlue
                    : DanjiColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
