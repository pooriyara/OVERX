#!/usr/bin/env bash
# =============================================================================
# کامپایلِ واقعیِ لایه‌ی اندروید — بدون libbox.aar و بدون اندروید استودیو
#
# چرا؟ چون `libbox.aar` نداریم و لایه‌ی اندروید تا امروز هرگز کامپایل نشده
# بود؛ خطاهایی از جنسِ «امضا جور نیست» یا «چنین متدی وجود ندارد» فقط با
# کامپایل بیرون می‌آیند، نه با خواندنِ کد. این اسکریپت:
#
#   1. JDK و android.jar (platform 35) را فراهم می‌کند
#   2. استاب‌های libbox را از روی سورسِ Go می‌سازد  (tool/libbox_stub)
#   3. کلاس‌های تولیدشده‌ی ساخت را استاب می‌کند        (tool/android_stub)
#   4. کاتلینِ android/app/src/main/kotlin را با kotlinc کامپایل می‌کند
#
# محدودیتِ مهم: این دروازه فقط **کامپایل** را چک می‌کند، نه رفتار را. اینکه
# کد روی دستگاه درست کار می‌کند، همچنان باید با اجرا تأیید شود.
#
# استفاده:
#   ./tool/check_android.sh
# =============================================================================
set -uo pipefail

ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-/var/tmp/android-sdk}"
DEPS="${DEPS:-/var/tmp/deps}"
PLATFORM="${PLATFORM:-android-35}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE_HASH="${ENGINE_HASH:-b8c8d3d8d5d0095127057f8a29ca8cc53da2167c}"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

# --------------------------------------------------------------------- JDK
if ! java -version 2>&1 | grep -qE 'version "(17|21|25)'; then
  log "نصب JDK 21…"
  sudo -n apt-get update -qq
  sudo -n apt-get install -y -qq openjdk-21-jdk-headless >/dev/null 2>&1
fi
export JAVA_HOME="${JAVA_HOME:-$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")}"

# ------------------------------------------------------------ اندروید SDK
mkdir -p "$ANDROID_SDK_ROOT"
if [ ! -f "$ANDROID_SDK_ROOT/platforms/$PLATFORM/android.jar" ]; then
  log "دریافت Android command-line tools و platform $PLATFORM…"
  if [ ! -x "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ]; then
    curl -sSL -o /tmp/cmdtools.zip \
      "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
    rm -rf /tmp/cmdtools && mkdir -p /tmp/cmdtools
    unzip -q /tmp/cmdtools.zip -d /tmp/cmdtools
    mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"
    rm -rf "$ANDROID_SDK_ROOT/cmdline-tools/latest"
    mv /tmp/cmdtools/cmdline-tools "$ANDROID_SDK_ROOT/cmdline-tools/latest"
    rm -f /tmp/cmdtools.zip
  fi
  yes | "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" --licenses \
    >/dev/null 2>&1 || true
  "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" \
    --install "platforms;$PLATFORM" >/dev/null
fi
ANDROID_JAR="$ANDROID_SDK_ROOT/platforms/$PLATFORM/android.jar"
[ -f "$ANDROID_JAR" ] || { echo "خطا: android.jar پیدا نشد"; exit 1; }

# ---------------------------------------------------------- وابستگی‌ها
mkdir -p "$DEPS"
fetch() { # url -> file
  [ -s "$2" ] || curl -sSL -o "$2" "$1"
}
fetch "https://dl.google.com/dl/android/maven2/androidx/core/core/1.13.1/core-1.13.1.aar" \
  "$DEPS/core.aar"
fetch "https://repo1.maven.org/maven2/org/jetbrains/kotlinx/kotlinx-coroutines-core-jvm/1.8.1/kotlinx-coroutines-core-jvm-1.8.1.jar" \
  "$DEPS/coroutines.jar"
# نکته: در ۲.۸.x خودِ کلاسِ LifecycleOwner در `-jvm` است نه در lifecycle-common
fetch "https://dl.google.com/dl/android/maven2/androidx/lifecycle/lifecycle-common-jvm/2.8.7/lifecycle-common-jvm-2.8.7.jar" \
  "$DEPS/lifecycle-common-jvm.jar"
fetch "https://storage.googleapis.com/download.flutter.io/io/flutter/flutter_embedding_release/1.0.0-$ENGINE_HASH/flutter_embedding_release-1.0.0-$ENGINE_HASH.jar" \
  "$DEPS/flutter_embedding.jar"

# کلاس‌های داخلِ AAR را بیرون می‌کشیم
if [ ! -s "$DEPS/core_classes.jar" ] && [ -s "$DEPS/core.aar" ]; then
  (cd "$DEPS" && unzip -o -q core.aar classes.jar -d core_x &&
    mv core_x/classes.jar core_classes.jar && rm -rf core_x)
fi

# ------------------------------------------------------------- کاتلین
export PATH="/var/tmp/kotlinc/bin:$PATH"
if [ ! -x /var/tmp/kotlinc/bin/kotlinc ]; then
  log "دریافت Kotlin compiler…"
  curl -sL -o /var/tmp/kotlin.zip \
    "https://github.com/JetBrains/kotlin/releases/download/v2.0.21/kotlin-compiler-2.0.21.zip"
  (cd /var/tmp && unzip -q -o kotlin.zip && rm -f kotlin.zip)
fi

# ------------------------------------------------------- استاب‌ها (javac)
STUB_OUT=/var/tmp/android_stub_classes
rm -rf "$STUB_OUT" && mkdir -p "$STUB_OUT"

# استابِ R را از روی res/ می‌سازیم که با منابع هم‌گام بماند (مثلِ AAPT)
if command -v python3 >/dev/null 2>&1; then
  log "ساختِ استابِ R از روی res/…"
  python3 "$PROJECT_DIR"/tool/gen_r_stub.py || {
    echo "خطا در ساختِ استابِ R"; exit 1; }
fi

# اگر libbox.aar واقعی ساخته شده باشد (scripts/build_libbox.sh)، در برابر
# APIِ واقعی کامپایل می‌کنیم؛ وگرنه استاب‌های دست‌نویس را به کار می‌بریم.
# این یعنی دروازه همیشه چیزی را چک می‌کند، و وقتی AAR هست چکِ سخت‌گیرانه‌تری.
LIBBOX_AAR="$PROJECT_DIR/android/libs/libbox.aar"
LIBBOX_REAL=""
if [ -s "$LIBBOX_AAR" ]; then
  log "libbox.aar واقعی پیدا شد — کامپایل در برابر APIِ واقعیِ gobind…"
  REAL_OUT=/var/tmp/libbox_real_classes
  rm -rf "$REAL_OUT" && mkdir -p "$REAL_OUT"
  if (cd "$REAL_OUT" && unzip -o -q "$LIBBOX_AAR" classes.jar &&
      mv classes.jar libbox_classes.jar); then
    LIBBOX_REAL="$REAL_OUT/libbox_classes.jar"
  else
    echo "  ⚠️  classes.jar از AAR در نیامد — می‌رویم سراغ استاب‌ها"
  fi
fi

if [ -n "$LIBBOX_REAL" ]; then
  log "کامپایلِ استاب‌های اندروید (R و NonNull)…"
  # -encoding UTF-8 ضروری است: کامنت‌های این فایل‌ها فارسی‌اند و javac بدون آن
  # از charset پیش‌فرضِ ماشین استفاده می‌کند (روی بعضی رانرها US-ASCII) و با
  # «unmappable character» می‌ترکد.
  javac -nowarn -encoding UTF-8 -d "$STUB_OUT" \
    "$PROJECT_DIR"/tool/android_stub/com/overx/overx/R.java \
    "$PROJECT_DIR"/tool/android_stub/androidx/annotation/NonNull.java || {
      echo "خطا در کامپایلِ استاب‌ها"; exit 1; }
else
  log "کامپایلِ استاب‌های libbox و اندروید…"
  javac -nowarn -encoding UTF-8 -d "$STUB_OUT" \
    "$PROJECT_DIR"/tool/libbox_stub/io/nekohasekai/libbox/*.java \
    "$PROJECT_DIR"/tool/android_stub/com/overx/overx/R.java \
    "$PROJECT_DIR"/tool/android_stub/androidx/annotation/NonNull.java || {
      echo "خطا در کامپایلِ استاب‌ها"; exit 1; }
fi

# -------------------------------------------------------- کامپایلِ اصلی
CP="$ANDROID_JAR:$STUB_OUT:${LIBBOX_REAL:-}:$DEPS/core_classes.jar:$DEPS/coroutines.jar:$DEPS/lifecycle-common-jvm.jar:$DEPS/flutter_embedding.jar"
OUT=/var/tmp/kout_android
rm -rf "$OUT" && mkdir -p "$OUT"

log "کامپایلِ کاتلینِ اندروید…"
kotlinc -nowarn -jvm-target 17 -cp "$CP" \
  "$PROJECT_DIR"/android/app/src/main/kotlin/com/overx/overx/*.kt \
  -d "$OUT" > /var/tmp/kandroid.log 2>&1

errors=$(grep -c 'error:' /var/tmp/kandroid.log)
echo
if [ "$errors" != "0" ]; then
  grep 'error:' /var/tmp/kandroid.log | sed "s|$PROJECT_DIR/||"
fi
echo "═══════════════════════════════"
echo "  تعداد خطاها: $errors"
echo "═══════════════════════════════"
[ "$errors" = "0" ] || exit 1
