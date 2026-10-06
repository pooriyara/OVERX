import 'dart:convert';

/// یک اشتراک (گروهی از پروفایل‌ها که از یک URL می‌آید).
class Subscription {
  const Subscription({
    required this.id,
    required this.name,
    this.url,
    this.updatedAt,
  });

  final String id;
  final String name;

  /// لینکِ اشتراک — برای اشتراک‌هایی که دستی/کلیپ‌برد اضافه شده‌اند null است.
  final String? url;
  final DateTime? updatedAt;

  Subscription copyWith({
    String? name,
    String? url,
    DateTime? updatedAt,
    bool clearUrl = false,
  }) =>
      Subscription(
        id: id,
        name: name ?? this.name,
        url: clearUrl ? null : (url ?? this.url),
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (url != null) 'url': url,
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      };

  static Subscription fromJson(Map<String, dynamic> j) => Subscription(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'subscription',
        url: j['url'] as String?,
        updatedAt: j['updatedAt'] == null
            ? null
            : DateTime.tryParse(j['updatedAt'] as String),
      );

  String encode() => jsonEncode(toJson());

  static Subscription? decode(String s) {
    try {
      return fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => 'Subscription($name, url=$url)';
}
