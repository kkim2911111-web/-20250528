import 'package:flutter/material.dart';

import '../services/payment_service.dart';
import '../theme/danji_colors.dart';
import '../widgets/danji_app_bar.dart';
import 'splash_screen.dart';
import '../routing/app_routes.dart';

/// 웹 빌링키 발급 리다이렉트 — success
class BillingAuthSuccessScreen extends StatefulWidget {
  final Map<String, String> queryParams;

  const BillingAuthSuccessScreen({super.key, required this.queryParams});

  @override
  State<BillingAuthSuccessScreen> createState() =>
      _BillingAuthSuccessScreenState();
}

class _BillingAuthSuccessScreenState extends State<BillingAuthSuccessScreen> {
  final _payment = PaymentService();
  var _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _issue();
  }

  Future<void> _issue() async {
    final authKey = widget.queryParams['authKey']?.trim();
    final customerKey = widget.queryParams['customerKey']?.trim();
    if (authKey == null ||
        authKey.isEmpty ||
        customerKey == null ||
        customerKey.isEmpty) {
      setState(() {
        _loading = false;
        _error = '카드 등록 정보가 없습니다. 온보딩에서 다시 시도해주세요.';
      });
      return;
    }

    try {
      await _payment.issueSignupBillingKey(
        authKey: authKey,
        customerKey: customerKey,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _goHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SplashScreen(child: AuthGate())),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: const DanjiAppBar(title: '카드 등록'),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    _error == null ? Icons.check_circle : Icons.error_outline,
                    size: 56,
                    color: _error == null
                        ? DanjiColors.buttonBlue
                        : DanjiColors.accentRed,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _error == null
                        ? paymentCardRegistrationSuccessMessage
                        : '카드 등록에 실패했습니다.',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: DanjiColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                  const Spacer(),
                  FilledButton(
                    onPressed: _goHome,
                    child: const Text('가입 이어하기'),
                  ),
                ],
              ),
      ),
    );
  }
}

/// 웹 빌링키 발급 리다이렉트 — fail
class BillingAuthFailScreen extends StatelessWidget {
  final Map<String, String> queryParams;

  const BillingAuthFailScreen({super.key, required this.queryParams});

  @override
  Widget build(BuildContext context) {
    final code = queryParams['code'];
    final message = queryParams['message'];

    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: const DanjiAppBar(title: '카드 등록'),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.error_outline,
              size: 56,
              color: DanjiColors.accentRed,
            ),
            const SizedBox(height: 16),
            const Text(
              '카드 등록이 완료되지 않았습니다.',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            if (message != null && message.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                message,
                style: const TextStyle(
                  color: DanjiColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
            if (code != null && code.isNotEmpty)
              Text(
                '코드: $code',
                style: const TextStyle(
                  color: DanjiColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            const Spacer(),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => const SplashScreen(child: AuthGate()),
                  ),
                  (_) => false,
                );
              },
              child: const Text('카드 등록 단계로 돌아가기'),
            ),
          ],
        ),
      ),
    );
  }
}
