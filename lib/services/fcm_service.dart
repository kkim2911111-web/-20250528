import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/firebase_config.dart';
import '../supabase_client.dart';
import 'fcm_navigation_service.dart';

/// FCM 백그라운드 핸들러 (모바일 전용)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kIsWeb) return;
  await _ensureFirebaseInitialized();
  debugPrint('[fcm:bg] ${message.messageId} data=${message.data}');
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

  static const _androidChannelId = 'danjicar_high_importance';
  static const _androidChannelName = '단지카 알림';

  final _localNotifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _listenersRegistered = false;
  bool _tokenRefreshListenerSet = false;

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

      await _initLocalNotifications();

      final messaging = FirebaseMessaging.instance;
      await messaging.setAutoInitEnabled(true);

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      _initialized = true;
      _registerMessageListeners();
    } catch (e, st) {
      debugPrint('[fcm] initialize failed (non-fatal): $e\n$st');
    }
  }

  Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final decoded = jsonDecode(payload);
          if (decoded is Map) {
            FcmNavigationService.handleData(
              Map<String, dynamic>.from(decoded),
            );
          }
        } catch (_) {}
      },
    );

    if (defaultTargetPlatform == TargetPlatform.android) {
      final plugin = _localNotifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await plugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _androidChannelId,
          _androidChannelName,
          description: '예약·대여 알림',
          importance: Importance.high,
        ),
      );
    }
  }

  void _registerMessageListeners() {
    if (_listenersRegistered) return;
    _listenersRegistered = true;

    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(FcmNavigationService.handleRemoteMessage);

    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        FcmNavigationService.handleRemoteMessage(message);
      }
    });
  }

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    final title = notification?.title ?? message.data['title']?.toString();
    final body = notification?.body ?? message.data['body']?.toString();
    if (title == null || title.isEmpty) return;

    final payload = jsonEncode(message.data);

    await _localNotifications.show(
      message.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannelId,
          _androidChannelName,
          channelDescription: '예약·대여 알림',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  Future<void> registerForCurrentUser() async {
    if (!isSupported) return;
    if (!_initialized) {
      await initialize();
    }
    if (!_initialized) {
      debugPrint('[fcm] register skipped: initialize failed');
      return;
    }
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

      if (!allowed) {
        debugPrint(
          '[fcm] notification permission denied: ${settings.authorizationStatus}',
        );
        return;
      }

      final token = await messaging.getToken();
      if (token == null || token.isEmpty) {
        debugPrint('[fcm] getToken returned empty');
        return;
      }

      await _saveToken(token);

      if (!_tokenRefreshListenerSet) {
        _tokenRefreshListenerSet = true;
        messaging.onTokenRefresh.listen((newToken) async {
          await _saveToken(newToken);
        });
      }
    } catch (e, st) {
      debugPrint('[fcm] register failed (non-fatal): $e\n$st');
    }
  }

  /// 로그아웃 시 서버·기기 토큰 정리
  Future<void> clearForSignOut() async {
    if (!isSupported || !isSupabaseInitialized) return;
    if (supabaseOrNull?.auth.currentUser == null) return;

    try {
      final messaging = FirebaseMessaging.instance;
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await supabase.rpc('delete_my_fcm_tokens', params: {
          'p_token': token,
        });
      }
      await messaging.deleteToken();
      debugPrint('[fcm] token cleared on signOut');
    } catch (e) {
      debugPrint('[fcm] clear on signOut failed (non-fatal): $e');
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
      debugPrint('[fcm] token saved (${_platformLabel})');
    } on PostgrestException catch (e) {
      debugPrint('[fcm] token save failed: ${e.message}');
    }
  }

  /// 레거시 — main.dart에서 호출하던 API (로컬 알림으로 대체)
  void listenForegroundMessages(void Function(RemoteMessage) onMessage) {
    if (!isSupported || !_initialized) return;
    FirebaseMessaging.onMessage.listen(onMessage);
  }
}
