class InspectionPhotoEntry {
  final String url;
  final DateTime? capturedAt;

  const InspectionPhotoEntry({
    required this.url,
    this.capturedAt,
  });

  static List<InspectionPhotoEntry> fromUrls(
    List<String> urls, {
    DateTime? capturedAt,
  }) {
    return urls
        .map(
          (url) => InspectionPhotoEntry(url: url, capturedAt: capturedAt),
        )
        .toList();
  }
}

class InspectionPhotoSet {
  final List<InspectionPhotoEntry> before;
  final List<InspectionPhotoEntry> after;

  const InspectionPhotoSet({
    this.before = const [],
    this.after = const [],
  });

  static const empty = InspectionPhotoSet();

  bool get hasAny => before.isNotEmpty || after.isNotEmpty;
}
