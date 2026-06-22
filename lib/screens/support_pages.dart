import 'package:flutter/material.dart';

import '../theme/danji_colors.dart';
import '../utils/cancel_refund_policy.dart';
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
                '문의시 대여 차량번호 혹은 예약번호를 알려주시면 '
                '빠르게 도움드리겠습니다.',
          ),
        ],
      ),
    );
  }
}

enum _FaqCategory {
  bookingPayment,
  rentalReturn,
  insuranceAccident,
  pointCoupon,
}

class _FaqItem {
  final String question;
  final String answer;
  final _FaqCategory? category;

  const _FaqItem({
    required this.question,
    required this.answer,
    this.category,
  });
}

class FaqScreen extends StatefulWidget {
  /// 펼쳐서 표시할 질문 (예: 취소·환불 FAQ 직행)
  final String? initialExpandedQuestion;

  const FaqScreen({super.key, this.initialExpandedQuestion});

  @override
  State<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends State<FaqScreen> {
  static const _tabs = <(String, _FaqCategory?)>[
    ('전체', null),
    ('예약·결제', _FaqCategory.bookingPayment),
    ('대여·반납', _FaqCategory.rentalReturn),
    ('보험·사고', _FaqCategory.insuranceAccident),
    ('포인트·쿠폰', _FaqCategory.pointCoupon),
  ];

  static const _items = [
    _FaqItem(
      category: _FaqCategory.bookingPayment,
      question: '예약은 어떻게 하나요?',
      answer:
          '마이페이지 또는 홈에서 차량 예약을 선택한 뒤 '
          '날짜·시간·차량을 고르고 결제하면 예약이 확정됩니다.',
    ),
    _FaqItem(
      category: _FaqCategory.bookingPayment,
      question: CancelRefundDisplay.faqCancelQuestion,
      answer: CancelRefundDisplay.faqCancelAnswer,
    ),
    _FaqItem(
      category: _FaqCategory.bookingPayment,
      question: '결제 수단은 무엇인가요?',
      answer: '카카오페이·토스페이·신용카드 등 토스페이먼츠를 통해 결제됩니다.',
    ),
    _FaqItem(
      category: _FaqCategory.bookingPayment,
      question: '입주민 인증이 필요한가요?',
      answer:
          '네. 단지카는 입주민 전용 서비스로, '
          '초대코드와 동/호 인증·승인 후 예약할 수 있습니다.',
    ),
    _FaqItem(
      category: _FaqCategory.rentalReturn,
      question: '통행료·범칙금·주유비는 누가 부담하나요?',
      answer:
          '통행료, 범칙금, 과태료는 임차인 부담입니다. '
          '주유비도 임차인 부담입니다.',
    ),
    _FaqItem(
      category: _FaqCategory.rentalReturn,
      question: '대여 시작은 어떻게 하나요?',
      answer:
          '내 예약에서 해당 예약의「대여하기」를 누르고 '
          '차량 사진·주행거리·주유 상태를 입력하면 됩니다.',
    ),
    _FaqItem(
      category: _FaqCategory.rentalReturn,
      question: '대여 연장은 어떻게 하나요?',
      answer:
          '대여 중 화면의「연장하기」버튼을 이용합니다. '
          '동일 차량에 다음 예약이 없을 때만 연장할 수 있습니다.',
    ),
    _FaqItem(
      category: _FaqCategory.rentalReturn,
      question: '반납 지연 시 어떻게 되나요?',
      answer:
          '반납이 지연되면 지연된 시간을 1시간 단위로 올림 계산하여, '
          '예약하신 차량의 시간당 요금이 자동으로 청구됩니다.',
    ),
    _FaqItem(
      category: _FaqCategory.rentalReturn,
      question: '차량 내 분실물은 어떻게 하나요?',
      answer:
          '고객센터로 문의해 주세요. '
          '차량 내 분실물에 대한 책임은 이용자 본인에게 있습니다.',
    ),
    _FaqItem(
      category: _FaqCategory.rentalReturn,
      question: '계약서는 어디서 확인하나요?',
      answer:
          '마이페이지 → 이용내역 → 완료된 예약 카드 하단의 '
          '「계약서 보기」에서 확인할 수 있습니다.',
    ),
    _FaqItem(
      category: _FaqCategory.insuranceAccident,
      question: '사고 발생 시 어떻게 하나요?',
      answer:
          '즉시 고객센터에 연락해 주세요. '
          '회사 안내에 따라 보험 처리 절차를 진행합니다. '
          '음주·무면허 운전 시 보험이 적용되지 않습니다.',
    ),
    _FaqItem(
      category: _FaqCategory.pointCoupon,
      question: '포인트는 언제 적립되나요?',
      answer:
          '반납 완료 시 결제 금액의 5%가 적립됩니다. '
          '쿠폰·포인트를 사용한 결제는 적립되지 않으며, '
          '적립 포인트의 유효기간은 1년입니다.',
    ),
    _FaqItem(
      category: _FaqCategory.pointCoupon,
      question: '쿠폰·포인트는 환불되나요?',
      answer:
          '쿠폰·포인트는 현금 환불이 불가합니다. '
          '예약 취소 시 전액 환불되는 경우에만 사용한 쿠폰·포인트가 복구됩니다. '
          '부분 환불·환불 없음 취소 시에는 복구되지 않습니다.',
    ),
    _FaqItem(
      question: '이용 자격이 있나요?',
      answer:
          '만 26세 이상이며, 면허 취득 후 1년 이상 경과한 '
          '입주민 인증 회원만 이용할 수 있습니다.',
    ),
  ];

  _FaqCategory? _selectedCategory;

  List<_FaqItem> get _visibleItems {
    if (_selectedCategory == null) return _items;
    return _items
        .where((item) => item.category == _selectedCategory)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final visibleItems = _visibleItems;

    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: const DanjiAppBar(title: '자주 묻는 질문'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: [
                for (var i = 0; i < _tabs.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  _FaqCategoryChip(
                    label: _tabs[i].$1,
                    selected: _selectedCategory == _tabs[i].$2,
                    onTap: () => setState(() => _selectedCategory = _tabs[i].$2),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              itemCount: visibleItems.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = visibleItems[index];
                return _FaqTile(
                  question: item.question,
                  answer: item.answer,
                  initiallyExpanded:
                      widget.initialExpandedQuestion == item.question,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FaqCategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FaqCategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? DanjiColors.buttonBlue : DanjiColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? DanjiColors.buttonBlue : DanjiColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : DanjiColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class TermsPolicyScreen extends StatelessWidget {
  /// 0: 이용약관, 1: 개인정보처리방침, 2: 자동차대여약관
  final int initialTabIndex;

  const TermsPolicyScreen({super.key, this.initialTabIndex = 0});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: initialTabIndex.clamp(0, 2),
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
                labelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: const [
                  Tab(text: '이용약관'),
                  Tab(text: '개인정보처리방침'),
                  Tab(text: '자동차대여약관'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _PolicyBody(text: _termsOfService),
                  _PolicyBody(text: _privacyPolicy),
                  _PolicyBody(text: _carRentalTerms),
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
3. 만 26세 이상이며, 면허 취득 후 1년 이상 경과한 자만 이용할 수 있습니다.

제3조 (예약 및 결제)
1. 이용자는 앱에서 차량·일시를 선택하고 결제하여 예약을 확정합니다.
2. 예약 취소는 대여 시작 전까지 가능하며, 상품 유형별 환불 정책(카셰어링 1시간·렌트 72/24시간)에 따릅니다.
3. 회사의 귀책 사유(앱 오류 등)로 예약이 불이행된 경우, 결제 금액 전액을 환불합니다.
4. 통행료, 범칙금, 과태료 및 주유비는 임차인이 부담합니다.

제4조 (쿠폰·포인트)
1. 쿠폰·포인트의 유효기간은 발급일로부터 1년입니다.
2. 쿠폰·포인트는 현금 환불·양도·매매가 불가합니다.
3. 유효기간 경과·탈퇴·이용 정지 시 소멸될 수 있습니다.

제5조 (이용자의 의무)
1. 운전면허를 보유하고 교통법규를 준수해야 합니다.
2. 차량 파손·사고 발생 시 즉시 고객센터에 연락해야 합니다.
3. 계정의 양도·대여·공유를 금지합니다.
4. 타인 면허 도용, 허위 정보 기재 등 부정 이용 시 즉시 이용이 정지되며, 회사는 손해배상을 청구할 수 있습니다.

제6조 (이용 정지·탈퇴)
회사는 다음 각 호의 사유가 있는 경우 사전 통지 후 이용을 정지하거나 탈퇴 처리할 수 있습니다.
1. 약관·관련 법령 위반
2. 타인 명의·면허 도용, 허위 정보 등록
3. 계정 양도·공유
4. 미결제·연체, 부정 결제
5. 차량·서비스 운영을 현저히 방해하는 행위
6. 기타 회사가 합리적으로 이용 부적합하다고 판단하는 경우

제7조 (면책)
천재지변·불가항력 등 회사의 귀책 없이 발생한 손해에 대해 회사는 법령이 허용하는 범위 내에서 책임을 제한할 수 있습니다.

제8조 (지연손해금)
이용자가 회사에 대한 금전채무를 연체하는 경우, 연체일 다음 날부터 변제 완료일까지 연 15%의 비율로 계산한 지연손해금을 지급합니다.

제9조 (서비스 변경·중단)
1. 회사가 서비스의 전부 또는 일부를 중단·변경하는 경우, 사유·일시·내용을 앱 공지사항을 통해 최소 7일 전에 고지합니다.
2. 긴급한 시스템 장애·보안 사고·법령 준수 등 불가피한 경우에는 즉시 공지할 수 있으며, 사후 상세 내용을 안내합니다.

제10조 (준용·분쟁 해결)
1. 본 약관에 명시되지 않은 자동차 대여 관련 사항은 공정거래위원회 자동차대여 표준약관을 준용합니다.
2. 소비자분쟁해결기준에 따릅니다.
3. 서비스 이용과 관련한 분쟁은 회사 소재지 관할 법원(인천지방법원)을 전속 관할 법원으로 합니다.
''';

  static const _privacyPolicy = '''
1. 수집 항목
- 필수: 이메일, 이름, 휴대전화, 주소, 입주민 인증 정보(동/호), 면허 정보
- 결제: 결제 키, 주문 ID (카드 전체 번호는 저장하지 않음)
- 위치: 차량 GPS 위치, 이용자 앱 위치 (대여·반납 시)

2. 이용 목적
- 회원 식별, 예약·결제·환불 처리, 고객 지원, 서비스 개선
- 차량 위치 확인, 대여·반납·안전 관리, 분실·도난 대응

3. 보관 기간
- 회원 탈퇴 또는 목적 달성 시 지체 없이 파기
- 관련 법령에 따라 일정 기간 보관할 수 있음
- 위치 정보: 대여 종료 후 1년

4. 제3자 제공
- 결제 처리: 토스페이먼츠
- 데이터 저장·인프라: Supabase

5. 이용자 권리
- 개인정보 열람·정정·삭제를 고객센터를 통해 요청할 수 있습니다.
- 위치정보에 대해서도 이용자 요청 시 지체 없이 삭제·처리를 중단합니다.

6. 위치기반서비스 이용 동의
- 단지카는 위치정보의 보호 및 이용 등에 관한 법률 제15조에 따라 차량 GPS 위치 추적 및 대여·반납 시 이용자 앱 위치 확인을 위해 위치기반서비스를 이용합니다.
- 수집 항목: 차량 GPS 위치, 이용자 앱 위치 (대여·반납 시)
- 보관 기간: 대여 종료 후 1년
- 위치정보는 차량 운행·반납 확인, 안전 관리, 분실·도난 대응 목적으로만 사용합니다.
- 위치기반서비스 이용에 동의하지 않을 경우, 일부 서비스(차량 대여·반납·스마트키 등) 이용이 제한될 수 있습니다.
- 이용자는 언제든지 위치정보 수집·이용 동의를 철회하고 삭제를 요청할 수 있습니다.
- 위치정보 수집·이용·제공 사실 확인 자료는 관련 법령에 따라 보관합니다.
''';

  static const _carRentalTerms = '''
단지카 자동차대여약관

제1조(목적·플랫폼 성격)
① GT컴퍼니가 운영하는 단지카 플랫폼을 통해 아파트 단지 내 차량 공유를 중개함에 있어 이용자와 회사 간의 권리·의무를 규정합니다.
② 단지카는 차량 공유 중개 플랫폼이며, 차량의 직접 소유자가 아닙니다.
③ 차량 소유 사업자와 이용자 간 분쟁이 발생한 경우, 단지카는 중개 서비스 제공 범위 내에서만 책임을 부담합니다.

제2조(이용 자격)
① 본인 명의 운전면허 소지자
② 해당 아파트 단지 입주민 인증 완료자
③ 본인 명의 결제수단 등록자
④ 만 26세 이상인 자

제3조(보험)
① 등록 차량은 자동차종합보험(대인·대물·자손)에 가입되어 있습니다.
② 대인: 무한 / 대물: 2,000만원 / 자손: 1,500만원
③ 자차: 가입(보험증권별 차량보상 설정금액)
④ 수리비 50만원 미만: 전액 본인 부담(제조사 서비스센터 견적 참조)
⑤ 수리비 50만원 이상: 면책금 50만원 납부 후 보험처리
⑥ 음주·무면허 운전 시 보험이 적용되지 않으며, 발생 손해는 전액 본인이 부담합니다.

제4조(이용 조건)
① 주행거리 제한 없음 (단지 내 공유 차량 특성상)
② 통행료, 범칙금, 과태료는 임차인 부담입니다.
③ 주유비는 임차인 부담입니다.
④ 대여 중 타인에게 차량을 양도·전대할 수 없습니다.
⑤ 해외 운전 및 차량 개조·튜닝을 금지합니다.
⑥ 반납 시 차량 사진 촬영은 필수이며, 분쟁 예방을 위해 반납 전후 상태를 기록합니다.
⑦ 반납 위치는 지정 주차 구역이며, 지정 구역 외 반납은 불가합니다.
⑧ 반납 시 배터리 잔량 20% 미만일 경우 충전 서비스비 10,000원을 청구합니다.

제5조(반납·지연)
① 반납이 지연된 경우, 지연된 시간은 1시간 단위로 올림하여 산정하며, 예약하신 차량의 시간당 요금이 자동으로 청구됩니다.
② 반납 지연으로 인한 추가 손해가 발생한 경우, 별도 배상을 청구할 수 있습니다.
③ 중도반납(조기반납)이란 대여 시작(출고) 이후 예약 종료 시각 이전에 반납하는 경우를 말하며, 카셰어링·일 렌트·월 렌트 등 모든 상품에 공통 적용됩니다.
④ 중도반납(조기반납) 시 이미 결제된 잔여 이용 기간에 해당하는 요금은 환불되지 않습니다. 미사용 기간에 대한 일할 계산·요금 환급을 제공하지 않습니다.

제6조(고객의 의무)
① 음주·무면허·고의사고 시 보험처리 불가
② 계약자 본인만 운전 가능(제2임차인 등록 시 해당 운전자 포함)
③ 흡연 적발 시 150,000원, 반려동물 오염 시 150,000원 청구
④ GPS 위치추적 및 시동차단 장치 임의 훼손 금지
⑤ 차량 내 분실물에 대한 책임은 이용자 본인에게 있으며, 회사는 분실물 보관·배상 책임을 지지 않습니다.

제7조(차량 훼손)
기존 손상 외 새로운 스크래치·파손이 발생한 경우, 수리비 실비를 청구합니다.

제8조(사고 처리)
① 사고 발생 시 즉시 회사 고객센터에 연락하고, 회사가 안내하는 보험 처리 절차에 따라야 합니다.
② 가해 사고와 피해 사고는 각각 보험사·경찰 신고 절차에 따라 구분 처리합니다.
③ 보험 접수·현장 출동·수리 등 후속 조치는 회사 및 보험사 안내에 따릅니다.

제9조(회사의 책임 한계·면책)
① 회사는 차량 공유 중개 서비스를 제공하며, 차량 자체의 하자로 인한 손해는 차량 소유자가 책임을 집니다.
② 이용자의 법규 위반으로 인한 사고는 회사가 책임지지 않습니다.
③ 천재지변, 전쟁, 정전, 통신 장애 등 불가항력으로 인한 손해에 대해 회사는 면책됩니다.
④ 정기 점검·안전 점검이 필요한 경우, 사전 공지 후 일시적으로 대여가 중단될 수 있습니다.

제10조(분쟁 해결)
본 약관에 관한 분쟁은 회사 소재지 관할 법원을 전속 관할로 합니다.
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
  final bool initiallyExpanded;

  const _FaqTile({
    required this.question,
    required this.answer,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DanjiColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: DanjiColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
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
