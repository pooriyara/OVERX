import 'package:overx/core/engine/engine_controller.dart';
import 'package:overx/core/models/app_package.dart';
import 'package:overx/core/models/settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PerAppProxyMode', () {
    test('include در برابر exclude', () {
      expect(PerAppProxyMode.include.isInclude, true);
      expect(PerAppProxyMode.exclude.isInclude, false);
    });
  });

  group('AppPackage', () {
    test('نام نمایشی به برچسب برمی‌گردد', () {
      const p = AppPackage(packageName: 'a.b', label: 'مرورگر');
      expect(p.displayName, 'مرورگر');
    });

    test('اگر برچسب خالی بود، خودِ نام بسته', () {
      const p = AppPackage(packageName: 'a.b');
      expect(p.displayName, 'a.b');
    });

    test('رفت‌وبرگشت JSON', () {
      const p = AppPackage(
        packageName: 'com.telegram',
        label: 'Telegram',
        isSystem: false,
      );
      final q = AppPackage.fromJson(p.toJson());
      expect(q, p);
      expect(q.isSystem, false);
    });

    test('برابری بر اساس نام بسته است', () {
      const a = AppPackage(packageName: 'x', label: 'یک');
      const b = AppPackage(packageName: 'x', label: 'دو');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('EngineController.perAppLists', () {
    AppSettings base() => const AppSettings()
        .copyWith(perAppPackages: <String>['a', 'b']);

    test('وقتی غیرفعال است هر دو فهرست خالی است', () {
      final (include, exclude) = EngineController.perAppLists(
        base().copyWith(perAppProxyEnabled: false),
      );
      expect(include, isEmpty);
      expect(exclude, isEmpty);
    });

    test('وقتی فهرست خالی است (هرچند فعال) باز هم خالی', () {
      final (include, exclude) = EngineController.perAppLists(
        const AppSettings().copyWith(perAppPackages: <String>[]),
      );
      expect(include, isEmpty);
      expect(exclude, isEmpty);
    });

    test('حالت include: بسته‌ها در include می‌روند', () {
      final (include, exclude) = EngineController.perAppLists(
        base().copyWith(
          perAppProxyEnabled: true,
          perAppProxyMode: PerAppProxyMode.include,
        ),
      );
      expect(include, ['a', 'b']);
      expect(exclude, isEmpty);
    });

    test('حالت exclude: بسته‌ها در exclude می‌روند', () {
      final (include, exclude) = EngineController.perAppLists(
        base().copyWith(
          perAppProxyEnabled: true,
          perAppProxyMode: PerAppProxyMode.exclude,
        ),
      );
      expect(include, isEmpty);
      expect(exclude, ['a', 'b']);
    });
  });

  group('AppSettings — پایداریِ تنظیماتِ per-app', () {
    test('دور کامل JSON فهرست و حالت را حفظ می‌کند', () {
      final original = const AppSettings().copyWith(
        perAppProxyEnabled: true,
        perAppProxyMode: PerAppProxyMode.include,
        perAppPackages: <String>['com.a', 'com.b'],
      );
      final restored = AppSettings.fromJson(original.toJson());

      expect(restored.perAppProxyEnabled, true);
      expect(restored.perAppProxyMode, PerAppProxyMode.include);
      expect(restored.perAppPackages, ['com.a', 'com.b']);
    });

    test('مقادیر پیش‌فرض: غیرفعال، exclude، خالی', () {
      final s = AppSettings.fromJson(const AppSettings().toJson());
      expect(s.perAppProxyEnabled, false);
      expect(s.perAppProxyMode, PerAppProxyMode.exclude);
      expect(s.perAppPackages, isEmpty);
    });

    test('کانفیگ قدیمی (بدون کلیدهای جدید) نمی‌شکند', () {
      final s = AppSettings.fromJson(<String, dynamic>{
        'lang': 'fa',
        'mixedPort': 2080,
      });
      expect(s.perAppProxyEnabled, false);
      expect(s.perAppPackages, isEmpty);
    });
  });
}
