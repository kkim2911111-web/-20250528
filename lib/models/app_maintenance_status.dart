class AppMaintenanceStatus {
  final bool enabled;
  final String message;

  const AppMaintenanceStatus({
    this.enabled = false,
    this.message = '점검 중입니다. 잠시 후 다시 이용해주세요.',
  });

  static const disabled = AppMaintenanceStatus();

  factory AppMaintenanceStatus.fromRpc(Object? raw) {
    if (raw is! Map) return disabled;
    final m = Map<String, dynamic>.from(raw);
    final enabled = m['enabled'] == true;
    final message = m['message']?.toString().trim();
    return AppMaintenanceStatus(
      enabled: enabled,
      message: (message == null || message.isEmpty)
          ? disabled.message
          : message,
    );
  }

  factory AppMaintenanceStatus.fromSettingsValue(Object? value) {
    if (value is! Map) return disabled;
    final m = Map<String, dynamic>.from(value);
    return AppMaintenanceStatus(
      enabled: m['enabled'] == true,
      message: m['message']?.toString().trim().isNotEmpty == true
          ? m['message'].toString()
          : disabled.message,
    );
  }
}
