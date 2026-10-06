import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:overx/core/engine/engine_controller.dart';
import 'package:overx/core/process/core_process.dart';
import 'package:overx/core/models/settings.dart';
import 'package:overx/l10n/strings_provider.dart';
import 'package:overx/theme/app_theme.dart';

/// صفحه‌ی لاگ‌ها.
class LogsPage extends ConsumerWidget {
  const LogsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final logs = ref.watch(logsProvider);
    final paused = ref.watch(logsPausedProvider);

    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        // نوار ابزار
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => ref.read(logsProvider.notifier).togglePaused(),
                icon: Icon(
                  paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  size: 17,
                ),
                label: Text(paused ? s.t('resume') : s.t('pause')),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => ref.read(logsProvider.notifier).clear(),
                icon: const Icon(Icons.delete_sweep_outlined, size: 17),
                label: Text(s.t('clear')),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: logs.isEmpty
                    ? null
                    : () {
                        final text =
                            logs.map((l) => l.toString()).join('\n');
                        Clipboard.setData(ClipboardData(text: text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('${s.t('copyLogs')} ✓')),
                        );
                      },
                icon: const Icon(Icons.copy_all_rounded, size: 17),
                label: Text(s.t('copyLogs')),
              ),
              const Spacer(),
              Text(
                '${logs.length}',
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.outline,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),

        // بدنه‌ی لاگ
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF07090D) : const Color(0xFF0D1117),
                borderRadius: BorderRadius.circular(AppTheme.radius),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
              ),
              clipBehavior: Clip.antiAlias,
              child: logs.isEmpty
                  ? Center(
                      child: Text(
                        s.t('logsSub'),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                      ),
                    )
                  : SelectionArea(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: logs.length,
                        itemBuilder: (_, i) =>
                            _LogRow(line: logs[i]),
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.line});

  final LogLine line;

  static const _colors = {
    LogLevel.debug: Color(0xFF6E7C8C),
    LogLevel.info: Color(0xFFB9C6D6),
    LogLevel.warning: Color(0xFFFBBF24),
    LogLevel.error: Color(0xFFF87171),
  };

  @override
  Widget build(BuildContext context) {
    final time = line.time.toIso8601String().substring(11, 19);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: RichText(
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.start,
        text: TextSpan(
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 11.5,
            height: 1.65,
          ),
          children: [
            TextSpan(
              text: '$time ',
              style: const TextStyle(color: Color(0xFF4B5A6B)),
            ),
            TextSpan(
              text: '${line.level.name.toUpperCase().padRight(5)} ',
              style: TextStyle(
                color: (_colors[line.level] ?? const Color(0xFFB9C6D6))
                    .withValues(alpha: 0.85),
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: line.text,
              style: TextStyle(color: _colors[line.level]),
            ),
          ],
        ),
      ),
    );
  }
}
