import 'package:firebase_core/firebase_core.dart';

/// Firebase 설정
/// - Web: dart-define / 기본 web 앱 값
/// - Android: android/app/google-services.json (Gradle plugin이 자동 연동)
class FirebaseConfig {
  // Web (danji-car)
  static const webProjectId = 'danji-car';
  static const authDomain = 'danji-car.firebaseapp.com';
  static const webStorageBucket = 'danji-car.firebasestorage.app';
  static const webMessagingSenderId = '62581668986';
  static const vapidKey =
      'BC7N_ELBP_nleQgMWAMKp61xCVGjsGFTzaas_Tz10SbDZC0lNXB4VtXgpfU0MV-Aw5qdYfWMlx1YwIteP4ySuQ4';

  static const apiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: 'AIzaSyBBkrtHDBYmclv6Rc_SBg6was-7MIaC2zc',
  );
  static const appId = String.fromEnvironment(
    'FIREBASE_APP_ID',
    defaultValue: '1:62581668986:web:4ce7ca737704d787f40fc3',
  );
  static const measurementId = String.fromEnvironment(
    'FIREBASE_MEASUREMENT_ID',
    defaultValue: 'G-Q1NQ36HH0Q',
  );

  // Android (google-services.json → danji-26a2f)
  static const androidApiKey = 'AIzaSyDtO1XXfdyNV44US-XmqREZLaahzdjQq5o';
  static const androidAppId =
      '1:623216691538:android:facea39c11109aaa24d28b';
  static const androidProjectId = 'danji-26a2f';
  static const androidStorageBucket = 'danji-26a2f.firebasestorage.app';
  static const androidMessagingSenderId = '623216691538';

  static bool get isWebConfigured => apiKey.isNotEmpty && appId.isNotEmpty;

  static FirebaseOptions get webOptions => FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        messagingSenderId: webMessagingSenderId,
        projectId: webProjectId,
        authDomain: authDomain,
        storageBucket: webStorageBucket,
        measurementId: measurementId,
      );

  static FirebaseOptions get androidOptions => FirebaseOptions(
        apiKey: androidApiKey,
        appId: androidAppId,
        messagingSenderId: androidMessagingSenderId,
        projectId: androidProjectId,
        storageBucket: androidStorageBucket,
      );
}
