import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_maintenance_status.dart';
import '../supabase_client.dart';
import '../utils/network_retry.dart';

/// 점검모드 — app_settings.maintenance_mode (입주민 앱)
class AppMaintenanceService {
  AppMaintenanceService._();

  static final AppMaintenanceService instance = AppMaintenanceService._();

  AppMaintenanceStatus _cached = AppMaintenanceStatus.disabled;
  DateTime? _fetchedAt;

  AppMaintenanceStatus get cached => _cached;

  /// 최근 조회 결과 (없으면 disabled)
  Future<AppMaintenanceStatus> current({bool force = false}) async {
    if (!force &&
        _fetchedAt != null &&
        DateTime.now().difference(_fetchedAt!) < const Duration(seconds: 30)) {
      return _cached;
    }
    return fetch(force: true);
  }

  Future<AppMaintenanceStatus> fetch({bool force = false}) async {
    if (!isSupabaseInitialized) return AppMaintenanceStatus.disabled;

    try {
      final status = await withNetworkRetry(_load);
      _cached = status;
      _fetchedAt = DateTime.now();
      return status;
    } catch (_) {
      return _cached;
    }
  }

  void applyStatus(AppMaintenanceStatus status) {
    _cached = status;
    _fetchedAt = DateTime.now();
  }

  void clearCache() {
    _cached = AppMaintenanceStatus.disabled;
    _fetchedAt = null;
  }

  Future<AppMaintenanceStatus> _load() async {
    try {
      final data = await supabase.rpc('get_app_maintenance_status');
      return AppMaintenanceStatus.fromRpc(data);
    } on PostgrestException catch (e) {
      if (_isMissingRpc(e)) {
        return _loadFromTable();
      }
      rethrow;
    }
  }

  Future<AppMaintenanceStatus> _loadFromTable() async {
    final row = await supabase
        .from('app_settings')
        .select('value')
        .eq('key', 'maintenance_mode')
        .maybeSingle();
    if (row == null) return AppMaintenanceStatus.disabled;
    return AppMaintenanceStatus.fromSettingsValue(row['value']);
  }

  bool _isMissingRpc(PostgrestException e) {
    final msg = e.message.toLowerCase();
    return msg.contains('get_app_maintenance_status') &&
        (msg.contains('could not find') || e.code == 'PGRST202');
  }
}
