/// 앱 시작 직후 등 네트워크 미준비 시 일시적 오류 재시도
Future<T> withNetworkRetry<T>(
  Future<T> Function() action, {
  int maxAttempts = 3,
  Duration initialDelay = const Duration(milliseconds: 600),
}) async {
  Object? lastError;
  StackTrace? lastStack;

  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await action();
    } catch (e, st) {
      lastError = e;
      lastStack = st;
      if (attempt >= maxAttempts || !isRetryableNetworkError(e)) {
        Error.throwWithStackTrace(e, st);
      }
      await Future<void>.delayed(initialDelay * attempt);
    }
  }

  Error.throwWithStackTrace(lastError!, lastStack ?? StackTrace.current);
}

bool isRetryableNetworkError(Object error) {
  final msg = error.toString().toLowerCase();
  return msg.contains('socketexception') ||
      msg.contains('clientexception') ||
      msg.contains('failed host lookup') ||
      msg.contains('no address associated with hostname') ||
      msg.contains('network is unreachable') ||
      msg.contains('connection timed out') ||
      msg.contains('connection refused') ||
      msg.contains('connection reset') ||
      msg.contains('errno = 7');
}

/// UI용 네트워크 오류 메시지
String friendlyNetworkError(Object error) {
  if (isRetryableNetworkError(error)) {
    return '네트워크 연결에 실패했습니다.\n'
        'Wi-Fi·LTE 연결을 확인한 뒤 다시 시도해주세요.';
  }
  return error.toString().replaceFirst('Exception: ', '');
}
