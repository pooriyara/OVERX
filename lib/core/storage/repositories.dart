import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:overx/core/models/profile.dart';
import 'package:overx/core/models/settings.dart';
import 'package:overx/core/models/subscription.dart';

/// نگه‌داری تنظیمات در SharedPreferences.
class SettingsRepository {
  const SettingsRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'overx.settings.v1';

  AppSettings defaults() => const AppSettings();

  AppSettings load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return defaults();
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return defaults();
    }
  }

  Future<void> save(AppSettings s) =>
      _prefs.setString(_key, jsonEncode(s.toJson()));

  Future<void> clear() => _prefs.remove(_key);
}

/// نگه‌داری پروفایل‌ها.
class ProfileRepository {
  const ProfileRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'overx.profiles.v1';
  static const _subsKey = 'overx.subscriptions.v1';

  List<Profile> defaults() => const [];

  List<Subscription> loadSubscriptions() {
    final raw = _prefs.getStringList(_subsKey);
    if (raw == null) return const [];
    return raw
        .map((e) => Subscription.decode(e))
        .whereType<Subscription>()
        .toList(growable: false);
  }

  Future<void> saveSubscriptions(List<Subscription> list) =>
      _prefs.setStringList(_subsKey, list.map((e) => e.encode()).toList());

  List<Profile> load() {
    final raw = _prefs.getStringList(_key);
    if (raw == null) return defaults();
    return raw
        .map((e) => Profile.decode(e))
        .whereType<Profile>()
        .toList(growable: false);
  }

  Future<void> save(List<Profile> list) =>
      _prefs.setStringList(_key, list.map((e) => e.encode()).toList());

  Future<void> clear() => _prefs.remove(_key);
}
