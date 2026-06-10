const maintenanceActiveCode = 'maintenance_active';

const defaultMaintenanceMessage = '점검 중입니다. 잠시 후 다시 이용해주세요.';

bool isMaintenanceActiveError(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains(maintenanceActiveCode);
}

String maintenanceMessageFromError(
  Object error, {
  String fallback = defaultMaintenanceMessage,
}) {
  if (!isMaintenanceActiveError(error)) return fallback;
  return fallback;
}
