import 'package:flutter/material.dart';

import 'package:overx/core/engine/core_type.dart';

/// انتخاب‌گرِ هسته (sing-box / Xray) به صورت segmented control.
class CoreSwitcher extends StatelessWidget {
  const CoreSwitcher({
    super.key,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  final CoreType selected;
  final ValueChanged<CoreType> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: CoreType.values.map((c) {
          final isSel = c == selected;
          return Padding(
            padding: const EdgeInsetsDirectional.only(
              start: 2,
              end: 2,
            ),
            child: _Segment(
              label: c.displayName,
              color: c.brandColor,
              selected: isSel,
              enabled: enabled,
              onTap: () => onChanged(c),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.color,
    required this.enabled,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: selected ? scheme.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(99),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(99),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: selected ? color : scheme.outline,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant.withValues(alpha: 
                            enabled ? 1 : 0.45),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
