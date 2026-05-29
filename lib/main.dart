import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'routing/app_routes.dart';
import 'services/fcm_service.dart';
import 'supabase_client.dart';
import 'theme/danji_colors.dart';
import 'theme/danji_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    usePathUrlStrategy();
    // Supabase/세션 복구 전 결제 리다이렉트 URL 보존
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
  String? _error;

  @override
  void initState() {
    super.initState();
    _initSupabase();
  }

  Future<void> _initSupabase() async {
    try {
      await Supabase.initialize(
        url: 'https://knxkmngonkzchwelpdjn.supabase.co',
        anonKey: 'sb_publishable_Mg_xNFRdV1QoH_-m0IsKGQ_fZJbfl6t',
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
        ),
      );
      await initializeDateFormatting('ko_KR', null);

      if (!_isPaymentReturnUrl()) {
        await FcmService.instance.initialize();
        if (supabase.auth.currentSession != null) {
          await FcmService.instance.registerForCurrentUser();
        }
      }

      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  bool _isPaymentReturnUrl() {
    if (!kIsWeb) return false;
    final route = webInitialRoute();
    return isPaymentSuccessPath(route) || isPaymentFailPath(route);
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return StartupErrorApp(message: _error!);
    }

    return MaterialApp(
      navigatorKey: _navKey,
      debugShowCheckedModeBanner: false,
      title: '단지카',
      theme: DanjiTheme.light,
      // path만 initialRoute — 쿼리(?orderId=...)는 paymentQueryParams()로 분리
      initialRoute: webInitialRoute(),
      onGenerateRoute: onGenerateRoute,
      onUnknownRoute: onUnknownRoute,
      onGenerateInitialRoutes: generateInitialRoutes,
      builder: (context, child) {
        if (!_ready) {
          return Stack(
            fit: StackFit.expand,
            children: [
              if (child != null) child,
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
        }

        if (_ready) {
          _registerFcmForegroundOnce();
        }

        return child ?? const SizedBox.shrink();
      },
    );
  }

  bool _fcmForegroundRegistered = false;

  void _registerFcmForegroundOnce() {
    if (_fcmForegroundRegistered) return;
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

class StartupErrorApp extends StatelessWidget {
  final String message;

  const StartupErrorApp({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: DanjiColors.background,
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              'Supabase 초기화 실패\n\n$message',
              style: const TextStyle(color: DanjiColors.accentRed),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
