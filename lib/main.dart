import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'resident_profile_screen.dart';
import 'screens/booking_route.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/payment_fail_screen.dart';
import 'screens/payment_success_screen.dart';
import 'services/fcm_service.dart';
import 'supabase_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    usePathUrlStrategy();
  }
  runApp(const BootstrapApp());
}

/// 웹에서 Supabase 초기화가 느려도 즉시 로딩 UI를 보여줍니다.
class BootstrapApp extends StatefulWidget {
  const BootstrapApp({super.key});

  @override
  State<BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<BootstrapApp> {
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
      await FcmService.instance.initialize();
      if (supabase.auth.currentSession != null) {
        await FcmService.instance.registerForCurrentUser();
      }
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return StartupErrorApp(message: _error!);
    }
    if (!_ready) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Color(0xFF071826),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(height: 16),
                Text(
                  '단지카 시작 중...',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return const DanjiCarApp();
  }
}

class StartupErrorApp extends StatelessWidget {
  final String message;

  const StartupErrorApp({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF071826),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              'Supabase 초기화 실패\n\n$message',
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class DanjiCarApp extends StatefulWidget {
  const DanjiCarApp({super.key});

  @override
  State<DanjiCarApp> createState() => _DanjiCarAppState();
}

class _DanjiCarAppState extends State<DanjiCarApp> {
  final _navKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navKey,
      debugShowCheckedModeBanner: false,
      title: '단지카',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF071826),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4DA3FF),
          brightness: Brightness.dark,
        ),
      ),
      home: const AppEntry(),
      routes: {
        '/home': (_) => const AuthGate(),
        '/booking': (_) => const BookingRoute(),
        '/payment/success': (_) => PaymentSuccessScreen(
              queryParams: Uri.base.queryParameters,
            ),
        '/payment/fail': (_) => PaymentFailScreen(
              queryParams: Uri.base.queryParameters,
            ),
      },
    );
  }
}

/// 웹 결제 리다이렉트 URL 처리 + 기본 진입점
class AppEntry extends StatelessWidget {
  const AppEntry({super.key});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      final path = Uri.base.path.replaceAll(RegExp(r'/+$'), '');
      if (path.endsWith('/payment/success')) {
        return PaymentSuccessScreen(queryParams: Uri.base.queryParameters);
      }
      if (path.endsWith('/payment/fail')) {
        return PaymentFailScreen(queryParams: Uri.base.queryParameters);
      }
    }
    return const AuthGate();
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    supabase.auth.onAuthStateChange.listen((data) async {
      if (data.session != null) {
        await FcmService.instance.registerForCurrentUser();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = supabase.auth;

    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, _) {
        final session = auth.currentSession;

        if (session == null) {
          return const LoginScreen();
        }

        return const ResidentGate();
      },
    );
  }
}

/// 로그인 후 입주민 승인 여부에 따라 화면 분기
class ResidentGate extends StatelessWidget {
  const ResidentGate({super.key});

  static const _bg = Color(0xFF071826);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ResidentProfile?>(
      stream: ResidentRepository().watchMyProfile(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Scaffold(
            backgroundColor: _bg,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snap.hasError && snap.data == null) {
          return Scaffold(
            backgroundColor: _bg,
            appBar: AppBar(
              backgroundColor: _bg,
              title: const Text('오류'),
            ),
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '입주민 정보 조회 실패: ${snap.error}',
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          );
        }

        final profile = snap.data;
        if (profile == null || profile.approved != true) {
          return const ResidentProfileScreen();
        }

        return const HomeScreen();
      },
    );
  }
}
