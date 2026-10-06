#!/usr/bin/env python3
"""دور دوم اصلاح‌ها: importهای گم‌شده، APIهای nullable، حذف کد مرده."""
from __future__ import annotations
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "lib"
PKG = "overx"


def pkg_uri(rel: str, f: Path) -> str | None:
    base = (f.parent / rel).resolve()
    try:
        r = base.relative_to(LIB.resolve())
    except ValueError:
        return None
    return f"package:{PKG}/{r.as_posix()}"


def convert_bare_imports(f: Path, src: str) -> str:
    def repl(m):
        q, uri = m.group("q"), m.group("uri")
        if uri.startswith("dart:") or uri.startswith("package:"):
            return m.group(0)
        if not uri.startswith("."):
            # import هم‌سطح بدون './' — فقط اگر داخل lib حل شود
            new = pkg_uri("./" + uri, f)
            if new is None:
                return m.group(0)
            return f"import {q}{new}{q};"
        new = pkg_uri(uri, f)
        return f"import {q}{new}{q};" if new else m.group(0)

    return re.sub(r"""import (?P<q>['"])(?P<uri>[^'"]+)(?P=q);""", repl, src)


def add_import(src: str, uri: str) -> str:
    if f"'{uri}'" in src or f'"{uri}"' in src:
        return src
    lines = src.split("\n")
    # بعد از آخرین import
    last = max(i for i, l in enumerate(lines) if l.startswith("import "))
    lines.insert(last + 1, f"import '{uri}';")
    return "\n".join(lines)


def remove_import(src: str, uri: str) -> str:
    return re.sub(rf"^import ['\"]{re.escape(uri)}['\"];\n", "", src,
                  flags=re.M)


def edit(path: str, fn) -> None:
    p = LIB / path
    s = p.read_text(encoding="utf-8")
    out = fn(s)
    if out != s:
        p.write_text(out, encoding="utf-8")
        print("patched", path)


# ---------------------------------------------------------------------------
# 1) importهای هم‌سطحِ بدون './' در整个 lib
# ---------------------------------------------------------------------------
for f in sorted(LIB.rglob("*.dart")):
    s = f.read_text(encoding="utf-8")
    out = convert_bare_imports(f, s)
    if out != s:
        f.write_text(out, encoding="utf-8")
        print("imports:", f.relative_to(ROOT))

# ---------------------------------------------------------------------------
# 2) app.dart / app_shell.dart → ThemeModePref
# ---------------------------------------------------------------------------
edit("app.dart", lambda s: add_import(
    convert_bare_imports(LIB / "app.dart", s),
    f"package:{PKG}/core/models/settings.dart"))


def fix_shell(s: str) -> str:
    s = add_import(s, f"package:{PKG}/core/models/settings.dart")
    return s


edit("ui/shell/app_shell.dart", fix_shell)

# ---------------------------------------------------------------------------
# 3) core_process.dart → CoreType
# ---------------------------------------------------------------------------
edit("core/process/core_process.dart",
     lambda s: add_import(s, f"package:{PKG}/core/engine/core_type.dart"))

# ---------------------------------------------------------------------------
# 4) engine_controller → SettingsRepository / ProfileRepository / AppLang
# ---------------------------------------------------------------------------


def fix_engine(s: str) -> str:
    s = add_import(s, f"package:{PKG}/core/storage/repositories.dart")
    s = add_import(s, f"package:{PKG}/l10n/strings.dart")
    # unawaited محلی را حذف می‌کنیم؛ dart:async خودش دارد
    s = re.sub(r"\nvoid unawaited\(Future<dynamic> f\) \{\}\n", "", s)
    return s


edit("core/engine/engine_controller.dart", fix_engine)

# ---------------------------------------------------------------------------
# 5) حذف unawaited محلی در core_process / stats_source
# ---------------------------------------------------------------------------
edit("core/process/core_process.dart",
     lambda s: re.sub(r"\nvoid unawaited\(Future<void> f\) \{\}\n", "", s))


def fix_stats(s: str) -> str:
    s = re.sub(r"\nvoid unawaited\(Future<void> f\) \{\}\n", "", s)
    # فیلدهای بلااستفاده
    s = s.replace("  int _totalUp = 0;\n  int _totalDown = 0;\n", "")
    s = s.replace("    _totalUp = 0;\n    _totalDown = 0;\n", "")
    s = s.replace("            // sing-box مقدار را به صورت تجمعی می‌فرستد\n"
                  "            _totalUp = up;\n            _totalDown = down;\n",
                  "            // sing-box مقدار را به صورت تجمعی می‌فرستد\n")
    return s


edit("core/stats/stats_source.dart", fix_stats)

# ---------------------------------------------------------------------------
# 6) حذف importهای بلااستفاده
# ---------------------------------------------------------------------------
edit("main.dart",
     lambda s: remove_import(s,
                             "package:flutter_localizations/flutter_localizations.dart"))
edit("core/config/singbox_config_builder.dart",
     lambda s: remove_import(s, f"package:{PKG}/core/engine/core_type.dart"))
edit("ui/logs/logs_page.dart",
     lambda s: remove_import(s, f"package:{PKG}/l10n/strings.dart"))
edit("ui/shell/app_drawer.dart",
     lambda s: remove_import(s, f"package:{PKG}/l10n/strings.dart"))

# ---------------------------------------------------------------------------
# 7) متغیر بلااستفاده در _ErrorCard
# ---------------------------------------------------------------------------


def fix_home(s: str) -> str:
    return s.replace("""  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),""",
        """  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),""")


edit("ui/home/home_page.dart", fix_home)

# ---------------------------------------------------------------------------
# 8) ActionSetting.onTap → nullable
# ---------------------------------------------------------------------------


def fix_tile(s: str) -> str:
    s = s.replace("  final String? subtitle;\n  final VoidCallback onTap;\n"
                  "  final IconData? icon;\n  final Widget? trailing;\n"
                  "  final bool danger;",
                  "  final String? subtitle;\n  final VoidCallback? onTap;\n"
                  "  final IconData? icon;\n  final Widget? trailing;\n"
                  "  final bool danger;")
    s = s.replace("    required this.onTap,\n    this.icon,\n    this.trailing,\n"
                  "    this.danger = false,",
                  "    this.onTap,\n    this.icon,\n    this.trailing,\n"
                  "    this.danger = false,")
    return s


edit("ui/widgets/setting_tile.dart", fix_tile)

print("\ndone.")
