#!/usr/bin/env python3
# =============================================================================
# ساخت آیکن و لوگوی برنامه از روی تصویرِ منبع
#
# ورودی: یک تصویر که دو بخش دارد
#   * بالا: نشانه + نامِ برنامه    → لوگو (داخلِ برنامه، صفحه‌ی آغازین)
#   * پایین: آیکنِ مربعِ گوشه‌گرد   → آیکنِ برنامه در همه‌ی پلتفرم‌ها
#
# تصویرِ منبع ممکن است «شفافیتِ» واقعی نداشته باشد و پس‌زمینه به‌صورتِ
# شطرنجیِ سفید/خاکستری داخلِ پیکسل‌ها پخته شده باشد (خروجیِ برخی ابزارها).
# این اسکریپت آن شطرنجی را با flood-fill از لبه‌ها بازسازی می‌کند: پس‌زمینه
# خاکستریِ روشنِ به‌هم‌پیوسته که به لبه می‌رسد شفاف می‌شود و هرچه داخلِ طرح
# محصور است (حتی حروفِ سفیدِ OVERX) کدر می‌ماند.
#
# خروجی:
#   assets/logo.png  assets/logo_white.png
#   assets/icon.png  assets/icon_white.png        (نشانه — سربرگِ منو)
#   android/.../mipmap-*/ic_launcher.png          (آیکنِ مربعِ گوشه‌گرد)
#   android/.../drawable/ic_launcher_foreground.png + mipmap-anydpi-v26
#   android/.../drawable-*/ic_stat_overx.png      (نوارِ وضعیت — تک‌رنگ)
#   android/.../drawable-{,night-}*/launch_logo.png
#   windows/runner/resources/app_icon.ico
#   macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_*.png
#   ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-*.png
#
# اجرا:
#   python3 tool/gen_icons.py <مسیرِ تصویر>
# =============================================================================
import os
import sys
import json
from collections import deque
from PIL import Image

SRC = sys.argv[1] if len(sys.argv) > 1 else 'tool/assets/logo_source.png'
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


# --------------------------------------------------------------------------- #
# بازسازیِ alpha از پس‌زمینه‌ی شطرنجی
# --------------------------------------------------------------------------- #
def reconstruct_alpha(im):
    """تصویرِ RGB با پس‌زمینه‌ی شطرنجی را RGBA می‌کند.

    پیکسل «شبهِ پس‌زمینه» است اگر کم‌اشباع و روشن باشد. سپس از همه‌ی لبه‌ها
    روی پیکسل‌های شبهِ پس‌زمینه flood-fill می‌کنیم؛ آن‌چه از لبه قابل‌رسیدن
    است پس‌زمینه‌ی واقعی (شفاف) و بقیه — شاملِ حفره‌های محصور مثلِ داخلِ
    حروفِ سفید — محتوا (کدر) است.
    """
    import numpy as np
    im = im.convert('RGBA')
    arr = np.asarray(im).astype(np.int16)
    rgb = arr[..., :3]
    lum = np.asarray(im.convert('L')).astype(np.int16)
    sat = rgb.max(axis=2) - rgb.min(axis=2)
    bg = (sat < 32) & (lum > 214)

    h, w = bg.shape
    exterior = np.zeros((h, w), bool)
    dq = deque()
    edge = []
    edge += [(0, x) for x in range(w)]
    edge += [(h - 1, x) for x in range(w)]
    edge += [(y, 0) for y in range(h)]
    edge += [(y, w - 1) for y in range(h)]
    for y, x in edge:
        if bg[y, x] and not exterior[y, x]:
            exterior[y, x] = True
            dq.append((y, x))
    while dq:
        y, x = dq.popleft()
        for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
            if 0 <= ny < h and 0 <= nx < w and not exterior[ny, nx] \
                    and bg[ny, nx]:
                exterior[ny, nx] = True
                dq.append((ny, nx))

    # حالتِ ۱: حفره‌های محصور کدر می‌مانند (برای لوگو — داخلِ حروفِ سفید).
    fill = np.asarray(im).copy()
    fill[..., 3] = np.where(exterior, 0, 255).astype(np.uint8)
    fill_im = Image.fromarray(fill, 'RGBA')

    # حالتِ ۲: هر پیکسلِ شبهِ پس‌زمینه شفاف است (برای نشانه — سوراخِ حلقه
    # باید شفاف بماند). سپس یک closing کوچک، ذراتِ ریزِ داخلِ تیغه‌ها را
    # پر می‌کند ولی سوراخِ بزرگِ حلقه دست‌نخورده می‌ماند.
    nofill = np.asarray(im).copy()
    nofill[..., 3] = np.where(bg, 0, 255).astype(np.uint8)
    from PIL import ImageFilter
    a = Image.fromarray(nofill[..., 3], 'L')
    a = a.filter(ImageFilter.MaxFilter(7)).filter(ImageFilter.MinFilter(7))
    nofill[..., 3] = np.asarray(a)
    nofill_im = Image.fromarray(nofill, 'RGBA')

    return fill_im, nofill_im


def _has_real_alpha(im):
    """اگر تصویر از قبل alpha واقعی دارد (شفاف در گوشه‌ها) همان را نگه دار."""
    if im.mode not in ('RGBA', 'LA'):
        return False
    a = im.convert('RGBA').split()[3]
    hist = a.histogram()
    return hist[0] > (im.width * im.height) // 50


# --------------------------------------------------------------------------- #
# ابزارهای هندسی
# --------------------------------------------------------------------------- #
def _opaque_mask(im, thr=140):
    return im.split()[3].point(lambda v: 255 if v > thr else 0)


def content_bbox(mask, ratio=0.02, pad=3):
    try:
        import numpy as np
        arr = np.asarray(mask) > 0
        cols = arr.sum(axis=0)
        rows = arr.sum(axis=1)
    except ImportError:
        cols = [mask.crop((x, 0, x + 1, mask.height)).histogram()[255]
                for x in range(mask.width)]
        rows = [mask.crop((0, y, mask.width, y + 1)).histogram()[255]
                for y in range(mask.height)]
    col_min = max(2, max(cols) * ratio)
    row_min = max(2, max(rows) * ratio)
    xs = [i for i, v in enumerate(cols) if v >= col_min]
    ys = [i for i, v in enumerate(rows) if v >= row_min]
    if not xs or not ys:
        return None
    return (max(0, xs[0] - pad), max(0, ys[0] - pad),
            min(mask.width, xs[-1] + 1 + pad), min(mask.height, ys[-1] + 1 + pad))


def find_split_y(im):
    """شکافِ افقیِ خالی میانِ بخشِ بالا و پایین را پیدا می‌کند."""
    mask = _opaque_mask(im)
    rows = [mask.crop((0, y, im.width, y + 1)).histogram()[255]
            for y in range(im.height)]
    content = [i for i, v in enumerate(rows) if v > 0]
    if not content:
        raise SystemExit('تصویر خالی است')
    # بزرگ‌ترین دنباله‌ی ردیفِ (تقریباً) خالی در میانِ محتوا
    best_len, best_start = 0, None
    cur_len, cur_start = 0, None
    for i in range(content[0], content[-1] + 1):
        if rows[i] < 5:
            if cur_len == 0:
                cur_start = i
            cur_len += 1
            if cur_len > best_len:
                best_len, best_start = cur_len, cur_start
        else:
            cur_len = 0
    if best_len < 2:
        raise SystemExit('شکافِ میانِ دو بخش پیدا نشد')
    return best_start + best_len // 2


def crop_region(im, y0, y1):
    mask = _opaque_mask(im).crop((0, y0, im.width, y1))
    box = content_bbox(mask)
    if box is None:
        raise SystemExit(f'هیچ محتوایی در {y0}..{y1} پیدا نشد')
    x0, top, x1, bottom = box
    return im.crop((x0, y0 + top, x1, y0 + bottom))


def extract_mark(im, y0, y1):
    """نشانه (چپِ بخشِ بالا) را با مؤلفه‌های همبندِ بلند جدا می‌کند."""
    region = im.crop((0, y0, im.width, y1))
    mask = _opaque_mask(region)
    # پایین‌نمونه برای سرعت
    scale = 4
    small = mask.resize((mask.width // scale, mask.height // scale),
                        Image.NEAREST)
    sw, sh = small.size
    px = small.load()
    seen = [[False] * sw for _ in range(sh)]
    comps = []
    for sy in range(sh):
        for sx in range(sw):
            if px[sx, sy] and not seen[sy][sx]:
                dq = deque([(sx, sy)])
                seen[sy][sx] = True
                xs, ys = [sx], [sy]
                while dq:
                    cx, cy = dq.popleft()
                    for nx, ny in ((cx + 1, cy), (cx - 1, cy),
                                   (cx, cy + 1), (cx, cy - 1)):
                        if 0 <= nx < sw and 0 <= ny < sh and not seen[ny][nx] \
                                and px[nx, ny]:
                            seen[ny][nx] = True
                            dq.append((nx, ny))
                            xs.append(nx)
                            ys.append(ny)
                comps.append((min(xs), min(ys), max(xs), max(ys)))
    top_h = y1 - y0
    # نشانه: مؤلفه‌ی بلندِ سمتِ چپ (حروفِ نام کوتاه‌ترند و سمتِ راست‌اند).
    # c = (x0, y0, x1, y1)؛ بلندی = y1 - y0.
    mark_boxes = [c for c in comps
                  if (c[3] - c[1]) * scale >= top_h * 0.5
                  and c[0] * scale < im.width * 0.3]
    if not mark_boxes:
        raise SystemExit('نشانه در بخشِ بالا پیدا نشد')
    x0 = min(c[0] for c in mark_boxes) * scale
    y0b = min(c[1] for c in mark_boxes) * scale
    x1 = (max(c[2] for c in mark_boxes) + 1) * scale
    y1b = (max(c[3] for c in mark_boxes) + 1) * scale
    return im.crop((max(0, x0 - 3), y0 + max(0, y0b - 3),
                    min(im.width, x1 + 3), y0 + min(top_h, y1b + 3)))


def clean_small(im, min_frac=0.002):
    """حذفِ ذراتِ ریزِ جداافتاده (مثلِ لبه‌ی حرفِ کنارِ نشانه)."""
    from collections import deque as _dq
    import numpy as np
    a = np.asarray(im.convert('RGBA'))
    alpha = a[..., 3]
    on = alpha > 128
    h, w = on.shape
    min_area = max(8, int(min_frac * w * h))
    seen = np.zeros((h, w), bool)
    for y in range(h):
        for x in range(w):
            if on[y, x] and not seen[y, x]:
                dq = _dq([(y, x)])
                seen[y, x] = True
                pts = []
                while dq:
                    cy, cx = dq.popleft()
                    pts.append((cy, cx))
                    for ny, nx in ((cy + 1, cx), (cy - 1, cx),
                                   (cy, cx + 1), (cy, cx - 1)):
                        if 0 <= ny < h and 0 <= nx < w and not seen[ny, nx] \
                                and on[ny, nx]:
                            seen[ny, nx] = True
                            dq.append((ny, nx))
                if len(pts) < min_area:
                    for cy, cx in pts:
                        a[cy, cx, 3] = 0
    return Image.fromarray(a, 'RGBA')


def fit_square(im, size, ratio):
    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    target = int(size * ratio)
    resized = im.copy()
    resized.thumbnail((target, target), Image.LANCZOS)
    canvas.paste(resized, ((size - resized.width) // 2,
                           (size - resized.height) // 2), resized)
    return canvas


def whiten(im):
    r, g, b, a = im.split()
    white = Image.new('L', im.size, 255)
    return Image.merge('RGBA', (white, white, white, a))


def silhouette(im):
    alpha = im.split()[3].point(lambda v: 255 if v > 128 else 0)
    white = Image.new('L', im.size, 255)
    return Image.merge('RGBA', (white, white, white, alpha))


def quantize(im, colors=128):
    return im.convert('RGBA').quantize(colors=colors,
                                       method=Image.FASTOCTREE)


def save(im, path, shrink=False):
    full = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    if shrink:
        im = quantize(im)
    im.save(full, optimize=True)
    size = os.path.getsize(full)
    print(f'  {path}  {im.width}×{im.height}  ({size // 1024} کیلوبایت)')


def dominant_dark(im):
    """رنگِ غالبِ پس‌زمینه‌ی تیره‌ی آیکن — برای پس‌زمینه‌ی تطبیقی و iOS."""
    import numpy as np
    small = np.asarray(im.convert('RGBA').resize((64, 64))).astype(int)
    a = small[..., 3]
    lum = small[..., :3].mean(axis=2)
    m = (a >= 128) & (lum <= 90)
    if not m.any():
        return (10, 12, 26)
    px = small[..., :3][m]
    key = (px // 32 * 32)
    uniq, counts = np.unique(key.reshape(-1, 3), axis=0, return_counts=True)
    return tuple(int(v) for v in uniq[counts.argmax()])


def main():
    raw = Image.open(SRC)
    if _has_real_alpha(raw):
        src_fill = src_mark = raw.convert('RGBA')
        print(f'منبع: {SRC} ({src_fill.width}×{src_fill.height}) — alpha واقعی')
    else:
        src_fill, src_mark = reconstruct_alpha(raw)
        print(f'منبع: {SRC} ({src_fill.width}×{src_fill.height}) — alpha بازسازی شد')

    split = find_split_y(src_fill)
    print(f'مرزِ دو بخش: y={split}')

    logo = crop_region(src_fill, 0, split)           # نشانه + نام
    app_icon = clean_small(crop_region(src_mark, split, src_mark.height))
    mark = clean_small(extract_mark(src_mark, 0, split))  # فقط نشانه
    print(f'لوگو: {logo.width}×{logo.height} | آیکن: {app_icon.width}×'
          f'{app_icon.height} | نشانه: {mark.width}×{mark.height}')

    dark = dominant_dark(app_icon)
    dark_hex = '#%02X%02X%02X' % dark
    print(f'رنگِ پس‌زمینه‌ی تیره: {dark_hex}')

    # ------------------------------------------------------------------ لوگو
    logo_out = logo.copy()
    logo_out.thumbnail((1024, 1024), Image.LANCZOS)
    save(logo_out, 'assets/logo.png', shrink=True)
    save(whiten(logo_out), 'assets/logo_white.png', shrink=True)
    # نشانه برای سربرگِ منو و جاهای مربعِ رابط
    save(fit_square(mark, 512, 1.0), 'assets/icon.png', shrink=True)
    save(whiten(fit_square(mark, 512, 1.0)), 'assets/icon_white.png',
         shrink=True)

    # ---------------------------------------------------- اندروید: کلاسیک
    print('اندروید — آیکنِ کلاسیک (مربعِ گوشه‌گرد):')
    for name, size in (('mdpi', 48), ('hdpi', 72), ('xhdpi', 96),
                       ('xxhdpi', 144), ('xxxhdpi', 192)):
        save(fit_square(app_icon, size, 1.0),
             f'android/app/src/main/res/mipmap-{name}/ic_launcher.png')

    # --------------------------------------------------- اندروید: تطبیقی
    print('اندروید — آیکنِ تطبیقی (۸ به بالا):')
    save(fit_square(mark, 432, 0.66),
         'android/app/src/main/res/drawable/ic_launcher_foreground.png')
    values = os.path.join(ROOT, 'android/app/src/main/res/values')
    os.makedirs(values, exist_ok=True)
    with open(os.path.join(values, 'ic_launcher_background.xml'), 'w') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<resources>\n'
                f'    <!-- رنگِ پس‌زمینه‌ی آیکنِ تطبیقی: همان تیره‌ی خودِ آیکن -->'
                '\n'
                f'    <color name="ic_launcher_background">{dark_hex}</color>\n'
                '</resources>\n')
    print('  android/app/src/main/res/values/ic_launcher_background.xml')
    anydpi = os.path.join(ROOT, 'android/app/src/main/res/mipmap-anydpi-v26')
    os.makedirs(anydpi, exist_ok=True)
    for name in ('ic_launcher.xml', 'ic_launcher_round.xml'):
        with open(os.path.join(anydpi, name), 'w') as f:
            f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                    '<adaptive-icon '
                    'xmlns:android="http://schemas.android.com/'
                    'schemas/android/apk/res/android">\n'
                    '    <background '
                    'android:drawable="@color/ic_launcher_background" />\n'
                    '    <foreground '
                    'android:drawable="@drawable/ic_launcher_foreground" '
                    '/>\n'
                    '</adaptive-icon>\n')
        print(f'  android/app/src/main/res/mipmap-anydpi-v26/{name}')

    # ------------------------------------------- اندروید: صفحه‌ی آغازین
    print('اندروید — لوگوی صفحه‌ی آغازین:')
    for folder, width in (('mdpi', 240), ('hdpi', 360), ('xhdpi', 480),
                          ('xxhdpi', 720), ('xxxhdpi', 960)):
        splash = logo.copy()
        splash.thumbnail((width, width), Image.LANCZOS)
        save(splash,
             f'android/app/src/main/res/drawable-{folder}/launch_logo.png',
             shrink=True)
        save(whiten(splash),
             f'android/app/src/main/res/drawable-night-{folder}/'
             f'launch_logo.png', shrink=True)

    # --------------------------------------------- اندروید: نوارِ وضعیت
    print('اندروید — آیکنِ نوارِ وضعیت (تک‌رنگ):')
    stat = silhouette(fit_square(mark, 1024, 0.86))
    for folder, size in (('mdpi', 24), ('hdpi', 36), ('xhdpi', 48),
                         ('xxhdpi', 72), ('xxxhdpi', 96)):
        save(stat.resize((size, size), Image.LANCZOS),
             f'android/app/src/main/res/drawable-{folder}/ic_stat_overx.png')

    # ------------------------------------------------------------ ویندوز
    print('ویندوز:')
    ico = fit_square(app_icon, 256, 1.0)
    ico.save(os.path.join(ROOT, 'windows/runner/resources/app_icon.ico'),
             sizes=[(256, 256), (128, 128), (64, 64), (48, 48), (32, 32),
                    (24, 24), (16, 16)])
    print('  windows/runner/resources/app_icon.ico')

    # ------------------------------------------------------------- مک‌او‌اس
    print('مک‌او‌اس:')
    for size in (16, 32, 64, 128, 256, 512, 1024):
        save(fit_square(app_icon, size, 1.0),
             f'macos/Runner/Assets.xcassets/AppIcon.appiconset/'
             f'app_icon_{size}.png', shrink=size >= 256)

    # ----------------------------------------------------------------- iOS
    print('آی‌اواس:')
    contents = os.path.join(
        ROOT, 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json')
    if os.path.exists(contents):
        data = json.load(open(contents))
        for img in data['images']:
            filename = img.get('filename')
            if not filename:
                continue
            stem = filename.replace('Icon-App-', '').replace('.png', '')
            dims, _, scale = stem.partition('@')
            base = float(dims.split('x')[0])
            mult = float(scale.replace('x', '') or 1)
            px = int(base * mult)
            # آیکنِ اپ‌استور نباید شفافیت داشته باشد؛ پس آیکنِ گوشه‌گرد را
            # روی رنگِ تیره‌ی خودش می‌نشانیم و alpha را حذف می‌کنیم.
            canvas = Image.new('RGBA', (px, px), dark + (255,))
            layer = fit_square(app_icon, px, 1.0)
            canvas.alpha_composite(layer)
            save(canvas.convert('RGB'),
                 f'ios/Runner/Assets.xcassets/AppIcon.appiconset/{filename}',
                 shrink=px >= 256)
    else:
        print('  (Contents.json پیدا نشد — رد شد)')


if __name__ == '__main__':
    main()
