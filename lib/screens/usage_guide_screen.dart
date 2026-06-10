import 'package:flutter/material.dart';

import '../theme/danji_colors.dart';
import '../widgets/danji_app_bar.dart';
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
          '· 대여 시작 1시간(60분) 전까지 앱에서 예약 취소가 가능합니다.\n'
          '· 취소 시 결제 금액은 전액 환불됩니다.\n'
          '· 사용한 쿠폰·포인트는 복구됩니다.\n'
          '· 대여 시작 1시간 이내에는 취소가 제한될 수 있습니다.',
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
          '· 24시간 이상 이용이 필요하면 일/월 단위 요금 탭을 선택하세요.\n'
          '· 일 단위: 최대 29일까지 앱에서 예약 가능합니다.\n'
          '· 월 단위: 최대 11개월까지 앱에서 예약 가능합니다.\n'
          '· 30일 이상·12개월 이상 장기 대여는「전화 문의」를 이용해 주세요.\n'
          '· 배달형 일/월 렌트 차량은 원하는 장소로 차량이 배달됩니다.',
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

  const _GuideNavTile({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DanjiColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: DanjiColors.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: DanjiColors.buttonBlue, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: DanjiColors.textPrimary,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: DanjiColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
