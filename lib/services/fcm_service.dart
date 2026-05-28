import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/firebase_config.dart';
import '../supabase_client.dart';

/// FCM 백그라운드 핸들러
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await _ensureFirebaseInitialized();
}

Future<void> _ensureFirebaseInitialized() async {
  if (Firebase.apps.isNotEmpty) return;

  if (kIsWeb) {
    await Firebase.initializeApp(options: FirebaseConfig.webOptions);
  } else if (defaultTargetPlatform == TargetPlatform.android) {
    await Firebase.initializeApp(options: FirebaseConfig.androidOptions);
  } else {
    await Firebase.initializeApp();
  }
}

class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    if (kIsWeb && !FirebaseConfig.isWebConfigured) return;

    await _ensureFirebaseInitialized();

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    final messaging = FirebaseMessaging.instance;
    await messaging.setAutoInitEnabled(true);

    _initialized = true;
  }

  Future<void> registerForCurrentUser() async {
    if (!_initialized) return;
    if (supabase.auth.currentUser == null) return;

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

    final token = kIsWeb
        ? await messaging.getToken(vapidKey: FirebaseConfig.vapidKey)
        : await messaging.getToken();
    if (token == null || token.isEmpty) return;

    await _saveToken(token);

    messaging.onTokenRefresh.listen((newToken) async {
      await _saveToken(newToken);
    });
  }

  String get _platformLabel {
    if (kIsWeb) return 'web';
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
    if (supabase.auth.currentUser == null) return;

    try {
      await supabase.rpc('upsert_fcm_token', params: {
        'p_token': token,
        'p_platform': _platformLabel,
      });
    } on PostgrestException catch (e) {
      debugPrint('FCM token save failed: ${e.message}');
    }
  }

  void listenForegroundMessages(void Function(RemoteMessage) onMessage) {
    if (!_initialized) return;
    FirebaseMessaging.onMessage.listen(onMessage);
  }
}
