/// 주유 상태 (DB: full / 3quarter / half / quarter / empty)
enum FuelLevel {
  full('full', '만땅'),
  threeQuarter('3quarter', '3/4'),
  half('half', '1/2'),
  quarter('quarter', '1/4'),
  empty('empty', '거의 없음');

  final String value;
  final String label;

  const FuelLevel(this.value, this.label);

  static FuelLevel? fromValue(String? value) {
    if (value == null) return null;
    for (final level in FuelLevel.values) {
      if (level.value == value) return level;
    }
    return null;
  }
}
