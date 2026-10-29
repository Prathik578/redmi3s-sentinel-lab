#!/usr/bin/env bash
# ==============================================================================
# Termux Daemon & Persistence Setup
# ==============================================================================
# Configures auto-start hooks in ~/.bashrc so both OpenSSH and the Sentinel
# Telemetry Dashboard automatically launch whenever Termux is opened.
# Also whitelists Termux from Android's aggressive battery optimizations.
# ==============================================================================

set -euo pipefail

TARGET_DEVICE="${1:-}"

ADB_CMD="adb"
if [ -n "$TARGET_DEVICE" ]; then
    ADB_CMD="adb -s $TARGET_DEVICE"
fi

echo "=== Configuring Termux Persistence & Auto-start ==="

# 1. Whitelist Termux from Android Battery Optimization (Doze mode)
echo "[-] Whitelisting Termux from Doze battery optimization..."
$ADB_CMD shell "dumpsys deviceidle whitelist +com.termux 2>/dev/null || true"

# 2. Configure ~/.bashrc
echo "[-] Injecting auto-start hooks into ~/.bashrc..."
$ADB_CMD shell "run-as com.termux /system/bin/sh -c '
export TMPDIR=/data/data/com.termux/files/usr/tmp
mkdir -p \$TMPDIR
cd \$TMPDIR
cat << \"EOF\" > /data/data/com.termux/files/home/.bashrc
export LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib
export PATH=/data/data/com.termux/files/usr/bin:\$PATH
alias debian=\"/data/data/com.termux/files/usr/bin/debian\"

# Auto-start SSH daemon
if ! ps | grep -v grep | grep sshd > /dev/null 2>&1; then
    /data/data/com.termux/files/usr/bin/sshd -p 8022
    echo \"[*] SSH daemon started on port 8022\"
fi

# Auto-start Device Sentinel Monitor
if ! ps | grep -v grep | grep \"server.py\" > /dev/null 2>&1; then
    cd /data/data/com.termux/files/home/monitor
    python3 server.py --daemon
    cd /data/data/com.termux/files/home
    echo \"[*] Sentinel Monitor started on port 8080\"
fi
EOF
cp /data/data/com.termux/files/home/.bashrc /data/data/com.termux/files/home/.profile
'"

# 3. Launch Termux Activity to initialize
echo "[-] Launching Termux to trigger startup..."
$ADB_CMD shell "am start -n com.termux/.app.TermuxActivity"

echo "✅ Termux persistence and auto-start configured successfully!"
