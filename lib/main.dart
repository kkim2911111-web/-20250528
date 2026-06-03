import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'config/supabase_config.dart';
import 'config/payment_config.dart';
import 'routing/app_routes.dart';
import 'services/fcm_service.dart';
import 'services/supabase_bootstrap.dart';
import 'supabase_client.dart';
import 'theme/danji_colors.dart';
import 'theme/danji_theme.dart';
import 'theme/danji_typography.dart';

/// 시스템 글자 크기 설정과 무관하게 앱 UI 비율 유지 (textScaleFactor 1.0)
Widget _lockAppTextScale(BuildContext context, Widget? child) {
  final mq = MediaQuery.of(context);
  return MediaQuery(
    data: mq.copyWith(textScaler: TextScaler.noScaling),
    child: child ?? const SizedBox.shrink(),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.loadEnv();
  PaymentConfig.logLoadedKey();
  if (kIsWeb) {
    usePathUrlStrategy();
    captureLaunchUri();
  }
  runApp(const BootstrapApp());
}

/// Supabase 초기화 + 단일 MaterialApp (라우트 유지)
class BootstrapApp extends StatefulWidget {
  const BootstrapApp({super.key});

  @override
  State<BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<BootstrapApp> {
  final _navKey = GlobalKey<NavigatorState>();
  bool _ready = false;
  String? _initWarning;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    String? warning;

    try {
      if (!SupabaseConfig.isConfigured) {
        warning = 'SUPABASE_URL 또는 SUPABASE_ANON_KEY가 비어 있습니다.\n'
            'assets/.env 또는 --dart-define를 확인해주세요.';
      } else {
        await initializeSupabaseWithRetry();
        debugPrint('[bootstrap] Supabase initialized: ${SupabaseConfig.url}');
      }
    } catch (e, st) {
      debugPrint('[bootstrap] Supabase init failed: $e\n$st');
      warning = '서버 연결 실패: $e\n'
          '네트워크 연결 후 앱을 다시 실행하거나 잠시 후 다시 시도해주세요.\n'
          'URL: ${SupabaseConfig.url}';
    }

    try {
      await initializeDateFormatting('ko_KR', null);
    } catch (e) {
      debugPrint('[bootstrap] date formatting init failed: $e');
    }

    if (isSupabaseInitialized && !_isPaymentReturnUrl()) {
      try {
        await FcmService.instance.initialize();
        if (supabase.auth.currentSession != null) {
          await FcmService.instance.registerForCurrentUser();
        }
      } catch (e) {
        debugPrint('[bootstrap] FCM init skipped: $e');
      }
    }

    if (mounted) {
      setState(() {
        _ready = true;
        _initWarning = warning;
      });
    }
  }

  bool _isPaymentReturnUrl() {
    if (!kIsWeb) return false;
    final route = webInitialRoute();
    return isPaymentSuccessPath(route) || isPaymentFailPath(route);
  }

  @override
  Widget build(BuildContext context) {
    // Supabase 초기화 전 AppEntry/AuthGate가 supabase에 접근하지 않도록 대기
    if (!_ready) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: '단지카',
        theme: DanjiTheme.light,
        builder: _lockAppTextScale,
        home: const _BootstrapLoadingScreen(),
      );
    }

    final mobileHome = isSupabaseInitialized
        ? const AppEntry()
        : _BootstrapErrorScreen(
            message: _initWarning ??
                '서버 연결에 실패했습니다.\n네트워크 연결을 확인한 뒤 앱을 다시 실행해주세요.',
          );

    return MaterialApp(
      navigatorKey: _navKey,
      debugShowCheckedModeBanner: false,
      title: '단지카',
      theme: DanjiTheme.light,
      // Android/iOS: home 진입 / Web: URL 라우팅
      home: kIsWeb ? null : mobileHome,
      initialRoute: kIsWeb ? webInitialRoute() : null,
      onGenerateRoute: kIsWeb ? onGenerateRoute : null,
      onUnknownRoute: kIsWeb ? onUnknownRoute : null,
      onGenerateInitialRoutes: kIsWeb ? generateInitialRoutes : null,
      builder: (context, child) {
        Widget content = _lockAppTextScale(context, child);
        content = DefaultTextStyle(
          style: DanjiTypography.bodyRegular,
          child: content,
        );

        if (_initWarning != null && isSupabaseInitialized) {
          content = Stack(
            fit: StackFit.expand,
            children: [
              content,
              Align(
                alignment: Alignment.topCenter,
                child: Material(
                  elevation: 1,
                  color: DanjiColors.accentRed.withValues(alpha: 0.12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: DanjiColors.accentRed,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _initWarning!,
                            style: const TextStyle(
                              color: DanjiColors.accentRed,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        if (_ready) {
          _registerFcmForegroundOnce();
        }

        return content;
      },
    );
  }

  bool _fcmForegroundRegistered = false;

  void _registerFcmForegroundOnce() {
    if (_fcmForegroundRegistered || !FcmService.instance.isSupported) return;
    _fcmForegroundRegistered = true;
    FcmService.instance.listenForegroundMessages((message) {
      final title = message.notification?.title;
      if (title == null) return;
      final ctx = _navKey.currentContext;
      if (ctx == null) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text(title)),
      );
    });
  }
}

class _BootstrapLoadingScreen extends StatelessWidget {
  const _BootstrapLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: DanjiColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: DanjiColors.buttonBlue),
            SizedBox(height: 16),
            Text(
              '단지카 시작 중...',
              style: DanjiTypography.secondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _BootstrapErrorScreen extends StatelessWidget {
  final String message;

  const _BootstrapErrorScreen({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DanjiColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.wifi_off_rounded,
                size: 48,
                color: DanjiColors.accentRed,
              ),
              const SizedBox(height: 16),
              Text(
                '서버 연결 실패',
                style: DanjiTypography.subtitleLarge.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: DanjiTypography.bodyRegular.copyWith(
                  color: DanjiColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
