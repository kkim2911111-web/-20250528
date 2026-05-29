import 'package:flutter/material.dart';

import '../theme/danji_colors.dart';
import '../widgets/danji_app_bar.dart';

class CustomerServiceScreen extends StatelessWidget {
  const CustomerServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: const DanjiAppBar(title: '고객센터'),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          _InfoCard(
            icon: Icons.phone_in_talk_outlined,
            title: '전화 문의',
            body: '1588-0000\n평일 09:00 ~ 18:00 (주말·공휴일 휴무)',
          ),
          SizedBox(height: 12),
          _InfoCard(
            icon: Icons.mail_outline,
            title: '이메일 문의',
            body: 'support@danjicar.co.kr\n영업일 기준 1~2일 내 답변',
          ),
          SizedBox(height: 12),
          _InfoCard(
            icon: Icons.info_outline,
            title: '안내',
            body:
                '예약·결제·환불·차량 이용 관련 문의는 '
                '예약 ID 또는 주문 ID를 함께 알려주시면 '
                '더 빠르게 도와드릴 수 있습니다.',
          ),
        ],
      ),
    );
  }
}

class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  static const _items = [
    (
      '예약은 어떻게 하나요?',
      '마이페이지 또는 홈에서 차량 예약을 선택한 뒤 '
          '날짜·시간·차량을 고르고 결제하면 예약이 확정됩니다.',
    ),
    (
      '예약 취소는 언제까지 가능한가요?',
      '대여 시작 1시간(60분) 전까지 예약 취소가 가능하며, '
          '결제 금액은 전액 환불됩니다.',
    ),
    (
      '운행 시작은 어떻게 하나요?',
      '내 예약에서 해당 예약의「운행시작」을 누르고 '
          '차량 사진·주행거리·주유 상태를 입력하면 됩니다.',
    ),
    (
      '입주민 인증이 필요한가요?',
      '네. 단지카는 입주민 전용 서비스로, '
          '초대코드와 동/호 인증·승인 후 예약할 수 있습니다.',
    ),
    (
      '결제 수단은 무엇인가요?',
      '카카오페이·토스페이·신용카드 등 토스페이먼츠를 통해 결제됩니다.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: const DanjiAppBar(title: '자주 묻는 질문'),
      body: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final item = _items[index];
          return _FaqTile(question: item.$1, answer: item.$2);
        },
      ),
    );
  }
}

class TermsPolicyScreen extends StatelessWidget {
  const TermsPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: DanjiColors.background,
        appBar: const DanjiAppBar(title: '약관 및 정책'),
        body: Column(
          children: [
            Material(
              color: DanjiColors.surface,
              child: TabBar(
                labelColor: DanjiColors.buttonBlue,
                unselectedLabelColor: DanjiColors.textMuted,
                indicatorColor: DanjiColors.buttonBlue,
                tabs: const [
                  Tab(text: '이용약관'),
                  Tab(text: '개인정보처리방침'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _PolicyBody(text: _termsOfService),
                  _PolicyBody(text: _privacyPolicy),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _termsOfService = '''
제1조 (목적)
본 약관은 단지카(이하 "서비스")의 이용과 관련하여 회사와 이용자 간 권리·의무를 규정합니다.

제2조 (서비스)
1. 서비스는 아파트 단지 입주민을 대상으로 공유 차량 예약·이용 기능을 제공합니다.
2. 입주민 인증 및 관리자 승인 후 예약 기능을 이용할 수 있습니다.

제3조 (예약 및 결제)
1. 이용자는 앱에서 차량·일시를 선택하고 결제하여 예약을 확정합니다.
2. 예약 취소는 대여 시작 1시간 전까지 가능하며, 환불 정책에 따릅니다.

제4조 (이용자의 의무)
1. 운전면허를 보유하고 교통법규를 준수해야 합니다.
2. 차량 파손·사고 발생 시 즉시 고객센터에 연락해야 합니다.

제5조 (면책)
천재지변·불가항력 등 회사의 귀책 없이 발생한 손해에 대해 회사는 법령이 허용하는 범위 내에서 책임을 제한할 수 있습니다.
''';

  static const _privacyPolicy = '''
1. 수집 항목
- 필수: 이메일, 이름, 휴대전화, 주소, 입주민 인증 정보(동/호), 면허 정보
- 결제: 결제 키, 주문 ID (카드 전체 번호는 저장하지 않음)

2. 이용 목적
- 회원 식별, 예약·결제·환불 처리, 고객 지원, 서비스 개선

3. 보관 기간
- 회원 탈퇴 또는 목적 달성 시 지체 없이 파기
- 관련 법령에 따라 일정 기간 보관할 수 있음

4. 제3자 제공
- 결제 처리: 토스페이먼츠
- 인프라: Supabase (데이터 저장)

5. 이용자 권리
- 개인정보 열람·정정·삭제를 고객센터를 통해 요청할 수 있습니다.
''';
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: DanjiColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DanjiColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: DanjiColors.buttonBlue, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: DanjiColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  body,
                  style: const TextStyle(
                    color: DanjiColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  final String question;
  final String answer;

  const _FaqTile({required this.question, required this.answer});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: DanjiColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DanjiColors.border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          iconColor: DanjiColors.buttonBlue,
          collapsedIconColor: DanjiColors.textMuted,
          title: Text(
            question,
            style: const TextStyle(
              color: DanjiColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                answer,
                style: const TextStyle(
                  color: DanjiColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PolicyBody extends StatelessWidget {
  final String text;

  const _PolicyBody({required this.text});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Text(
        text.trim(),
        style: const TextStyle(
          color: DanjiColors.textSecondary,
          height: 1.6,
          fontSize: 14,
        ),
      ),
    );
  }
}
