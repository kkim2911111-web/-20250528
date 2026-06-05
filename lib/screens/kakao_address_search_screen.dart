import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../config/kakao_config.dart';
import '../theme/danji_colors.dart';
import '../widgets/danji_app_bar.dart';

/// 카카오(다음) 우편번호 주소 검색 WebView 팝업
class KakaoAddressSearchScreen extends StatefulWidget {
  const KakaoAddressSearchScreen({super.key});

  static Future<String?> show(BuildContext context) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        fullscreenDialog: true,
        builder: (_) => const KakaoAddressSearchScreen(),
      ),
    );
  }

  @override
  State<KakaoAddressSearchScreen> createState() =>
      _KakaoAddressSearchScreenState();
}

class _KakaoAddressSearchScreenState extends State<KakaoAddressSearchScreen> {
  late final WebViewController _controller;
  var _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'AddressChannel',
        onMessageReceived: (message) => _onAddressSelected(message.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            setState(() {
              _loading = false;
              _error = error.description;
            });
          },
        ),
      )
      ..loadHtmlString(
        _buildPostcodeHtml(),
        baseUrl: '${KakaoConfig.webViewBaseUrl}/',
      );
  }

  void _onAddressSelected(String raw) {
    String? address;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        address = decoded['address']?.toString();
      }
    } catch (_) {
      address = raw;
    }

    if (!mounted || address == null || address.trim().isEmpty) return;
    Navigator.of(context).pop(address.trim());
  }

  String _buildPostcodeHtml() {
    final jsKey = KakaoConfig.javascriptKey
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'");

    return '''
<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>주소 검색</title>
  <style>
    html, body { margin: 0; padding: 0; width: 100%; height: 100%; background: #fff; }
    #layer { width: 100%; height: 100%; }
  </style>
  <script>
    window.KAKAO_JAVASCRIPT_KEY = '$jsKey';
  </script>
  <script src="https://t1.daumcdn.net/mapjsapi/bundle/postcode/prod/postcode.v2.js"></script>
</head>
<body>
  <div id="layer"></div>
  <script>
    function sendAddress(payload) {
      if (window.AddressChannel && window.AddressChannel.postMessage) {
        window.AddressChannel.postMessage(JSON.stringify(payload));
      }
    }

    function openPostcode() {
      new daum.Postcode({
        oncomplete: function(data) {
          var addr = '';
          var extra = '';

          if (data.userSelectedType === 'R') {
            addr = data.roadAddress;
          } else {
            addr = data.jibunAddress;
          }

          if (data.bname !== '' && /[동|로|가]\$/g.test(data.bname)) {
            extra += data.bname;
          }
          if (data.buildingName !== '' && data.apartment === 'Y') {
            extra += (extra !== '' ? ', ' + data.buildingName : data.buildingName);
          }
          if (extra !== '') {
            addr += ' (' + extra + ')';
          }

          sendAddress({
            address: addr,
            zonecode: data.zonecode,
            roadAddress: data.roadAddress,
            jibunAddress: data.jibunAddress
          });
        },
        onresize: function(size) {
          var layer = document.getElementById('layer');
          layer.style.height = size.height + 'px';
        },
        width: '100%',
        height: '100%'
      }).embed(document.getElementById('layer'));
    }

    window.onload = openPostcode;
  </script>
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: const DanjiAppBar(
        title: '주소 검색',
        showBack: true,
        showHome: false,
        light: true,
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: DanjiColors.accentRed),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
