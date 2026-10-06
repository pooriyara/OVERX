import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:overx/theme/app_theme.dart';

/// دکمه‌ی بزرگِ اتصال.
///
/// سه حالت:
///  - idle:        حلقه خاکستری + آیکون پاور
///  - connecting:  حلقه‌ی چرخانِ کهربایی
///  - connected:   حلقه‌ی سبز + هاله‌های پالس + آیکون سپر
class ConnectButton extends StatefulWidget {
  const ConnectButton({
    super.key,
    required this.status,
    required this.label,
    required this.hint,
    required this.onTap,
    this.size = 190,
  });

  final ConnectionState2 status;
  final String label;
  final String hint;
  final VoidCallback onTap;
  final double size;

  @override
  State<ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends State<ConnectButton>
    with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late final AnimationController _halo = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    reverseDuration: const Duration(milliseconds: 420),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant ConnectButton old) {
    super.didUpdateWidget(old);
    if (old.status != widget.status) _sync();
  }

  void _sync() {
    switch (widget.status) {
      case ConnectionState2.connecting:
        _spin.repeat();
        _halo.stop();
        _halo.value = 0;
      case ConnectionState2.connected:
        _spin.stop();
        _spin.value = 0;
        _halo.repeat();
      default:
        _spin.stop();
        _spin.value = 0;
        _halo.stop();
        _halo.value = 0;
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _halo.dispose();
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = StatusColors.of(widget.status);
    final coreSize = widget.size * 0.74;

    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        onTapDown: (_) => _press.forward(),
        onTapUp: (_) => _press.reverse(),
        onTapCancel: () => _press.reverse(),
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: Listenable.merge([_spin, _halo, _press]),
          builder: (context, _) {
            final scale = 1.0 - 0.035 * _press.value;
            return Transform.scale(
              scale: scale,
              child: SizedBox(
                width: widget.size,
                height: widget.size,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // هاله‌های پالس (فقط هنگام اتصال)
                    if (widget.status == ConnectionState2.connected)
                      CustomPaint(
                        size: Size.square(widget.size),
                        painter: _HaloPainter(
                          color: color,
                          t: _halo.value,
                        ),
                      ),

                    // حلقه
                    CustomPaint(
                      size: Size.square(widget.size),
                      painter: _RingPainter(
                        trackColor: scheme.outlineVariant.withValues(alpha: 0.9),
                        color: color,
                        indeterminate:
                            widget.status == ConnectionState2.connecting,
                        progress: widget.status == ConnectionState2.connected
                            ? 1.0
                            : 0.0,
                        rotation: _spin.value * 2 * math.pi,
                        strokeWidth: 5,
                      ),
                    ),

                    // هسته‌ی دکمه
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOutCubic,
                      width: coreSize,
                      height: coreSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.status == ConnectionState2.connected
                            ? scheme.surfaceContainerHigh
                            : scheme.surfaceContainerLow,
                        border: Border.all(
                          color: color.withValues(alpha: 
                              widget.status == ConnectionState2.disconnected
                                  ? 0.25
                                  : 0.55),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 
                                widget.status == ConnectionState2.disconnected
                                    ? 0.0
                                    : 0.22),
                            blurRadius: 26,
                            spreadRadius: 2,
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 260),
                            child: Icon(
                              switch (widget.status) {
                                ConnectionState2.connected =>
                                  Icons.shield_rounded,
                                ConnectionState2.connecting =>
                                  Icons.hourglass_top_rounded,
                                ConnectionState2.error =>
                                  Icons.error_outline_rounded,
                                ConnectionState2.disconnected =>
                                  Icons.power_settings_new_rounded,
                              },
                              key: ValueKey(widget.status),
                              size: widget.size * 0.2,
                              color: color,
                            ),
                          ),
                          SizedBox(height: widget.size * 0.045),
                          Text(
                            widget.label,
                            style: TextStyle(
                              fontSize: widget.size * 0.068,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                              color: scheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.trackColor,
    required this.color,
    required this.indeterminate,
    required this.progress,
    required this.rotation,
    required this.strokeWidth,
  });

  final Color trackColor;
  final Color color;
  final bool indeterminate;
  final double progress;
  final double rotation;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = strokeWidth / 2 + 2;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - inset * 2,
      size.height - inset * 2,
    );

    // track
    canvas.drawCircle(
      rect.center,
      rect.width / 2,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );

    final sweep = indeterminate ? 0.75 * math.pi : 2 * math.pi * progress;
    if (sweep <= 0) return;

    canvas.drawArc(
      rect,
      -math.pi / 2 + rotation,
      sweep,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.color != color ||
      old.progress != progress ||
      old.rotation != rotation ||
      old.indeterminate != indeterminate ||
      old.trackColor != trackColor;
}

class _HaloPainter extends CustomPainter {
  const _HaloPainter({required this.color, required this.t});

  final Color color;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.width / 2;

    for (var i = 0; i < 3; i++) {
      final phase = (t + i / 3) % 1.0;
      final r = maxR * (0.86 + 0.42 * phase);
      final opacity = (1 - phase) * 0.42;
      if (opacity <= 0) continue;
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..color = color.withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HaloPainter old) =>
      old.t != t || old.color != color;
}
