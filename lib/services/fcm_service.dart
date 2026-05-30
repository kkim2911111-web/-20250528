import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/firebase_config.dart';
import '../supabase_client.dart';

/// FCM 백그라운드 핸들러 (모바일 전용)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kIsWeb) return;
  await _ensureFirebaseInitialized();
}

Future<void> _ensureFirebaseInitialized() async {
  if (kIsWeb) return;
  if (Firebase.apps.isNotEmpty) return;

  if (defaultTargetPlatform == TargetPlatform.android) {
    await Firebase.initializeApp(options: FirebaseConfig.androidOptions);
  } else {
    await Firebase.initializeApp();
  }
}

class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  bool _initialized = false;

  /// Flutter Web은 push service 제한 — FCM 비활성화
  bool get isSupported => !kIsWeb;

  Future<void> initialize() async {
    if (!isSupported) {
      debugPrint('[fcm] skipped on web (push service not available)');
      return;
    }
    if (_initialized) return;

    try {
      await _ensureFirebaseInitialized();
      FirebaseMessaging.onBackgroundMessage(
        firebaseMessagingBackgroundHandler,
      );
      final messaging = FirebaseMessaging.instance;
      await messaging.setAutoInitEnabled(true);
      _initialized = true;
    } catch (e, st) {
      debugPrint('[fcm] initialize failed (non-fatal): $e\n$st');
    }
  }

  Future<void> registerForCurrentUser() async {
    if (!isSupported || !_initialized) return;
    if (!isSupabaseInitialized || supabaseOrNull?.auth.currentUser == null) {
      return;
    }

    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      final allowed = settings.authorizationStatus ==
              AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;

      if (!allowed) return;

      final token = await messaging.getToken();
      if (token == null || token.isEmpty) return;

      await _saveToken(token);

      messaging.onTokenRefresh.listen((newToken) async {
        await _saveToken(newToken);
      });
    } catch (e, st) {
      debugPrint('[fcm] register failed (non-fatal): $e\n$st');
    }
  }

  String get _platformLabel {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      default:
        return defaultTargetPlatform.name;
    }
  }

  Future<void> _saveToken(String token) async {
    if (!isSupabaseInitialized || supabaseOrNull?.auth.currentUser == null) {
      return;
    }

    try {
      await supabase.rpc('upsert_fcm_token', params: {
        'p_token': token,
        'p_platform': _platformLabel,
      });
    } on PostgrestException catch (e) {
      debugPrint('[fcm] token save failed: ${e.message}');
    }
  }

  void listenForegroundMessages(void Function(RemoteMessage) onMessage) {
    if (!isSupported || !_initialized) return;
    FirebaseMessaging.onMessage.listen(onMessage);
  }
}
