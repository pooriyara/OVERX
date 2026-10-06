#!/usr/bin/env python3
"""ساختِ گالریِ HTML از تصاویرِ طلاییِ `tool/goldens/`.

خروجی یک فایلِ کاملاً مستقل است (تصاویر به صورت base64 درونِ خودش جاسازی
می‌شوند)، بنابراین در مرورگر و در پیش‌نمایشِ sandbox شده هم درست نشان
داده می‌شود.

اجرا:
    python3 tool/build_gallery.py [مسیرِ خروجی]

پیش‌فرضِ خروجی: ../screenshots_gallery.html
"""

from __future__ import annotations

import base64
import pathlib
import sys

# (نامِ فایل بدون پسوند، عنوانِ فارسی، زیرنویسِ انگلیسی)
SHOTS = [
    ("01_home_desktop_dark_fa", "خانه — دسکتاپ، تاریک، فارسی", "Home — desktop, dark, Persian"),
    ("02_home_desktop_light_fa", "خانه — دسکتاپ، روشن", "Home — desktop, light"),
    ("03_home_desktop_dark_en", "خانه — انگلیسی (LTR)", "Home — English (LTR)"),
    ("04_home_mobile_dark_fa", "خانه — موبایل", "Home — mobile"),
    ("05_drawer_mobile_dark_fa", "منوی همبرگری — موبایل", "Hamburger drawer — mobile"),
    ("06_settings_mobile_dark_fa", "تنظیمات — موبایل", "Settings — mobile"),
    ("07_profiles_desktop_dark_fa", "پروفایل‌ها", "Profiles"),
    ("08_cores_desktop_dark_fa", "هسته‌ها", "Cores"),
    ("09_per_app_mobile_dark_fa", "مسیریابیِ هر برنامه — موبایل", "Per-app proxy — mobile"),
]

HEAD = """<!DOCTYPE html>
<html lang="fa" dir="rtl">
<head><meta charset="utf-8"><title>OVERX — رابط کاربری</title>
<style>
  :root{ --bg:#0b0f14; --card:#131a22; --line:#222d3a; --fg:#e6edf3; --dim:#8b98a5; --acc:#4cc2ff; }
  *{box-sizing:border-box}
  body{margin:0;background:var(--bg);color:var(--fg);
       font-family:"Vazirmatn",-apple-system,"Segoe UI",system-ui,sans-serif;
       padding:32px 24px 56px}
  header{max-width:1200px;margin:0 auto 28px}
  h1{margin:0 0 6px;font-size:26px;letter-spacing:.2px}
  .sub{color:var(--dim);font-size:14px;line-height:1.9}
  .sub code{background:#1b2531;padding:2px 6px;border-radius:5px;color:var(--acc)}
  .grid{max-width:1200px;margin:0 auto;display:grid;gap:22px;
         grid-template-columns:repeat(auto-fill,minmax(340px,1fr))}
  figure{margin:0;background:var(--card);border:1px solid var(--line);
          border-radius:14px;overflow:hidden;transition:.18s}
  figure:hover{border-color:var(--acc);transform:translateY(-2px)}
  img{display:block;width:100%;height:auto}
  figcaption{padding:11px 14px;font-size:13px;line-height:1.7;border-top:1px solid var(--line)}
  figcaption span{color:var(--dim);font-size:12px}
</style></head>
<body>
<header>
  <h1>OVERX — نمای رابط کاربری</h1>
  <div class="sub">
    فلاتر · فارسی (RTL) و انگلیسی · هسته‌های sing-box و Xray<br>
    تولیدشده با <code>flutter test tool/generate_screenshots_test.dart --update-goldens</code>
  </div>
</header>
<div class="grid">
"""

FOOT = """</div>
</body>
</html>
"""


def main(argv: list[str]) -> int:
    here = pathlib.Path(__file__).resolve().parent
    goldens = here / "goldens"
    out = pathlib.Path(argv[1]) if len(argv) > 1 else here.parent.parent / "screenshots_gallery.html"

    parts = [HEAD]
    for stem, fa, en in SHOTS:
        path = goldens / f"{stem}.png"
        if not path.exists():
            print(f"هشدار: {path} وجود ندارد — رد شد", file=sys.stderr)
            continue
        b64 = base64.b64encode(path.read_bytes()).decode("ascii")
        parts.append(
            "  <figure>\n"
            f'    <img src="data:image/png;base64,{b64}" alt="{en}">\n'
            f'    <figcaption><b>{fa}</b><br><span dir="ltr">{en}</span></figcaption>\n'
            "  </figure>\n"
        )
    parts.append(FOOT)

    out.write_text("".join(parts), encoding="utf-8")
    kb = out.stat().st_size / 1024
    print(f"{out} نوشته شد ({kb:.0f} کیلوبایت، {len(parts) - 2} تصویر)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
