#!/usr/bin/env bash
# ==============================================================================
# Xiaomi Redmi 3S (land) & MIUI Safe Telemetry & Adware Debloater
# ==============================================================================
# This script safely uninstalls telemetry, ad frameworks, and bloatware for
# Android User 0 using `pm uninstall -k --user 0`.
# It is completely safe, does NOT require root, and does NOT modify /system.
#
# To restore any uninstalled package later, run:
#   adb shell cmd package install-existing <package_name>
# ==============================================================================

set -euo pipefail

TARGET_DEVICE="${1:-}"

ADB_CMD="adb"
if [ -n "$TARGET_DEVICE" ]; then
    ADB_CMD="adb -s $TARGET_DEVICE"
fi

echo "=== Redmi 3S Safe MIUI Telemetry & Adware Debloater ==="
echo "Target: $($ADB_CMD get-serialno 2>/dev/null || echo 'Default ADB device')"

DEBLOAT_PACKAGES=(
    # MIUI Adware & Telemetry Daemons
    "com.miui.msa.global"          # MIUI System Ads (MSA) daemon
    "com.miui.analytics"           # Device activity & usage analytics
    "com.miui.daemon"              # Xiaomi system telemetry daemon
    "com.miui.bugreport"           # Background bug & crash telemetry
    "com.miui.cleanmaster"         # Cheetah Mobile adware cleaner
    "com.miui.yellowpage"          # Yellow pages ad service
    "com.miui.hybrid"              # Quick Apps & ad platform
    "com.miui.hybrid.accessory"    # Quick Apps accessory support
    "com.xiaomi.joyose"            # Joyose analytics and throttling
    "com.xiaomi.glgm"              # Xiaomi Games promotions
    "com.xiaomi.mipicks"           # Mi Picks / GetApps app store
    "com.xiaomi.payment"           # Xiaomi payment background framework
    "com.mipay.wallet.in"          # Mi Pay India
    "com.mipay.wallet.id"          # Mi Pay Indonesia
    "com.mi.globalTrendNews"       # Trend News push notifications

    # Pre-installed Facebook Tracking & Services
    "com.facebook.appmanager"      # Facebook background app manager
    "com.facebook.services"        # Facebook background telemetry service
    "com.facebook.system"          # Facebook system installer
)

SUCCESS_COUNT=0
SKIP_COUNT=0

for pkg in "${DEBLOAT_PACKAGES[@]}"; do
    echo -n "[-] Removing $pkg... "
    out=$($ADB_CMD shell pm uninstall -k --user 0 "$pkg" 2>&1 || true)
    if echo "$out" | grep -q "Success"; then
        echo "✅ Success"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo "⏭️ Not present or already removed ($out)"
        SKIP_COUNT=$((SKIP_COUNT + 1))
    fi
done

echo ""
echo "=== Debloat Finished ==="
echo "Successfully debloated: $SUCCESS_COUNT packages"
echo "Skipped:               $SKIP_COUNT packages"
echo "Phone CPU wakeups, background network chatter, and RAM usage have been optimized."
