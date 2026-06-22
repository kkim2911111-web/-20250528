class LocalSpot {
  final String id;
  final String name;
  final String shortName;
  final String description;
  final String imageUrl;
  final double rating;
  final List<String> tags;
  final String distanceText;
  final bool isFeatured;
  final String? phoneNumber;
  final int sortOrder;

  const LocalSpot({
    required this.id,
    required this.name,
    required this.shortName,
    required this.description,
    required this.imageUrl,
    required this.rating,
    required this.tags,
    required this.distanceText,
    this.isFeatured = false,
    this.phoneNumber,
    this.sortOrder = 0,
  });

  factory LocalSpot.fromMap(Map<String, dynamic> map) {
    final rawTags = map['tags'];
    final tags = rawTags is List
        ? rawTags.map((e) => e.toString()).toList()
        : <String>[];

    return LocalSpot(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      shortName: map['short_name']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      imageUrl: map['image_url']?.toString() ?? '',
      rating: (map['rating'] as num?)?.toDouble() ?? 0,
      tags: tags,
      distanceText: map['distance_text']?.toString() ?? '',
      isFeatured: map['is_featured'] == true,
      phoneNumber: map['phone_number']?.toString(),
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  List<String> get displayTags => tags.take(2).toList();
}
