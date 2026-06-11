import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_feature_config.dart';
import '../supabase_client.dart';
import '../utils/network_retry.dart';

/// 기능별 킬 스위치 — app_config (조회 실패 시 허용)
class AppFeatureConfigService {
  AppFeatureConfigService._();

  static final AppFeatureConfigService instance = AppFeatureConfigService._();

  Map<String, AppFeatureConfig> _cached = AppFeatureConfig.allEnabled();
  DateTime? _fetchedAt;

  Map<String, AppFeatureConfig> get cached => Map.unmodifiable(_cached);

  bool isEnabled(String featureKey) =>
      _cached[featureKey]?.isEnabled ?? true;

  String messageFor(String featureKey) =>
      _cached[featureKey]?.blockMessage ??
      AppFeatureConfig.defaultFeatureDisabledMessage;

  Future<Map<String, AppFeatureConfig>> current({bool force = false}) async {
    if (!force &&
        _fetchedAt != null &&
        DateTime.now().difference(_fetchedAt!) < const Duration(seconds: 30)) {
      return _cached;
    }
    return fetch(force: true);
  }

  Future<Map<String, AppFeatureConfig>> fetch({bool force = false}) async {
    if (!isSupabaseInitialized) return _cached;

    try {
      final next = await withNetworkRetry(_load);
      _cached = next;
      _fetchedAt = DateTime.now();
      return next;
    } catch (_) {
      if (_fetchedAt == null) {
        _cached = AppFeatureConfig.allEnabled();
      }
      return _cached;
    }
  }

  void applyConfigs(Map<String, AppFeatureConfig> configs) {
    _cached = configs;
    _fetchedAt = DateTime.now();
  }

  void clearCache() {
    _cached = AppFeatureConfig.allEnabled();
    _fetchedAt = null;
  }

  Future<Map<String, AppFeatureConfig>> _load() async {
    try {
      final data = await supabase.rpc('get_app_feature_configs');
      return _parseRpc(data);
    } on PostgrestException catch (e) {
      if (_isMissingRpc(e)) {
        return _loadFromTable();
      }
      rethrow;
    }
  }

  Future<Map<String, AppFeatureConfig>> _loadFromTable() async {
    final rows = await supabase.from('app_config').select();
    final result = AppFeatureConfig.allEnabled();
    for (final row in rows) {
      final key = row['feature_key']?.toString();
      if (key == null || key.isEmpty) continue;
      result[key] = AppFeatureConfig(
        featureKey: key,
        isEnabled: row['is_enabled'] != false,
        disabledMessage: row['disabled_message']?.toString(),
      );
    }
    return result;
  }

  Map<String, AppFeatureConfig> _parseRpc(Object? raw) {
    final result = AppFeatureConfig.allEnabled();
    if (raw is! Map) return result;
    final map = Map<String, dynamic>.from(raw);
    for (final key in AppFeatureConfig.allEnabledKeys) {
      if (map.containsKey(key)) {
        result[key] = AppFeatureConfig.fromMap(key, map[key]);
      }
    }
    return result;
  }

  bool _isMissingRpc(PostgrestException e) {
    final msg = e.message.toLowerCase();
    return msg.contains('get_app_feature_configs') &&
        (msg.contains('could not find') || e.code == 'PGRST202');
  }
}
