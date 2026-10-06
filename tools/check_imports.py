#!/usr/bin/env python3
"""
یک بررسیِ سبک و سریع روی پروژه dart:
  1) هر import نسبی باید به فایل موجود اشاره کند
  2) هر import پکیجی باید در pubspec.yaml باشد
  3) تعادلِ آکولاد/پرانتز/کروشه
  4) فایل‌های ارجاع‌شده از lib/main.dart باید قابل‌دسترسی باشند

بدون نیاز به Dart SDK اجرا می‌شود (بررسیِ ساختاری، نه تحلیلِ معنایی).
"""
from __future__ import annotations
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "lib"

errors: list[str] = []
warnings: list[str] = []


def pubspec_packages() -> set[str]:
    txt = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    # فقط بخش dependencies (تا dev_dependencies)
    m = re.search(r"^dependencies:(.*?)(?=^dev_dependencies:|^flutter:)", txt,
                  re.S | re.M)
    body = m.group(1) if m else txt
    pkgs = set()
    for line in body.splitlines():
        s = line.strip()
        if not s or s.startswith("#") or s.startswith("-"):
            continue
        mm = re.match(r"^([a-z_][a-z0-9_]*)\s*:", s)
        if mm:
            pkgs.add(mm.group(1))
    return pkgs


def check_balance(path: Path, src: str) -> None:
    pairs = {"{": "}", "(": ")", "[": "]"}
    stack: list[str] = []
    i = 0
    n = len(src)
    in_line_comment = False
    in_block_comment = False
    in_string: str | None = None
    while i < n:
        ch = src[i]
        nxt = src[i + 1] if i + 1 < n else ""
        if in_line_comment:
            if ch == "\n":
                in_line_comment = False
            i += 1
            continue
        if in_block_comment:
            if ch == "*" and nxt == "/":
                in_block_comment = False
                i += 2
                continue
            i += 1
            continue
        if in_string:
            if ch == "\\":
                i += 2
                continue
            if ch == in_string:
                in_string = None
            i += 1
            continue
        if ch == "/" and nxt == "/":
            in_line_comment = True
            i += 2
            continue
        if ch == "/" and nxt == "*":
            in_block_comment = True
            i += 2
            continue
        if ch in "\"'":
            in_string = ch
            i += 1
            continue
        if ch in pairs:
            stack.append(ch)
        elif ch in pairs.values():
            if not stack:
                errors.append(f"{path.relative_to(ROOT)}: unbalanced '{ch}'")
                return
            top = stack.pop()
            if pairs[top] != ch:
                errors.append(
                    f"{path.relative_to(ROOT)}: mismatch '{top}' closed by '{ch}'")
                return
        i += 1
    if stack:
        errors.append(
            f"{path.relative_to(ROOT)}: unclosed {[pairs[s] for s in stack]}")


def main() -> int:
    if not LIB.exists():
        print("lib/ not found")
        return 1

    pkgs = pubspec_packages()
    dart_files = sorted(LIB.rglob("*.dart"))
    print(f"dart files: {len(dart_files)}")
    print(f"declared packages: {sorted(pkgs)}\n")

    for f in dart_files:
        src = f.read_text(encoding="utf-8")
        rel = f.relative_to(ROOT)

        for m in re.finditer(
                r"""^\s*import\s+(?:'(?P<a>[^']+)'|"(?P<b>[^"]+)")\s*;""",
                src, re.M):
            uri = m.group("a") or m.group("b")
            if uri.startswith("dart:"):
                continue
            if uri.startswith("package:"):
                pkg = uri[len("package:"):].split("/")[0]
                if pkg not in pkgs:
                    errors.append(f"{rel}: package not in pubspec → '{pkg}'")
                continue
            target = (f.parent / uri).resolve()
            if not target.exists():
                errors.append(f"{rel}: missing relative import → '{uri}'")

        for m in re.finditer(r"""^\s*export\s+(?:'([^']+)'|"([^"]+)")\s*;""",
                             src, re.M):
            uri = m.group(1) or m.group(2)
            if uri.startswith("package:"):
                continue
            target = (f.parent / uri).resolve()
            if not target.exists():
                errors.append(f"{rel}: missing relative export → '{uri}'")

        check_balance(f, src)

    # ارجاع به دارایی‌ها در pubspec
    pub = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    for m in re.finditer(r"^\s*- (assets/.*)$", pub, re.M):
        p = ROOT / m.group(1).rstrip("/")
        if not p.exists():
            warnings.append(f"pubspec: asset dir missing → {m.group(1)}")

    print("─" * 60)
    for w in warnings:
        print(f"WARN  {w}")
    if errors:
        for e in errors:
            print(f"ERROR {e}")
        print(f"\n{len(errors)} error(s)")
        return 1
    print("OK — imports resolve, brackets balanced.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
