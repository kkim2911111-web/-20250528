/// 매출 집계 반납 완료일 — DB `sales_return_completed_at` / 노쇼 폴백과 동일
DateTime? resolveSalesReturnCompletedAt({
  DateTime? returnedAt,
  DateTime? actualEndAt,
  DateTime? scheduledEndAt,
  bool isNoShow = false,
  DateTime? updatedAt,
}) {
  final base = returnedAt ?? actualEndAt ?? scheduledEndAt;
  if (base != null) return base;
  if (isNoShow) return updatedAt;
  return null;
}

/// 매출 인식 월 라벨 (Asia/Seoul 기준, completed만)
String? formatSalesRecognitionMonth(DateTime? returnCompletedAt) {
  if (returnCompletedAt == null) return null;
  final local = returnCompletedAt.toLocal();
  return '${local.year}년 ${local.month}월';
}
