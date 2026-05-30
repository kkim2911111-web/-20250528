import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'config/supabase_config.dart';
import 'routing/app_routes.dart';
import 'services/fcm_service.dart';
import 'supabase_client.dart';
import 'theme/danji_colors.dart';
import 'theme/danji_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.loadEnv();
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
            '.env 또는 --dart-define를 확인해주세요.';
      } else {
        await Supabase.initialize(
          url: SupabaseConfig.url,
          anonKey: SupabaseConfig.anonKey,
          authOptions: const FlutterAuthClientOptions(
            authFlowType: AuthFlowType.pkce,
          ),
        );
        debugPrint('[bootstrap] Supabase initialized: ${SupabaseConfig.url}');
      }
    } catch (e, st) {
      debugPrint('[bootstrap] Supabase init failed: $e\n$st');
      warning = 'Supabase 연결 실패: $e\n'
          'URL: ${SupabaseConfig.url}\n'
          '.env의 SUPABASE_URL·SUPABASE_ANON_KEY를 확인해주세요.';
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
    return MaterialApp(
      navigatorKey: _navKey,
      debugShowCheckedModeBanner: false,
      title: '단지카',
      theme: DanjiTheme.light,
      initialRoute: webInitialRoute(),
      onGenerateRoute: onGenerateRoute,
      onUnknownRoute: onUnknownRoute,
      onGenerateInitialRoutes: generateInitialRoutes,
      builder: (context, child) {
        Widget content = child ?? const SizedBox.shrink();

        if (!_ready) {
          content = Stack(
            fit: StackFit.expand,
            children: [
              content,
              ColoredBox(
                color: DanjiColors.background.withValues(alpha: 0.92),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: DanjiColors.buttonBlue),
                      SizedBox(height: 16),
                      Text(
                        '단지카 시작 중...',
                        style: TextStyle(color: DanjiColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        } else if (_initWarning != null) {
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
