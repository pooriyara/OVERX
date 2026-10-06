import 'package:flutter/material.dart';

import 'package:overx/theme/app_theme.dart';

/// ردیفِ تنظیمات با سوییچ.
class SwitchSetting extends StatelessWidget {
  const SwitchSetting({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.icon,
    this.danger = false,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final titleColor = danger ? StatusColors.error : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 19, color: scheme.onSurfaceVariant),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: titleColor ?? scheme.onSurface,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.45,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// ردیفِ تنظیمات با انتخاب از لیست.
class OptionSetting<T> extends StatelessWidget {
  const OptionSetting({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onChanged,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final T value;
  final List<T> options;
  final String Function(T) labelOf;
  final ValueChanged<T?> onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 19, color: scheme.onSurfaceVariant),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurface,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.45,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 148,
            child: DropdownButtonFormField<T>(
              initialValue: value,
              isDense: true,
              isExpanded: true,
              items: options
                  .map((o) => DropdownMenuItem<T>(
                        value: o,
                        child: Text(
                          labelOf(o),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ))
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// ردیفِ تنظیمات متنی (عدد یا رشته).
class TextSetting extends StatefulWidget {
  const TextSetting({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onSubmit,
    this.icon,
    this.numeric = false,
    this.ltr = false,
    this.width = 200,
  });

  final String title;
  final String? subtitle;
  final String value;
  final ValueChanged<String> onSubmit;
  final IconData? icon;
  final bool numeric;
  final bool ltr;
  final double width;

  @override
  State<TextSetting> createState() => _TextSettingState();
}

class _TextSettingState extends State<TextSetting> {
  late final TextEditingController _c;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.value);
    _focus = FocusNode();
    _focus.addListener(() {
      if (!_focus.hasFocus) {
        widget.onSubmit(_c.text.trim());
      }
    });
  }

  @override
  void didUpdateWidget(covariant TextSetting old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !_focus.hasFocus) {
      _c.text = widget.value;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          if (widget.icon != null) ...[
            Icon(widget.icon, size: 19, color: scheme.onSurfaceVariant),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurface,
                  ),
                ),
                if (widget.subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    widget.subtitle!,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.45,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: widget.width,
            child: TextField(
              controller: _c,
              focusNode: _focus,
              textDirection: widget.ltr ? TextDirection.ltr : null,
              textAlign: widget.ltr ? TextAlign.start : TextAlign.start,
              keyboardType: widget.numeric
                  ? TextInputType.number
                  : TextInputType.text,
              onSubmitted: (v) => widget.onSubmit(v.trim()),
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// ردیفِ اکشن (کلیک‌پذیر).
class ActionSetting extends StatelessWidget {
  const ActionSetting({
    super.key,
    required this.title,
    this.subtitle,
    this.onTap,
    this.icon,
    this.trailing,
    this.danger = false,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final IconData? icon;
  final Widget? trailing;
  final bool danger;

  /// وقتی false باشد ردیف خاکستری می‌شود و لمس نمی‌پذیرد.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = danger
        ? StatusColors.error
        : (enabled ? scheme.onSurface : scheme.onSurfaceVariant);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 19, color: danger
                    ? StatusColors.error
                    : scheme.onSurfaceVariant),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: color,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.45,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              trailing ??
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: scheme.outline,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// جداکننده‌ی بین ردیف‌ها داخل یک کارت.
class SettingDivider extends StatelessWidget {
  const SettingDivider({super.key});

  @override
  Widget build(BuildContext context) => Divider(
        height: 1,
        indent: 16,
        endIndent: 16,
        color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.55),
      );
}
