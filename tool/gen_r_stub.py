#!/usr/bin/env python3
# =============================================================================
# ساختِ خودکارِ استابِ کلاسِ R از روی پوشه‌ی res
#
# چرا؟ در ساختِ واقعی AAPT کلاسِ R را از روی res/ می‌سازد، ولی در این محیط
# اندروید SDK نداریم و کامپایلِ کاتلین را با یک استاب انجام می‌دهیم
# (tool/check_android.sh). اگر استاب با res/ هم‌گام نباشد، یا کامپایل
# «unresolved reference» می‌دهد یا — بدتر — ارجاعی به منبعی که وجود ندارد
# را از قلم می‌اندازد. پس استاب را از خودِ res/ می‌سازیم.
#
# اجرا:
#   python3 tool/gen_r_stub.py
# =============================================================================
import os
import re
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, 'android/app/src/main/res')
OUT = os.path.join(ROOT, 'tool/android_stub/com/overx/overx/R.java')

# فقط این انواع برای کدِ ما لازم‌اند (و در استاب تعریف می‌شوند)
KINDS = ('drawable', 'mipmap', 'string', 'color', 'xml')

# نگاشتِ «نوعِ منبعِ پوشه» → «نامِ کلاس در R»
FOLDER_KIND = {'drawable': 'drawable', 'mipmap': 'mipmap'}


def resource_name(filename):
    """launch_background.xml → launch_background | ic_launcher.png → ic_launcher"""
    return os.path.splitext(filename)[0]


def collect():
    found = {k: set() for k in KINDS}

    for entry in sorted(os.listdir(RES)):
        path = os.path.join(RES, entry)
        if not os.path.isdir(path):
            continue
        folder = entry.split('-')[0]          # drawable-v21 → drawable
        kind = FOLDER_KIND.get(folder)
        if kind:
            for f in sorted(os.listdir(path)):
                if os.path.isfile(os.path.join(path, f)):
                    found[kind].add(resource_name(f))
            continue

        if entry.startswith('values'):        # values, values-fa, values-night…
            for f in sorted(os.listdir(path)):
                if not f.endswith('.xml'):
                    continue
                full = os.path.join(path, f)
                try:
                    root = ET.parse(full).getroot()
                except ET.ParseError:
                    print(f'هشدار: نشدِ خواندن {full}', file=sys.stderr)
                    continue
                for child in root:
                    # <string name="x"> و <color name="x">
                    name = child.get('name')
                    if not name:
                        continue
                    if child.tag == 'string':
                        found['string'].add(name)
                    elif child.tag == 'color':
                        found['color'].add(name)
    return found


# نام‌هایی که در R.xml می‌آیند (فقط اگر در res/xml باشند)
def main():
    if not os.path.isdir(RES):
        raise SystemExit(f'پوشه‌ی res پیدا نشد: {RES}')
    found = collect()

    lines = [
        '// این فایل خودکار ساخته شده — دستی ویرایش نشود.',
        '// منبع: android/app/src/main/res (با tool/gen_r_stub.py)',
        '//',
        '// در ساختِ واقعی این کلاس را AAPT از روی res/ می‌سازد؛ اینجا فقط برای',
        '// کامپایلِ ایستا (tool/check_android.sh) است، چون اندروید SDK نداریم.',
        '// پس مقدارِ عددیِ هر فیلد اهمیتی ندارد.',
        'package com.overx.overx;',
        '',
        'public final class R {',
    ]
    base = 0x7f010000
    for i, kind in enumerate(KINDS):
        names = sorted(found.get(kind, ()))
        if not names:
            continue
        lines.append(f'    public static final class {kind} {{')
        for j, name in enumerate(names):
            ident = re.sub(r'[^A-Za-z0-9_]', '_', name)
            lines.append(f'        public static final int {ident} = '
                         f'0x{base + i * 0x10000 + j:08x};')
        lines.append('    }')
    lines.append('}')
    lines.append('')

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, 'w') as f:
        f.write('\n'.join(lines))

    counts = ' '.join(f'{k}={len(v)}' for k, v in found.items() if v)
    print(f'استابِ R ساخته شد: {OUT} ({counts})')


if __name__ == '__main__':
    main()
