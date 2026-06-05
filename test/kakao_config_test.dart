import 'package:danjicar_app/config/kakao_config.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('KakaoConfig loads key from .env', () async {
    await dotenv.load(fileName: '.env', isOptional: true);

    expect(KakaoConfig.isConfigured, isTrue);
    expect(
      KakaoConfig.javascriptKey,
      'ebd5439dcc704240b47c0116c38ef755',
    );
    expect(KakaoConfig.keySource, anyOf('dart-define', '.env'));
    expect(KakaoConfig.maskedKey, 'ebd5439d...f755');
  });
}
