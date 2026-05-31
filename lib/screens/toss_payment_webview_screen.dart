import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../config/payment_config.dart';
import '../theme/danji_colors.dart';
import '../widgets/danji_app_bar.dart';

/// Android/iOS — Toss Payments v2 결제창 (WebView)
class TossPaymentWebViewScreen extends StatefulWidget {
  final String orderId;
  final String orderName;
  final int amount;
  final String customerKey;
  final TossPaymentMethod method;
  final String? customerEmail;
  final String? customerName;

  const TossPaymentWebViewScreen({
    super.key,
    required this.orderId,
    required this.orderName,
    required this.amount,
    required this.customerKey,
    required this.method,
    this.customerEmail,
    this.customerName,
  });

  @override
  State<TossPaymentWebViewScreen> createState() =>
      _TossPaymentWebViewScreenState();
}

class _TossPaymentWebViewScreenState extends State<TossPaymentWebViewScreen> {
  late final WebViewController _controller;
  var _loading = true;
  String? _error;
  var _completed = false;

  static final _webviewBaseUrl = '${PaymentConfig.mobilePaymentOrigin}/';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) => _handleRedirectUrl(url),
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onUrlChange: (change) => _handleRedirectUrl(change.url),
          onWebResourceError: (error) {
            if (!mounted || _completed) return;
            setState(() {
              _loading = false;
              _error = error.description;
            });
          },
          onNavigationRequest: (request) async {
            final decision = await _navigationDecisionFor(request.url);
            return decision;
          },
        ),
      )
      ..loadHtmlString(
        _buildPaymentHtml(),
        baseUrl: _webviewBaseUrl,
      );
  }

  Future<NavigationDecision> _navigationDecisionFor(String url) async {
    if (_tryHandlePaymentRedirect(url)) {
      return NavigationDecision.prevent;
    }

    final uri = Uri.tryParse(url);
    if (uri == null) return NavigationDecision.navigate;

    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return NavigationDecision.navigate;
    }

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
    return NavigationDecision.prevent;
  }

  void _handleRedirectUrl(String? url) {
    if (url == null || url.isEmpty) return;
    _tryHandlePaymentRedirect(url);
  }

  bool _tryHandlePaymentRedirect(String url) {
    if (_completed) return true;

    final uri = Uri.tryParse(url);
    if (uri == null) return false;

    String? segment;
    if (uri.scheme == PaymentConfig.appPaymentScheme &&
        uri.host == 'payment' &&
        uri.pathSegments.isNotEmpty) {
      segment = uri.pathSegments.first;
    } else if (uri.scheme == 'https' &&
        uri.host == PaymentConfig.appPaymentHost &&
        uri.pathSegments.length >= 2 &&
        uri.pathSegments.first == 'payment') {
      segment = uri.pathSegments[1];
    }

    if (segment != 'success' && segment != 'fail') {
      return false;
    }

    final params = Map<String, String>.from(uri.queryParameters);
    params['_route'] = segment!;
    _completed = true;

    if (mounted) {
      Navigator.of(context).pop(params);
    }
    return true;
  }

  String _buildPaymentHtml() {
    final config = <String, dynamic>{
      'clientKey': PaymentConfig.tossClientKey,
      'method': widget.method.tossMethod,
      'amount': widget.amount,
      'orderId': widget.orderId,
      'orderName': widget.orderName,
      'customerKey': widget.customerKey,
      'successUrl': PaymentConfig.appPaymentRedirectUrl('success'),
      'failUrl': PaymentConfig.appPaymentRedirectUrl('fail'),
      if (widget.customerEmail != null) 'customerEmail': widget.customerEmail,
      if (widget.customerName != null) 'customerName': widget.customerName,
      if (widget.method.isKakaoPay) 'easyPay': 'KAKAOPAY',
    };

    final configJson = jsonEncode(config);
    return '''
<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <script src="https://js.tosspayments.com/v2/standard"></script>
  <style>
    body {
      font-family: sans-serif;
      margin: 0;
      padding: 24px;
      background: #f5f8fc;
      color: #1a1a2e;
    }
    .box {
      max-width: 420px;
      margin: 40px auto;
      padding: 24px;
      background: #fff;
      border-radius: 16px;
      text-align: center;
    }
    .muted { color: #667085; font-size: 14px; line-height: 1.5; }
    .error { color: #d32f2f; }
  </style>
</head>
<body>
  <div class="box">
    <p id="status" class="muted">결제창을 불러오는 중입니다...</p>
  </div>
  <script>
    (async function () {
      var config = $configJson;
      var status = document.getElementById('status');
      try {
        if (typeof TossPayments === 'undefined') {
          throw new Error('TossPayments SDK를 불러오지 못했습니다.');
        }
        var tossPayments = TossPayments(config.clientKey);
        var payment = tossPayments.payment({ customerKey: config.customerKey });
        var params = {
          method: config.method,
          amount: { currency: 'KRW', value: config.amount },
          orderId: config.orderId,
          orderName: config.orderName,
          successUrl: config.successUrl,
          failUrl: config.failUrl
        };
        if (config.customerEmail) params.customerEmail = config.customerEmail;
        if (config.customerName) params.customerName = config.customerName;
        if (config.method === 'CARD' && config.easyPay === 'KAKAOPAY') {
          params.card = { flowMode: 'DIRECT', easyPay: 'KAKAOPAY' };
        } else if (config.method === 'CARD') {
          params.card = { flowMode: 'DEFAULT' };
        } else if (config.method === 'TRANSFER') {
          params.transfer = { cashReceipt: { type: '소득공제' } };
        }
        status.textContent = '결제창을 여는 중입니다...';
        await payment.requestPayment(params);
      } catch (err) {
        var msg = (err && err.message) ? err.message : String(err);
        status.className = 'error';
        status.textContent = '결제 오류: ' + msg;
      }
    })();
  </script>
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: const DanjiAppBar(title: '결제'),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: DanjiColors.danger),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('닫기'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
