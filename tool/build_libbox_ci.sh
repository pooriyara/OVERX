#!/usr/bin/env bash
# =============================================================================
# ساختِ libbox.aar در یک محیط تمیز (CI / سندباکس)
#
# این اسکریپت فقط پیش‌نیازها را نصب می‌کند و بعد scripts/build_libbox.sh را
# (که خودِ مخزن sing-box را می‌گیرد و `make lib_android` را اجرا می‌کند) صدا
# می‌زند:
#
#   * Go  — اگر نسخه‌ی سیستم قدیمی باشد، از go.dev می‌گیرد
#   * Android NDK r28 — از طریق sdkmanager
#   * gomobile — `go install` + `gomobile init`
#
# هشدار: چند گیگابایت دانلود و زمانِ زیادی می‌گیرد (ساخت برای ۴ معماری).
# خروجی در android/libs/libbox.aar است.
#
# استفاده:
#   ./tool/build_libbox_ci.sh
# =============================================================================
set -euo pipefail

ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-/var/tmp/android-sdk}"
NDK_VERSION="${NDK_VERSION:-28.0.13004108}"
GO_DIR="${GO_DIR:-/var/tmp/go}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

# ----------------------------------------------------------------------- Go
need_go() {
  command -v go >/dev/null 2>&1 || return 0
  local v
  v="$(go env GOVERSION 2>/dev/null | sed 's/^go//')"
  local major minor
  major="${v%%.*}"; minor="$(echo "$v" | cut -d. -f2)"
  [ "$major" -ge 1 ] && [ "$minor" -ge 25 ] && return 1
  return 0
}

if need_go; then
  log "دریافت Go…"
  mkdir -p /var/tmp/godl
  GO_VER="$(curl -s 'https://go.dev/VERSION?m=text' | head -1)"
  echo "    آخرین نسخه: $GO_VER"
  curl -sSL -o /var/tmp/godl/go.tgz "https://go.dev/dl/${GO_VER}.linux-amd64.tar.gz"
  rm -rf "$GO_DIR" && mkdir -p "$GO_DIR"
  tar -C "$GO_DIR" -xzf /var/tmp/godl/go.tgz --strip-components=1
  rm -f /var/tmp/godl/go.tgz
fi
if [ -x "$GO_DIR/bin/go" ]; then
  export PATH="$GO_DIR/bin:$PATH"
fi
export GOPATH="${GOPATH:-/var/tmp/gopath}"
export PATH="$GOPATH/bin:$PATH"
go version

# ---------------------------------------------------------------------- جاوا
# اسکریپتِ ساختِ sing-box دقیقاً جاوای ۱۷ می‌خواهد (خروجیِ `java -version` را
# نگاه می‌کند و اگر "openjdk 17" نباشد با «java version should be openjdk 17»
# بیرون می‌زند). جاوایِ ۲۱ برای gomobile خوب است اما برای این ساخت نه، پس اگر
# ۱۷ نصب نبود از Adoptium (Temurin) می‌گیریم.
java_is_17() {
  [ -n "${1:-}" ] && [ -x "$1/bin/java" ] || return 1
  "$1/bin/java" -version 2>&1 | head -1 | grep -q 'openjdk version "17'
}

if java_is_17 "${JAVA_HOME:-}"; then
  :
else
  for cand in /var/tmp/jdk17 /usr/lib/jvm/java-17-openjdk-amd64 \
              /usr/lib/jvm/java-1.17.0-openjdk-amd64; do
    if java_is_17 "$cand"; then JAVA_HOME="$cand"; break; fi
  done
fi

if ! java_is_17 "${JAVA_HOME:-}"; then
  log "دریافت JDK 17 (Temurin)…"
  mkdir -p /var/tmp/jdk17
  curl -sSL -o /var/tmp/jdk17.tgz \
    "https://api.adoptium.net/v3/binary/latest/17/ga/linux/x64/jdk/hotspot/normal/eclipse"
  tar -xzf /var/tmp/jdk17.tgz -C /var/tmp/jdk17 --strip-components=1
  rm -f /var/tmp/jdk17.tgz
  JAVA_HOME=/var/tmp/jdk17
fi

export JAVA_HOME
export PATH="$JAVA_HOME/bin:$PATH"
log "جاوا:"
java -version 2>&1 | head -1

# --------------------------------------------------------------------- SDK/NDK
mkdir -p "$ANDROID_SDK_ROOT"
export ANDROID_HOME="$ANDROID_SDK_ROOT"
if [ ! -x "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ]; then
  log "دریافت Android command-line tools…"
  curl -sSL -o /tmp/cmdtools.zip \
    "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
  rm -rf /tmp/cmdtools && mkdir -p /tmp/cmdtools
  unzip -q /tmp/cmdtools.zip -d /tmp/cmdtools
  mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"
  mv /tmp/cmdtools/cmdline-tools "$ANDROID_SDK_ROOT/cmdline-tools/latest"
  rm -f /tmp/cmdtools.zip
fi
if [ -d "${ANDROID_NDK_HOME:-}" ]; then
  log "NDK از محیط گرفته شد: $ANDROID_NDK_HOME"
elif [ ! -d "$ANDROID_SDK_ROOT/ndk/$NDK_VERSION" ]; then
  log "دریافت Android NDK $NDK_VERSION (چند دقیقه)…"
  yes | "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" --licenses \
    >/dev/null 2>&1 || true
  "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" \
    --install "ndk;$NDK_VERSION" >/dev/null
fi
# اگر از محیط آمده باشد دست‌نخورده می‌ماند (CI)، وگرنه همانِ نصب‌شده
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$ANDROID_SDK_ROOT/ndk/$NDK_VERSION}"
log "ANDROID_NDK_HOME=$ANDROID_NDK_HOME"

# ------------------------------------------------------------------ gomobile
# نکته‌ی مهم: sing-box **انشعابِ خودش** از gomobile را می‌خواهد، نه نسخه‌ی
# اصلیِ golang.org/x/mobile. تفاوت فقط در یک فلگ است (`-libname`) که نسخه‌ی
# اصلی ندارد و ساخت با «flag provided but not defined: -libname» می‌ترکد.
# شماره‌ی نسخه را از Makefile یِ خودِ sing-box می‌خوانیم (اگر موجود باشد).
GOMOBILE_VERSION="v0.1.13"
SINGBOX_SRC="${SINGBOX_SRC:-$HOME/.cache/overx-build/sing-box}"
if [ -f "$SINGBOX_SRC/Makefile" ]; then
  v="$(grep -oE 'sagernet/gomobile/cmd/gomobile@[^ ]+' "$SINGBOX_SRC/Makefile" |
    head -1 | sed 's/.*@//')"
  [ -n "$v" ] && GOMOBILE_VERSION="$v"
fi
log "نصب gomobile ($GOMOBILE_VERSION، انشعابِ sagernet)…"
go install "github.com/sagernet/gomobile/cmd/gomobile@$GOMOBILE_VERSION"
go install "github.com/sagernet/gomobile/cmd/gobind@$GOMOBILE_VERSION"
gomobile init

# --------------------------------------------------------------------- ساخت
log "scripts/build_libbox.sh"
cd "$PROJECT_DIR"
./scripts/build_libbox.sh

log "خروجی:"
ls -lh android/libs/libbox.aar
unzip -Z1 android/libs/libbox.aar | grep -E '^jni/' || true
