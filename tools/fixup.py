#!/usr/bin/env python3
"""
اصلاح‌های سراسری روی پروژه برای سازگاری با Flutter/Dart جدید:
  • تبديل importهای نسبی به package:
  • withOpacity(...) → withValues(alpha: ...)
  • MaterialState*   → WidgetState*
  • setterهای SettingsController → Future<void>
  • DropdownButtonFormField value: → initialValue:
"""
from __future__ import annotations
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "lib"
PKG = "overx"

changed: list[str] = []


def to_package_uri(rel: str, from_file: Path) -> str | None:
    if not rel.startswith("."):
        return None
    base = (from_file.parent / rel).resolve()
    try:
        r = base.relative_to(LIB.resolve())
    except ValueError:
        return None
    return f"package:{PKG}/{r.as_posix()}"


def fix_imports(f: Path, src: str) -> str:
    def repl(m):
        q = m.group("q")
        uri = m.group("uri")
        new = to_package_uri(uri, f)
        if new is None:
            return m.group(0)
        return f"import {q}{new}{q};"

    return re.sub(r"""import (?P<q>['"])(?P<uri>[^'"]+)(?P=q);""", repl, src)


def main() -> None:
    for f in sorted(LIB.rglob("*.dart")):
        src = f.read_text(encoding="utf-8")
        orig = src

        # 1) package: imports
        src = fix_imports(f, src)

        # 2) withOpacity → withValues
        src = re.sub(r"\.withOpacity\(([^()]*(?:\([^()]*\))?[^()]*)\)",
                     r".withValues(alpha: \1)", src)

        # 3) MaterialState → WidgetState
        src = src.replace("MaterialStateProperty", "WidgetStateProperty")
        src = src.replace("MaterialState.", "WidgetState.")

        # 4) DropdownButtonFormField value → initialValue
        src = src.replace("              value: value,\n              isDense: true,",
                          "              initialValue: value,\n              isDense: true,")

        if src != orig:
            f.write_text(src, encoding="utf-8")
            changed.append(str(f.relative_to(ROOT)))

    # 5) setterهای تنظیمات باید Future<void> برگردانند
    p = LIB / "core" / "engine" / "engine_controller.dart"
    s = p.read_text(encoding="utf-8")
    before = s
    s = re.sub(r"  void (set\w+)\(([^)]*)\) =>\s*\n?\s*unawaited\(_save\((.*?)\)\);",
               r"  Future<void> \1(\2) async => _save(\3);", s, flags=re.S)
    s = s.replace("  void setCore(CoreType v) => unawaited(_save(state.copyWith(\n"
                  "        activeCore: v == CoreType.singbox ? CoreTypePref.singbox : CoreTypePref.xray,\n"
                  "      )));",
                  "  Future<void> setCore(CoreType v) => _save(state.copyWith(\n"
                  "      activeCore:\n"
                  "          v == CoreType.singbox ? CoreTypePref.singbox : CoreTypePref.xray));")
    s = re.sub(r"  void (set\w+)\(([^)]*)\) =>\s*\n?\s*unawaited\(_save\((.*?)\)\);",
               r"  Future<void> \1(\2) async => _save(\3);", s, flags=re.S)
    if s != before:
        p.write_text(s, encoding="utf-8")
        changed.append(str(p.relative_to(ROOT)))

    print(f"patched {len(changed)} file(s)")
    for c in changed:
        print("  ", c)


if __name__ == "__main__":
    main()
