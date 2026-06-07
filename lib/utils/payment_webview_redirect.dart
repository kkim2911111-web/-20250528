import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../config/payment_config.dart';

/// Android MainActivity → WebView 결제 화면 딥링크 전달
class PaymentDeepLinkChannel {
  PaymentDeepLinkChannel._();

  static const _channel = EventChannel('danjicar/payment_deep_link');

  static Stream<String> get stream =>
      _channel.receiveBroadcastStream().map((event) => event.toString());
}

/// Toss WebView 결제/빌링 리다이렉트 파싱 결과
class PaymentRedirectResult {
  final String segment;
  final Map<String, String> params;

  const PaymentRedirectResult({
    required this.segment,
    required this.params,
  });
}

/// Toss WebView — success/fail URL 감지 및 외부 앱(카드사) 실행
abstract final class PaymentWebViewRedirect {
  static PaymentRedirectResult? parse(
    String url, {
    required Set<String> allowedSegments,
  }) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    String? segment;

    if (uri.scheme == PaymentConfig.appPaymentScheme) {
      if (uri.host == 'payment' && uri.pathSegments.isNotEmpty) {
        segment = uri.pathSegments.first;
      } else if (uri.pathSegments.length >= 2 &&
          uri.pathSegments.first == 'payment') {
        segment = uri.pathSegments[1];
      } else {
        final path = uri.path;
        for (final allowed in allowedSegments) {
          if (path == '/payment/$allowed' ||
              path.endsWith('/payment/$allowed')) {
            segment = allowed;
            break;
          }
        }
      }
    } else if ((uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host == PaymentConfig.appPaymentHost) {
      if (uri.pathSegments.length >= 2 &&
          uri.pathSegments.first == 'payment') {
        segment = uri.pathSegments[1];
      }
    }

    if (segment == null || !allowedSegments.contains(segment)) {
      return null;
    }

    final params = Map<String, String>.from(uri.queryParameters);
    params['_route'] = _routeKeyForSegment(segment);
    return PaymentRedirectResult(segment: segment, params: params);
  }

  static String _routeKeyForSegment(String segment) {
    if (segment == 'billing-success') return 'success';
    if (segment == 'billing-fail') return 'fail';
    return segment;
  }

  static bool isHttpUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https');
  }

  static bool isPaymentRedirectUrl(
    String url, {
    required Set<String> allowedSegments,
  }) =>
      parse(url, allowedSegments: allowedSegments) != null;

  /// 카드사 앱 등 외부 URL 실행 (intent:// 포함)
  static Future<bool> launchExternalUrl(String url) async {
    if (url.startsWith('intent://')) {
      return _launchAndroidIntentUrl(url);
    }

    final uri = Uri.tryParse(url);
    if (uri == null) return false;

    try {
      if (await canLaunchUrl(uri)) {
        return launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('[payment/webview] launchExternalUrl failed: $e');
    }
    return false;
  }

  static Future<bool> _launchAndroidIntentUrl(String url) async {
    final intentUri = Uri.tryParse(url);
    if (intentUri != null) {
      try {
        if (await canLaunchUrl(intentUri)) {
          return launchUrl(
            intentUri,
            mode: LaunchMode.externalApplication,
          );
        }
      } catch (_) {}
    }

    final schemeMatch = RegExp(r';scheme=([^;]+);?').firstMatch(url);
    if (schemeMatch != null) {
      final scheme = schemeMatch.group(1)!;
      final intentPart = url.split('#Intent').first;
      final rebuilt = intentPart.replaceFirst('intent://', '$scheme://');
      final schemeUri = Uri.tryParse(rebuilt);
      if (schemeUri != null) {
        try {
          if (await canLaunchUrl(schemeUri)) {
            return launchUrl(
              schemeUri,
              mode: LaunchMode.externalApplication,
            );
          }
        } catch (_) {}
      }
    }

    final fallbackMatch =
        RegExp(r'S\.browser_fallback_url=([^;]+);?').firstMatch(url);
    if (fallbackMatch != null) {
      final fallback = Uri.tryParse(
        Uri.decodeComponent(fallbackMatch.group(1)!),
      );
      if (fallback != null) {
        try {
          return launchUrl(fallback, mode: LaunchMode.externalApplication);
        } catch (_) {}
      }
    }

    final packageMatch = RegExp(r';package=([^;]+);?').firstMatch(url);
    if (packageMatch != null) {
      final marketUri =
          Uri.parse('market://details?id=${packageMatch.group(1)}');
      try {
        if (await canLaunchUrl(marketUri)) {
          return launchUrl(marketUri, mode: LaunchMode.externalApplication);
        }
      } catch (_) {}
    }

    return false;
  }

  static Future<NavigationDecision> navigationDecision({
    required String url,
    required Set<String> allowedSegments,
    required void Function(PaymentRedirectResult result) onRedirect,
    required bool completed,
  }) async {
    if (completed) return NavigationDecision.prevent;

    final redirect = parse(url, allowedSegments: allowedSegments);
    if (redirect != null) {
      onRedirect(redirect);
      return NavigationDecision.prevent;
    }

    if (isHttpUrl(url)) {
      return NavigationDecision.navigate;
    }

    await launchExternalUrl(url);
    return NavigationDecision.prevent;
  }
}
