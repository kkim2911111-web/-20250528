import 'package:danjicar_app/config/kakao_config.dart';
import 'package:danjicar_app/models/my_page_profile.dart';
import 'package:danjicar_app/screens/my_personal_info_screen.dart';
import 'package:danjicar_app/widgets/kakao_address_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await dotenv.load(fileName: '.env', isOptional: true);
  });

  group('KakaoConfig', () {
    test('javascript key is configured', () {
      expect(KakaoConfig.isConfigured, isTrue);
      expect(
        KakaoConfig.javascriptKey,
        'ebd5439dcc704240b47c0116c38ef755',
      );
      expect(KakaoConfig.maskedKey, 'ebd5439d...f755');
    });
  });

  group('KakaoAddressField on screens', () {
    testWidgets('개인정보 수정 화면에 주소 검색 필드', (tester) async {
      final profile = MyPageProfile(
        email: 'test@example.com',
        name: '테스트',
        phone: '01012345678',
        address: '',
      );

      await tester.pumpWidget(
        MaterialApp(home: MyPersonalInfoScreen(profile: profile)),
      );

      expect(find.byType(KakaoAddressField), findsOneWidget);
      expect(find.text('탭하여 주소 검색'), findsOneWidget);
      expect(find.text('개인정보 수정'), findsOneWidget);
    });

    testWidgets('회원가입 온보딩용 주소 검색 필드', (tester) async {
      final address = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KakaoAddressField(
              controller: address,
              decoration: const InputDecoration(
                labelText: '주소',
                hintText: '탭하여 주소 검색',
              ),
            ),
          ),
        ),
      );

      expect(find.byType(KakaoAddressField), findsOneWidget);
      expect(find.text('주소'), findsOneWidget);
      address.dispose();
    });

    testWidgets('관리자 단지 정보용 사업장 주소 검색 필드', (tester) async {
      final address = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KakaoAddressField(
              controller: address,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '사업장 주소',
                hintText: '탭하여 주소 검색',
              ),
            ),
          ),
        ),
      );

      expect(find.byType(KakaoAddressField), findsOneWidget);
      expect(find.byIcon(Icons.search), findsOneWidget);
      address.dispose();
    });
  });
}
