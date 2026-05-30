import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

Future<bool> launchPhoneCall(String phone) async {
  final normalized = phone.replaceAll(RegExp(r'[^\d+]'), '');
  if (normalized.isEmpty) return false;

  final uri = Uri(scheme: 'tel', path: normalized);
  try {
    final launched = await launchUrl(
      uri,
      mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
    );
    return launched;
  } catch (e) {
    debugPrint('[phone] launch failed: $e');
    return false;
  }
}
