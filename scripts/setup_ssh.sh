#!/usr/bin/env bash
# ==============================================================================
# SSH Provisioner & Key Injector for Termux
# ==============================================================================
# Generates a local SSH key pair if none exists, injects the public key into
# Termux's authorized_keys, and verifies passwordless SSH access on port 8022.
# ==============================================================================

set -euo pipefail

TARGET_DEVICE="${1:-}"
KEY_PATH="$HOME/.ssh/id_ed25519"

ADB_CMD="adb"
if [ -n "$TARGET_DEVICE" ]; then
    ADB_CMD="adb -s $TARGET_DEVICE"
fi

echo "=== SSH Setup for Redmi 3S Termux ==="

# 1. Generate SSH key pair if not exists
if [ ! -f "$KEY_PATH" ]; then
    echo "[-] Generating SSH key pair at $KEY_PATH..."
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -C "redmi3s-engineering-lab"
fi

PUBKEY=$(cat "$KEY_PATH.pub")

# 2. Inject public key into Termux
echo "[-] Injecting public key into Termux authorized_keys..."
$ADB_CMD shell "run-as com.termux sh -c '
mkdir -p /data/data/com.termux/files/home/.ssh
chmod 700 /data/data/com.termux/files/home/.ssh
echo \"$PUBKEY\" > /data/data/com.termux/files/home/.ssh/authorized_keys
chmod 600 /data/data/com.termux/files/home/.ssh/authorized_keys

export LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib
export PATH=/data/data/com.termux/files/usr/bin:\$PATH
ssh-keygen -A 2>/dev/null || true
pkill -f \"sshd -p 8022\" 2>/dev/null || true
sshd -p 8022
'"

# 3. Get Phone Wi-Fi IP
PHONE_IP=$($ADB_CMD shell ip -4 addr show wlan0 2>/dev/null | grep -oE "inet [0-9.]+" | cut -d' ' -f2 || echo "")

if [ -n "$PHONE_IP" ]; then
    echo "[-] Phone IP detected: $PHONE_IP"
    echo "[-] Testing SSH connection..."
    if ssh -i "$KEY_PATH" -p 8022 -o StrictHostKeyChecking=no -o ConnectTimeout=4 "$PHONE_IP" "echo 'SSH Connection Verified!'" 2>/dev/null; then
        echo "✅ SSH connection successful!"
        echo "Access your phone anytime via: ssh -p 8022 $PHONE_IP"
    else
        echo "⚠️ Note: SSH daemon is running. Ensure phone and PC are on the same Wi-Fi network."
    fi
else
    echo "⚠️ Could not auto-detect Wi-Fi IP. Ensure Wi-Fi is enabled on the phone."
fi
