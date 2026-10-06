import 'dart:convert';

/// پروتکل‌هایی که در هر دو هسته پشتیبانی می‌کنیم.
enum ProfileProtocol {
  vless,
  vmess,
  trojan,
  shadowsocks,
  hysteria2,
  tuic;

  String get id => name;

  String get label => switch (this) {
        ProfileProtocol.vless => 'VLESS',
        ProfileProtocol.vmess => 'VMess',
        ProfileProtocol.trojan => 'Trojan',
        ProfileProtocol.shadowsocks => 'Shadowsocks',
        ProfileProtocol.hysteria2 => 'Hysteria2',
        ProfileProtocol.tuic => 'TUIC',
      };

  /// نام نوع در sing-box.
  String get singboxType => switch (this) {
        ProfileProtocol.vless => 'vless',
        ProfileProtocol.vmess => 'vmess',
        ProfileProtocol.trojan => 'trojan',
        ProfileProtocol.shadowsocks => 'shadowsocks',
        ProfileProtocol.hysteria2 => 'hysteria2',
        ProfileProtocol.tuic => 'tuic',
      };

  /// نام پروتکل در Xray.
  String? get xrayProtocol => switch (this) {
        ProfileProtocol.vless => 'vless',
        ProfileProtocol.vmess => 'vmess',
        ProfileProtocol.trojan => 'trojan',
        ProfileProtocol.shadowsocks => 'shadowsocks',
        // Hysteria2 / TUIC در Xray-core پشتیبانی نمی‌شن.
        ProfileProtocol.hysteria2 => null,
        ProfileProtocol.tuic => null,
      };

  bool get supportedByXray => xrayProtocol != null;
}

/// یک پروفایل/سرور.
///
/// فیلدهای اختصاصیِ هر پروتکل در [fields] نگه داشته می‌شن تا مدل
/// با اضافه شدن پروتکل جدید تغییر نکنه.
class Profile {
  const Profile({
    required this.id,
    required this.name,
    required this.protocol,
    required this.address,
    required this.port,
    this.fields = const {},
    this.rawLink,
    this.latencyMs,
  });

  final String id;
  final String name;
  final ProfileProtocol protocol;
  final String address;
  final int port;
  final Map<String, dynamic> fields;
  final String? rawLink;
  final int? latencyMs;

  // ---- فیلدهای پرکاربرد ----
  String? get uuid => fields['uuid'] as String?;
  String? get password => fields['password'] as String?;
  String? get method => fields['method'] as String?;
  String? get security => fields['security'] as String?; // tls|reality|none
  String? get sni => fields['sni'] as String?;
  String? get flow => fields['flow'] as String?;
  String? get network => fields['network'] as String?; // tcp|ws|grpc|http|quic|h2
  String? get path => fields['path'] as String?;
  String? get host => fields['host'] as String?;
  String? get serviceName => fields['serviceName'] as String?;
  String? get alpn => fields['alpn'] as String?;
  String? get fingerprint => fields['fingerprint'] as String?;
  String? get publicKey => fields['publicKey'] as String?;
  String? get shortId => fields['shortId'] as String?;
  String? get obfsPassword => fields['obfsPassword'] as String?;
  int? get upMbps => fields['upMbps'] as int?;
  int? get downMbps => fields['downMbps'] as int?;

  Profile copyWith({
    String? name,
    ProfileProtocol? protocol,
    String? address,
    int? port,
    Map<String, dynamic>? fields,
    String? rawLink,
    int? latencyMs,
  }) =>
      Profile(
        id: id,
        name: name ?? this.name,
        protocol: protocol ?? this.protocol,
        address: address ?? this.address,
        port: port ?? this.port,
        fields: fields ?? this.fields,
        rawLink: rawLink ?? this.rawLink,
        latencyMs: latencyMs ?? this.latencyMs,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'protocol': protocol.name,
        'address': address,
        'port': port,
        'fields': fields,
        if (rawLink != null) 'rawLink': rawLink,
        if (latencyMs != null) 'latencyMs': latencyMs,
      };

  static Profile fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'profile',
        protocol: ProfileProtocol.values.firstWhere(
          (p) => p.name == j['protocol'],
          orElse: () => ProfileProtocol.vless,
        ),
        address: j['address'] as String? ?? '',
        port: (j['port'] as num?)?.toInt() ?? 443,
        fields: Map<String, dynamic>.from(j['fields'] as Map? ?? {}),
        rawLink: j['rawLink'] as String?,
        latencyMs: (j['latencyMs'] as num?)?.toInt(),
      );

  String encode() => jsonEncode(toJson());

  static Profile? decode(String s) {
    try {
      return fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => '$name (${protocol.label} @ $address:$port)';
}
