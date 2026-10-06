import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:overx/core/engine/engine_controller.dart';
import 'package:overx/core/models/traffic.dart';
import 'package:overx/l10n/strings_provider.dart';
import 'package:overx/theme/app_theme.dart';

const int _historyLength = 44;

/// نمایشِ آپلود/دانلود همراه با نمودارِ لحظه‌ای.
class TrafficMeter extends ConsumerStatefulWidget {
  const TrafficMeter({super.key});

  @override
  ConsumerState<TrafficMeter> createState() => _TrafficMeterState();
}

class _TrafficMeterState extends ConsumerState<TrafficMeter> {
  final List<double> _up = [];
  final List<double> _down = [];

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final traffic = ref.watch(trafficProvider);

    ref.listen(trafficProvider, (prev, next) {
      _push(_up, next.uplinkSpeed.toDouble());
      _push(_down, next.downlinkSpeed.toDouble());
    });

    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: _Panel(
                label: s.t('upload'),
                total: traffic.uplinkTotal,
                speed: traffic.uplinkSpeed,
                history: _up,
                color: const Color(0xFFF59E0B),
                icon: Icons.arrow_upward_rounded,
                unit: 'B',
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: _Panel(
                label: s.t('download'),
                total: traffic.downlinkTotal,
                speed: traffic.downlinkSpeed,
                history: _down,
                color: scheme.primary,
                icon: Icons.arrow_downward_rounded,
                unit: 'B',
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _push(List<double> list, double v) {
    list.add(v);
    while (list.length > _historyLength) {
      list.removeAt(0);
    }
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.label,
    required this.total,
    required this.speed,
    required this.history,
    required this.color,
    required this.icon,
    required this.unit,
  });

  final String label;
  final int total;
  final int speed;
  final List<double> history;
  final Color color;
  final IconData icon;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              formatBytes(total),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                height: 1.05,
                letterSpacing: -0.5,
                color: scheme.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            formatSpeed(speed),
            style: TextStyle(
              fontSize: 11.5,
              color: scheme.outline,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 28,
            width: double.infinity,
            child: CustomPaint(
              painter: _SparkPainter(data: history, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  const _SparkPainter({required this.data, required this.color});

  final List<double> data;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) {
      canvas.drawLine(
        Offset(0, size.height - 2),
        Offset(size.width, size.height - 2),
        _p(1)..color = color.withValues(alpha: 0.25),
      );
      return;
    }

    final max = data.fold<double>(0, math.max);
    final scale = max <= 0 ? 0.0 : 1.0 / max;

    final pts = <Offset>[];
    for (var i = 0; i < data.length; i++) {
      final x = (i / (data.length - 1)) * size.width;
      final y = size.height - 2 - (data[i] * scale) * (size.height - 5);
      pts.add(Offset(x, y));
    }

    //_area
    final area = Path()
      ..moveTo(0, size.height)
      ..lineTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      area.lineTo(p.dx, p.dy);
    }
    area
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.0)],
        ).createShader(Offset.zero & size),
    );

    // line
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      line.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(line, _p(1.6));

    // head dot
    canvas.drawCircle(
      pts.last,
      2.2,
      Paint()..color = color,
    );
  }

  Paint _p(double w) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  bool shouldRepaint(covariant _SparkPainter old) =>
      old.data.length != data.length || old.color != color;
}
