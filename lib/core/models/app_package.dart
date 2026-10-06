/// شیوه‌ی انتخاب برنامه‌ها در «مسیریابیِ هر برنامه».
enum PerAppProxyMode {
  /// فقط برنامه‌های انتخاب‌شده از VPN عبور می‌کنند.
  include,

  /// همه عبور می‌کنند به‌جز برنامه‌های انتخاب‌شده.
  exclude;

  bool get isInclude => this == PerAppProxyMode.include;
}

/// یک برنامه‌ی نصب‌شده روی اندروید.
///
/// فقط نام بسته و برچسب را نگه می‌داریم (نه آیکون) تا حجمِ رفت‌وبرگشت روی
/// کانال کم بماند.
class AppPackage {
  const AppPackage({
    required this.packageName,
    this.label = '',
    this.isSystem = false,
  });

  final String packageName;
  final String label;
  final bool isSystem;

  factory AppPackage.fromJson(Map<Object?, Object?> j) => AppPackage(
        packageName: j['packageName'] as String? ?? '',
        label: j['label'] as String? ?? '',
        isSystem: j['isSystem'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'packageName': packageName,
        'label': label,
        'isSystem': isSystem,
      };

  /// نام نمایشی: اگر برچسب خالی بود، خودِ نام بسته.
  String get displayName => label.isEmpty ? packageName : label;

  @override
  bool operator ==(Object other) =>
      other is AppPackage && other.packageName == packageName;

  @override
  int get hashCode => packageName.hashCode;

  @override
  String toString() => 'AppPackage($packageName, $label)';
}
