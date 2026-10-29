#!/usr/bin/env bash
set -e

PHONE_IP="192.168.0.9"
SSH_PORT="8022"
SSH_KEY="$HOME/.ssh/id_ed25519"
TARGET_DIR="/data/data/com.termux/files/home/monitor"

echo "=== Deploying Sentinel Lab to Redmi 3S ($PHONE_IP) ==="

# 1. Create directory on phone
ssh -i "$SSH_KEY" -p "$SSH_PORT" -o StrictHostKeyChecking=no "$PHONE_IP" "mkdir -p $TARGET_DIR"

# 2. Copy files to phone
scp -i "$SSH_KEY" -P "$SSH_PORT" -o StrictHostKeyChecking=no server.py index.html "$PHONE_IP:$TARGET_DIR/"

# 3. Kill any existing monitor instance and start fresh in background
ssh -i "$SSH_KEY" -p "$SSH_PORT" -o StrictHostKeyChecking=no "$PHONE_IP" "
export LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib
export PATH=/data/data/com.termux/files/usr/bin:\$PATH

pkill -f 'python3.*server.py' 2>/dev/null || true
cd $TARGET_DIR
nohup python3 server.py > server.log 2>&1 &
sleep 1
ps | grep server.py || echo 'Warning: server process not detected in ps'
"

echo "=== Deployment Complete! ==="
echo "Live Web Dashboard URL: http://$PHONE_IP:8080"
