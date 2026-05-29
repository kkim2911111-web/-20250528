import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/booking_route.dart';
import '../screens/payment_fail_screen.dart';
import '../screens/payment_success_screen.dart';
import '../screens/main_shell.dart';
import '../resident_profile_screen.dart';
import '../screens/admin/admin_dashboard_screen.dart';
import '../screens/admin/admin_pending_screen.dart';
import '../screens/admin/admin_sign_up_screen.dart';
import '../screens/login_screen.dart';
import '../repositories/staff_repository.dart';
import '../models/staff_profile.dart';
import '../services/auth_service.dart';
import '../services/fcm_service.dart';
import '../supabase_client.dart';

/// 토스 결제 리다이렉트 직후 URL 스냅샷 (Supabase 초기화·세션 복구 후에도 유지)
Uri? _capturedLaunchUri;

/// main()에서 Supabase.initialize 전에 호출
void captureLaunchUri() {
  if (kIsWeb) {
    _capturedLaunchUri = Uri.base;
    debugPrint(
      '[router] captureLaunchUri path=${_capturedLaunchUri!.path} '
      'query=${_capturedLaunchUri!.queryParameters}',
    );
  }
}

/// 브라우저 시작 URL (경로 + 쿼리). Supabase 초기화 전 captureLaunchUri()로 보존.
Uri? get webLaunchUri =>
    kIsWeb ? (_capturedLaunchUri ?? Uri.base) : null;

/// MaterialApp initialRoute — **경로만** (쿼리 제외). Flutter routes map과 호환.
String webInitialRoute() {
  if (!kIsWeb) return '/';
  final uri = webLaunchUri;
  if (uri == null) return '/';
  final path = _normalizePath(uri.path);
  if (path.isEmpty || path == '/') return '/';
  return path;
}

String _normalizePath(String path) =>
    path.replaceAll(RegExp(r'/+$'), '');

String routePath(String? name) {
  if (name == null || name.isEmpty) return '/';
  final uri = Uri.parse(name.startsWith('/') ? name : '/$name');
  return _normalizePath(uri.path);
}

bool isPaymentSuccessPath(String? routeName) =>
    routePath(routeName).endsWith('/payment/success');

bool isPaymentFailPath(String? routeName) =>
    routePath(routeName).endsWith('/payment/fail');

bool isPaymentRoute(String? routeName) =>
    isPaymentSuccessPath(routeName) || isPaymentFailPath(routeName);

/// orderId, paymentKey, amount — 스냅샷(결제 직후 URL) + Uri.base.queryParameters 병합
Map<String, String> paymentQueryParams([String? routeName]) {
  final merged = <String, String>{};

  void addFromUri(Uri? uri) {
    if (uri == null) return;
    merged.addAll(uri.queryParameters);
  }

  // Supabase 초기화 전 보존 URL (쿼리 유실 방지)
  addFromUri(_capturedLaunchUri);
  // 브라우저 주소창 — 사용자 요청대로 최종 우선
  addFromUri(Uri.base);

  if (routeName != null && routeName.contains('?')) {
    addFromUri(Uri.parse(
      routeName.startsWith('/') ? routeName : '/$routeName',
    ));
  }

  return merged;
}

/// MaterialApp.home — path만 보고 결제 화면 또는 기본 진입
Widget resolveInitialHomeWidget() {
  if (kIsWeb) {
    final path = webInitialRoute();
    debugPrint(
      '[router] resolveInitialHome path=$path '
      'query=${paymentQueryParams()}',
    );
    if (isPaymentSuccessPath(path)) {
      return PaymentSuccessScreen(queryParams: paymentQueryParams());
    }
    if (isPaymentFailPath(path)) {
      return PaymentFailScreen(queryParams: paymentQueryParams());
    }
  }
  return const AppEntry();
}

Route<dynamic> buildPaymentSuccessRoute([String? routeName]) {
  final params = paymentQueryParams(routeName);
  return MaterialPageRoute(
    settings: RouteSettings(
      name: '/payment/success',
      arguments: params,
    ),
    builder: (_) => PaymentSuccessScreen(queryParams: params),
  );
}

Route<dynamic> buildPaymentFailRoute([String? routeName]) {
  final params = paymentQueryParams(routeName);
  return MaterialPageRoute(
    settings: RouteSettings(
      name: '/payment/fail',
      arguments: params,
    ),
    builder: (_) => PaymentFailScreen(queryParams: params),
  );
}

Route<dynamic> onGenerateRoute(RouteSettings settings) {
  // Flutter Web: route name에 ?orderId=... 가 붙어도 path만 추출
  final path = routePath(settings.name);

  if (path.endsWith('/payment/success')) {
    return buildPaymentSuccessRoute(settings.name);
  }
  if (path.endsWith('/payment/fail')) {
    return buildPaymentFailRoute(settings.name);
  }

  switch (path) {
    case '/home':
      return MaterialPageRoute(
        settings: RouteSettings(name: path),
        builder: (_) => const AuthGate(),
      );
    case '/booking':
      return MaterialPageRoute(
        settings: RouteSettings(name: path),
        builder: (_) => const BookingRoute(),
      );
    case '/':
      return MaterialPageRoute(
        settings: RouteSettings(name: path),
        builder: (_) => const AppEntry(),
      );
    default:
      return MaterialPageRoute(
        settings: RouteSettings(name: path),
        builder: (_) => const AppEntry(),
      );
  }
}

List<Route<dynamic>> generateInitialRoutes(String routeName) {
  // 플랫폼이 "/payment/success?orderId=..." 형태로 넘겨도 path만 추출
  final name = kIsWeb
      ? webInitialRoute()
      : routePath(routeName.isNotEmpty ? routeName : '/');

  debugPrint(
    '[router] generateInitialRoutes path=$name query=${paymentQueryParams()}',
  );

  return [
    onGenerateRoute(RouteSettings(name: name)),
  ];
}

Route<dynamic> onUnknownRoute(RouteSettings settings) {
  if (isPaymentSuccessPath(settings.name) ||
      isPaymentSuccessPath(webInitialRoute())) {
    return buildPaymentSuccessRoute(settings.name);
  }
  if (isPaymentFailPath(settings.name) ||
      isPaymentFailPath(webInitialRoute())) {
    return buildPaymentFailRoute(settings.name);
  }
  return MaterialPageRoute(builder: (_) => const AppEntry());
}

/// 웹 결제 리다이렉트 URL 처리 + 기본 진입점
class AppEntry extends StatelessWidget {
  const AppEntry({super.key});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      final path = webInitialRoute();
      if (isPaymentSuccessPath(path)) {
        return PaymentSuccessScreen(
          queryParams: paymentQueryParams(),
        );
      }
      if (isPaymentFailPath(path)) {
        return PaymentFailScreen(
          queryParams: paymentQueryParams(),
        );
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
  final _auth = AuthService();
  bool _showSignUp = false;
  bool _showAdminSignUp = false;

  @override
  void initState() {
    super.initState();
    _auth.onSignedOut = (toSignUp) {
      if (mounted) setState(() => _showSignUp = toSignUp);
    };
    supabase.auth.onAuthStateChange.listen((data) async {
      if (data.session != null) {
        if (mounted) {
          setState(() {
            _showSignUp = false;
            _showAdminSignUp = false;
          });
        }
        await FcmService.instance.registerForCurrentUser();
      }
    });
  }

  @override
  void dispose() {
    _auth.onSignedOut = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = supabase.auth;

    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, _) {
        final session = auth.currentSession;

        if (session == null) {
          if (_showAdminSignUp) {
            return AdminSignUpScreen(
              onGoLogin: () => setState(() => _showAdminSignUp = false),
            );
          }
          if (_showSignUp) {
            return SignUpScreen(
              onGoLogin: () => setState(() => _showSignUp = false),
            );
          }
          return LoginScreen(
            onGoSignUp: () => setState(() => _showSignUp = true),
            onGoAdminSignUp: () => setState(() => _showAdminSignUp = true),
          );
        }

        return const RoleGate();
      },
    );
  }
}

class RoleGate extends StatelessWidget {
  const RoleGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<StaffProfile?>(
      stream: StaffRepository().watchMyProfile(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final staff = snap.data;
        if (staff != null) {
          if (!staff.isApproved) {
            return AdminPendingScreen(profile: staff);
          }
          return AdminDashboardScreen(profile: staff);
        }

        return const ResidentGate();
      },
    );
  }
}

class ResidentGate extends StatelessWidget {
  const ResidentGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ResidentProfile?>(
      stream: ResidentRepository().watchMyProfile(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snap.hasError && snap.data == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('오류')),
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('입주민 정보 조회 실패: ${snap.error}'),
            ),
          );
        }

        final profile = snap.data;
        if (profile == null || profile.approved != true) {
          return const ResidentProfileScreen();
        }

        return const MainShell();
      },
    );
  }
}
