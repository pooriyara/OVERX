#!/usr/bin/env bash
# =============================================================================
# اعتبارسنجیِ کانفیگ‌های تولیدشده با **باینری اصلیِ** sing-box و Xray.
#
# چرا؟ چون تست‌های واحد فقط انتظارهای خودمان را چک می‌کنند. اینکه آیا هسته‌ی
# واقعی این JSON را قبول می‌کند، فقط با اجرای خودش معلوم می‌شود. این اسکریپت
# همان کاری را می‌کند که هیچ تستی نمی‌توانست: خروجیِ واقعیِ برنامه را به
# هسته‌ی واقعی می‌دهد.
#
# اجرا:
#   flutter test tool/emit_configs_test.dart     # ساختِ کانفیگ‌ها
#   ./tool/validate_configs.sh                   # اعتبارسنجی با هسته‌ی واقعی
#
# باینری‌ها در /var/tmp/bin کش می‌شوند (چند ده مگابایت).
# =============================================================================
set -uo pipefail

SINGBOX_VERSION="${SINGBOX_VERSION:-1.14.2}"
BIN_DIR="${BIN_DIR:-/var/tmp/bin}"
CFG_DIR="${CFG_DIR:-/tmp/overx-configs}"

mkdir -p "$BIN_DIR"

die() { echo "خطا: $*" >&2; exit 1; }

# ------------------------------------------------------------------ گرفتن
fetch_singbox() {
  local dir="$BIN_DIR/sing-box-${SINGBOX_VERSION}-linux-amd64"
  [[ -x "$dir/sing-box" ]] && { echo "$dir/sing-box"; return; }
  echo "دریافت sing-box ${SINGBOX_VERSION}…" >&2
  curl -fsSL -o "$BIN_DIR/sb.tgz" \
    "https://github.com/SagerNet/sing-box/releases/download/v${SINGBOX_VERSION}/sing-box-${SINGBOX_VERSION}-linux-amd64.tar.gz" \
    || die "دریافت sing-box ناموفق بود"
  (cd "$BIN_DIR" && tar xzf sb.tgz) || die "باز کردن بسته ناموفق بود"
  rm -f "$BIN_DIR/sb.tgz"
  chmod +x "$dir/sing-box"
  echo "$dir/sing-box"
}

fetch_xray() {
  [[ -x "$BIN_DIR/xray" ]] && { echo "$BIN_DIR/xray"; return; }
  echo "دریافت Xray-core (آخرین نسخه)…" >&2
  curl -fsSL -o "$BIN_DIR/xray.zip" \
    "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip" \
    || die "دریافت Xray ناموفق بود"
  command -v unzip >/dev/null || die "unzip نصب نیست (apt install unzip)"
  (cd "$BIN_DIR" && unzip -oq xray.zip) || die "باز کردن بسته ناموفق بود"
  rm -f "$BIN_DIR/xray.zip"
  chmod +x "$BIN_DIR/xray"
  echo "$BIN_DIR/xray"
}

strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

# ------------------------------------------------------------------ اجرا
[[ -d "$CFG_DIR" ]] || die "$CFG_DIR وجود ندارد؛ اول emit_configs_test.dart را اجرا کن"

SB=$(fetch_singbox)
XR=$(fetch_xray)
echo

pass=0; fail=0

echo "═══ sing-box $($SB version | head -1) — check ═══"
for f in "$CFG_DIR"/*.singbox.json; do
  n=$(basename "$f" .singbox.json)
  if out=$("$SB" check -c "$f" 2>&1); then
    echo "  PASS  $n"; pass=$((pass+1))
  else
    echo "  FAIL  $n"
    echo "$out" | strip_ansi | head -3 | sed 's/^/          /'
    fail=$((fail+1))
  fi
done

echo
echo "═══ Xray $($XR version | head -1) — test ═══"
for f in "$CFG_DIR"/*.xray.json; do
  # نسخه‌ی TUN نیاز به root دارد؛ اینجا رد می‌شود
  case "$f" in *.tun.xray.json) continue;; esac
  n=$(basename "$f" .xray.json)
  out=$("$XR" -test -c "$f" 2>&1)
  if echo "$out" | grep -q "Configuration OK"; then
    echo "  PASS  $n"; pass=$((pass+1))
  else
    echo "  FAIL  $n"
    echo "$out" | grep -iE 'Failed to start|> infra/conf' | head -2 | sed 's/^/          /'
    fail=$((fail+1))
  fi
done

echo
echo "═══════════════════════════════"
echo "  موفق: $pass    ناموفق: $fail"
echo
if [[ -f "$CFG_DIR"/*.tun.xray.json ]]; then
  echo "  یادداشت: نسخه‌های *.tun.xray.json عمداً بررسی نشدند (ساختِ TUN"
  echo "  به root نیاز دارد و این محیط بی‌دسترسی است)."
fi
[[ $fail -eq 0 ]] || exit 1
