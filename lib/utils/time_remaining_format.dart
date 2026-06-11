/// 대여 종료까지 남은 시간 표기 (홈 잔여시간)
String formatTimeRemaining(Duration diff) {
  if (diff.isNegative) return '종료';
  final totalHours = diff.inHours;
  if (totalHours >= 24) {
    final days = totalHours ~/ 24;
    final hours = totalHours % 24;
    if (hours == 0) return '$days일';
    return '$days일 $hours시간';
  }
  if (totalHours >= 1) {
    return '$totalHours시간 ${diff.inMinutes % 60}분 남음';
  }
  if (diff.inMinutes >= 1) return '${diff.inMinutes}분 남음';
  return '곧 종료';
}
