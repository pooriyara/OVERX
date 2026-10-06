#!/usr/bin/env bash
# =============================================================================
# آماده‌سازی محیط توسعه
#
# Flutter SDK در /var/tmp/sdk نصب می‌شود چون پوشه‌های snapshot فضای کافی
# ندارند — یعنی ممکن است بین نشست‌ها پاک شود. استفاده:
#
#   source tool/env.sh
#   flutter test
#
# یا خلاصه:
#   source tool/env.sh && check
# =============================================================================

export PATH="/var/tmp/sdk/flutter/bin:$PATH"
export PUB_CACHE="/var/tmp/sdk/.pub-cache"
export PATH="/var/tmp/kotlinc/bin:$PATH"

ensure_flutter() {
  if [ ! -x /var/tmp/sdk/flutter/bin/flutter ]; then
    echo "در حال دریافت Flutter (حدود ۳۰ ثانیه)…"
    rm -rf /var/tmp/sdk/flutter
    git clone --depth 1 -b stable https://github.com/flutter/flutter.git \
      /var/tmp/sdk/flutter >/dev/null 2>&1
    git config --global --add safe.directory /var/tmp/sdk/flutter
  fi
  flutter --version 2>&1 | head -1
}

ensure_kotlinc() {
  if [ ! -x /var/tmp/kotlinc/bin/kotlinc ]; then
    echo "در حال دریافت Kotlin compiler…"
    curl -sL -o /var/tmp/kotlin.zip \
      "https://github.com/JetBrains/kotlin/releases/download/v2.0.21/kotlin-compiler-2.0.21.zip"
    (cd /var/tmp && unzip -q -o kotlin.zip && rm -f kotlin.zip)
  fi
}

# کامپایلِ واقعیِ لایه‌ی اندروید با android.jar و استابِ libbox.
# این همان کاری است که check_kotlin_raw می‌خواست تقریب بزند — اما حالا
# android.jar و استاب داریم، پس خطای واقعی می‌گیریم نه خط‌مبنا.
#   source tool/env.sh && check_kotlin
check_kotlin() {
  ./tool/check_android.sh
}

# بررسیِ خام (بدون android.jar) — فقط برای مقایسه با خط‌مبنای قدیمی (۱۶ خطا).
# چون کتابخانه‌ها حل‌نشده‌اند، بیشتر خطاها نویز است و ارزشِ کمی دارد.
check_kotlin_raw() {
  ensure_kotlinc
  local dir="android/app/src/main/kotlin/com/overx/overx"
  local log=/var/tmp/kotlinc.log
  mkdir -p /var/tmp/kout
  (cd "$dir" && kotlinc -nowarn -d /var/tmp/kout *.kt >"$log" 2>&1)
  echo "--- خطاهای غیرکتابخانه‌ای (باید خالی باشد) ---"
  grep 'error:' "$log" | grep -vE "unresolved reference|cannot infer type|not enough information|overrides nothing" || true
  echo "--- جمع کل خطاها: $(grep -c 'error:' "$log") ---"
}

# تست + تحلیل ایستا
check() {
  ensure_flutter
  echo "=== ANALYZE ==="
  flutter analyze --no-fatal-infos --no-fatal-warnings 2>&1 |
    grep -E "^\s*(error|warning)" || echo "تمیز (۰ خطا، ۰ هشدار)"
  echo "=== TEST ==="
  flutter test 2>&1 | grep -vE "^#[0-9]+" | tail -3
}

alias f=flutter

if [ -x /var/tmp/sdk/flutter/bin/flutter ]; then
  export PATH="/var/tmp/sdk/flutter/bin:$PATH"
fi
