#!/usr/bin/env bash
# =============================================================================
# ساخت APK اندروید در یک محیط تمیز (CI/سندباکس)
#
# این اسکریپت همه‌ی پیش‌نیازها را خودش نصب می‌کند:
#   * JDK 17
#   * Android SDK command-line tools + platform + build-tools
#   * پذیرش خودکارِ لایسنس‌ها
# و بعد `flutter build apk` را اجرا می‌کند.
#
# نکته: libbox.aar اختیاری است. اگر در android/libs نباشد، Gradle فقط هشدار
# می‌دهد و APK ساخته می‌شود — اما در آن صورت sing-box روی اندروید فقط از مسیر
# CLI استفاده می‌کند و TUN در دسترس نیست. برای TUN باید libbox.aar را با
# scripts/build_libbox.sh بسازید.
#
# استفاده:
#   ./tool/build_android_ci.sh            # APK دیباگ
#   ./tool/build_android_ci.sh release    # APK ریلیز
# =============================================================================
set -euo pipefail

MODE="${1:-debug}"
ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-/var/tmp/android-sdk}"
CMDLINE_VERSION="11076708"
PLATFORM="android-35"
BUILD_TOOLS="35.0.0"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

# --------------------------------------------------------------------- JDK 17
# Gradle 9 / AGP 9 با JDK 17 و 21 هر دو کار می‌کنند؛ در این تصویر فقط ۲۱ و ۲۵
# موجود است، پس ۲۱ را می‌گیریم.
if ! java -version 2>&1 | grep -qE 'version "(17|21|25)'; then
  log "نصب JDK 21…"
  sudo -n apt-get update -qq
  sudo -n apt-get install -y -qq openjdk-21-jdk-headless >/dev/null
fi
export JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
log "JAVA_HOME=$JAVA_HOME"
java -version 2>&1 | head -1

# ----------------------------------------------------------------- Android SDK
mkdir -p "$ANDROID_SDK_ROOT"
export ANDROID_HOME="$ANDROID_SDK_ROOT"
export ANDROID_SDK_ROOT

if [ ! -x "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ]; then
  log "دریافت Android command-line tools…"
  rm -rf "$ANDROID_SDK_ROOT/cmdline-tools"
  curl -sSL -o /tmp/cmdtools.zip \
    "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_VERSION}_latest.zip"
  rm -rf /tmp/cmdtools && mkdir -p /tmp/cmdtools
  unzip -q /tmp/cmdtools.zip -d /tmp/cmdtools
  mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"
  mv /tmp/cmdtools/cmdline-tools "$ANDROID_SDK_ROOT/cmdline-tools/latest"
  rm -f /tmp/cmdtools.zip
fi

SDKMANAGER="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
log "نصب platform و build-tools (ممکن است چند دقیقه طول بکشد)…"
yes | "$SDKMANAGER" --licenses >/dev/null 2>&1 || true
"$SDKMANAGER" --install "platforms;${PLATFORM}" "build-tools;${BUILD_TOOLS}" \
  "platform-tools" >/dev/null
"$SDKMANAGER" --list_installed | sed 's/^/    /'

# -------------------------------------------------------------------- Flutter
export PATH="/var/tmp/sdk/flutter/bin:$PATH"
export PUB_CACHE="/var/tmp/sdk/.pub-cache"
if [ ! -x /var/tmp/sdk/flutter/bin/flutter ]; then
  log "دریافت Flutter…"
  rm -rf /var/tmp/sdk/flutter
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git \
    /var/tmp/sdk/flutter >/dev/null 2>&1
  git config --global --add safe.directory /var/tmp/sdk/flutter
fi
flutter --version 2>&1 | head -1

cd "$PROJECT_DIR"
flutter config --android-sdk "$ANDROID_SDK_ROOT" >/dev/null
flutter config --android-jdk "$JAVA_HOME" >/dev/null || true

# local.properties برای Gradle (در .gitignore است و منتشر نمی‌شود)
{
  echo "sdk.dir=$ANDROID_SDK_ROOT"
  echo "flutter.sdk=/var/tmp/sdk/flutter"
} > android/local.properties

# محدودیت حافظه: ماشین‌های کوچک (مثل رانرِ رایگانِ CI یا سندباکس) فقط ۲ گیگابایت
# رم دارند و پیش‌فرضِ Gradle برای هیپ ۸ گیگابایت است — یعنی دیمن کشته می‌شود.
# این مقادیر فقط در همین اجرا اِعمال می‌شوند و در فایل پروژه ذخیره نمی‌شوند.
export GRADLE_OPTS="-Dorg.gradle.jvmargs=-Xmx700m -XX:MaxMetaspaceSize=320m \
 -XX:ReservedCodeCacheSize=96m -Dkotlin.compiler.execution.strategy=in-process \
 -Dorg.gradle.workers.max=1 -Dorg.gradle.parallel=false \
 -Dorg.gradle.internal.instrumentation.agent=false -Dfile.encoding=UTF-8"

log " flutter build apk --$MODE"
flutter build apk --"$MODE" 2>&1 | tail -30

log "خروجی:"
find build/app/outputs -name '*.apk' -exec ls -lh {} \;
