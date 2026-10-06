import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:overx/core/engine/engine_controller.dart';
import 'package:overx/l10n/strings_provider.dart';
import 'package:overx/theme/app_theme.dart';

/// صفحه‌ی درباره.
class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final engine = ref.watch(engineProvider);
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
      children: [
        // hero
        AppCard(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // لوگوی کاملِ برنامه (نشانه + نام) — نسخه‌ی سفید برای زمینه‌ی تیره
              Image.asset(
                Theme.of(context).brightness == Brightness.dark
                    ? 'assets/logo_white.png'
                    : 'assets/logo.png',
                height: 54,
                filterQuality: FilterQuality.medium,
              ),
              const SizedBox(height: 16),
              Text(
                s.t('tagline2'),
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              AppChip(label: 'v1.0.0 · Flutter', color: scheme.outline),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // مشخصات
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle('Build'),
              _Kv('OVERX', '1.0.0 (1)'),
              _Kv(s.t('aSdk'), '3.24 · Dart 3.5'),
              _Kv('Channel', 'stable'),
              const Divider(height: 20),
              const SectionTitle('Cores'),
              _Kv(s.t('aSb'), engine.singboxVersion ?? s.t('notFound')),
              _Kv(s.t('aXr'), engine.xrayVersion ?? s.t('notFound')),
              if (engine.singboxPath != null) _Kv('path', engine.singboxPath!),
              if (engine.xrayPath != null) _Kv('path', engine.xrayPath!),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // قدردانی
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionTitle(s.t('aCredits')),
              _Credit(
                name: 'sing-box',
                org: 'SagerNet',
                license: 'MIT',
                color: const Color(0xFF14B8A6),
                letter: 'SB',
              ),
              const SizedBox(height: 12),
              _Credit(
                name: 'Xray-core',
                org: 'XTLS',
                license: 'MPL-2.0',
                color: const Color(0xFF6366F1),
                letter: 'XR',
              ),
              const SizedBox(height: 16),
              Text(
                s.t('disclaimer'),
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.75,
                  color: scheme.outline,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Kv extends StatelessWidget {
  const _Kv(this.k, this.v);

  final String k;
  final String v;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: TextStyle(fontSize: 12.5, color: scheme.outline)),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              v,
              textAlign: TextAlign.end,
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontSize: 11.5,
                fontFamily: 'monospace',
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Credit extends StatelessWidget {
  const _Credit({
    required this.name,
    required this.org,
    required this.license,
    required this.color,
    required this.letter,
  });

  final String name;
  final String org;
  final String license;
  final Color color;
  final String letter;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Center(
            child: Text(
              letter,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
              Text(
                org,
                style: TextStyle(fontSize: 11.5, color: scheme.outline),
              ),
            ],
          ),
        ),
        AppChip(label: license, color: scheme.outline),
      ],
    );
  }
}
