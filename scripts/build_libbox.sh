#!/usr/bin/env bash
# =============================================================================
# ساخت کتابخانه‌ی libbox برای اندروید
#
# چرا لازم است؟
# باینری CLI هسته‌ی sing-box نمی‌تواند اینترفیس TUN را روی اندروید بسازد
# (کانفیگ JSON آن هیچ فیلدی برای fd ندارد). تنها راهِ درست این است که هسته را
# به صورت کتابخانه‌ی بومی درون برنامه اجرا کنیم — همان کاری که
# sing-box for Android می‌کند.
#
# پیش‌نیازها:
#   - Go 1.24 یا جدیدتر          https://go.dev/dl
#   - Android NDK r28 یا جدیدتر  (از طریق Android Studio → SDK Manager)
#     و متغیر محیطی ANDROID_NDK_HOME
#   - JDK 17
#
# اجرا:
#   ./scripts/build_libbox.sh              # خروجی در android/libs/libbox.aar
#   SINGBOX_REF=v1.14.2 ./scripts/build_libbox.sh
#
# ماشینِ کم‌رم؟ می‌توان فقط یک معماری ساخت (ساختِ چهار معماری با هم بیش از
# ۴ گیگابایت رم می‌خواهد؛ روی ماشین ۲ گیگابایتی دستگاه قفل می‌کند):
#
#   LIBBOX_PLATFORM=android/arm64 ./scripts/build_libbox.sh
#   LIBBOX_PLATFORM=android/arm,android/arm64 ./scripts/build_libbox.sh
# =============================================================================
set -euo pipefail

SINGBOX_REPO="${SINGBOX_REPO:-https://github.com/SagerNet/sing-box}"
SINGBOX_REF="${SINGBOX_REF:-v1.14.2}"
BUILD_DIR="${BUILD_DIR:-$HOME/.cache/overx-build}"
OUT_DIR="$(cd "$(dirname "$0")/.." && pwd)/android/libs"

echo "==> sing-box $SINGBOX_REF"

# ------------------------------------------------------------------ پیش‌نیازها
command -v go >/dev/null || { echo "Go نصب نیست: https://go.dev/dl"; exit 1; }
GO_VER="$(go env GOVERSION | sed 's/^go//')"
echo "    Go $GO_VER"

if [ -z "${ANDROID_NDK_HOME:-}" ]; then
  if [ -n "${ANDROID_HOME:-}" ] && [ -d "$ANDROID_HOME/ndk" ]; then
    ANDROID_NDK_HOME="$(find "$ANDROID_HOME/ndk" -maxdepth 1 -mindepth 1 -type d | sort | tail -1)"
    export ANDROID_NDK_HOME
  fi
fi
[ -d "${ANDROID_NDK_HOME:-}" ] || { echo "ANDROID_NDK_HOME تنظیم نشده است"; exit 1; }
echo "    NDK $ANDROID_NDK_HOME"

GO_MAJOR="$(echo "$GO_VER" | cut -d. -f1)"
GO_MINOR="$(echo "$GO_VER" | cut -d. -f2)"
if [ "$GO_MAJOR" -lt 1 ] || { [ "$GO_MAJOR" -eq 1 ] && [ "$GO_MINOR" -lt 24 ]; }; then
  echo "    ⚠️  Go 1.24+ توصیه می‌شود"
fi

# ------------------------------------------------------------------- دریافت کد
mkdir -p "$BUILD_DIR"
if [ ! -d "$BUILD_DIR/sing-box/.git" ]; then
  rm -rf "$BUILD_DIR/sing-box"
  git clone --filter=blob:none "$SINGBOX_REPO" "$BUILD_DIR/sing-box"
fi
cd "$BUILD_DIR/sing-box"
git fetch --filter=blob:none origin "refs/tags/$SINGBOX_REF:refs/tags/$SINGBOX_REF" 2>/dev/null || true
git checkout -q "$SINGBOX_REF"
echo "    checked out $(git describe --tags 2>/dev/null || echo "$SINGBOX_REF")"

# --------------------------------------------------------------------- ساخت
# خود مخزن sing-box این target را برای همین کار فراهم کرده است:
#   make lib_android  →  go run ./cmd/internal/build_libbox -target android
# پیکربندی‌اش در experimental/libbox/ffi.json است (بسته‌ی جاوا:
# io.nekohasekai.libbox).
# نکته: -platform مستقیماً به gomobile می‌رسد و می‌تواند یک یا چند معماری
# باشد (android/arm64 یا android/arm,android/arm64). اگر خالی باشد، همان
# `make lib_android` اجرا می‌شود که هر چهار معماری را می‌سازد.
if [ -n "${LIBBOX_PLATFORM:-}" ]; then
  echo "==> build_libbox -platform $LIBBOX_PLATFORM (فقط معماری‌های خواسته‌شده)"
  go run ./cmd/internal/build_libbox -target android \
    -platform "$LIBBOX_PLATFORM"
else
  echo "==> make lib_android"
  make lib_android
fi

# ------------------------------------------------------------------- خروجی
# build_libbox خروجی را در کنار repo می‌گذارد (مانند مسیر DEPLOY_ANDROID در
# ffi.json: sing-box-for-android/app/libs). هر AAR‌ای که پیدا شد کپی می‌کنیم.
mkdir -p "$OUT_DIR"
AAR=""
for candidate in \
  "$BUILD_DIR/sing-box/bin/libbox.aar" \
  "$BUILD_DIR/sing-box/libbox.aar" \
  "$BUILD_DIR/sing-box-for-android/app/libs/libbox.aar" \
  "$(find "$BUILD_DIR" -maxdepth 3 -name 'libbox*.aar' -print -quit 2>/dev/null)"; do
  [ -n "$candidate" ] && [ -f "$candidate" ] && AAR="$candidate" && break
done

if [ -z "$AAR" ]; then
  echo "    ⚠️  AAR پیدا نشد. خروجی‌های build را بگردید:"
  find "$BUILD_DIR/sing-box" -maxdepth 2 -type d \( -name bin -o -name dist \) -exec ls -la {} \; 2>/dev/null || true
  exit 1
fi

cp -f "$AAR" "$OUT_DIR/libbox.aar"
echo "==> ✓ $OUT_DIR/libbox.aar ($(du -h "$OUT_DIR/libbox.aar" | cut -f1))"

# ---------------------------------------------------------- ABIهای پشتیبانی‌شده
echo "    ABIها:"
unzip -Z1 "$OUT_DIR/libbox.aar" 2>/dev/null | grep -E '^jni/' || echo "      (جستجو در AAR ناموفق)"

cat <<'TIP'

==> مرحله‌ی بعد

    flutter build apk --release

نکته: اگر فقط ABI خاصی می‌خواهید (مثلاً برای کاهش حجم):

    flutter build apk --split-per-abi --target-platform android-arm64

نکته: باینری‌های Xray هم‌چنان باید در
android/app/src/main/jniLibs/<abi>/libxray.so قرار گیرند
(مسیر CLI برای Xray بدون تغییر است).
TIP
