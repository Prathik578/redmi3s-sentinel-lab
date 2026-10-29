#!/usr/bin/env bash
# ==============================================================================
# Debian 12 (Bookworm) Userspace Provisioner for Termux & Android
# ==============================================================================
# This script installs PRoot in Termux, downloads and extracts the official
# Debian Bookworm ARM64 (aarch64) rootfs, configures DNS, creates a convenient
# `debian` launcher command, and installs essential developer tools.
# ==============================================================================

set -euo pipefail

TARGET_DEVICE="${1:-}"

ADB_CMD="adb"
if [ -n "$TARGET_DEVICE" ]; then
    ADB_CMD="adb -s $TARGET_DEVICE"
fi

echo "=== Debian 12 Bookworm Provisioner ==="
echo "Target: $($ADB_CMD get-serialno 2>/dev/null || echo 'Default ADB device')"

# 1. Update Termux apt repos and install proot
echo "[*] Step 1/5: Updating Termux repositories and installing proot..."
$ADB_CMD shell "run-as com.termux sh -c '
rm -f /data/data/com.termux/files/usr/etc/apt/sources.list.d/*.list 2>/dev/null || true
export LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib
export PATH=/data/data/com.termux/files/usr/bin:\$PATH
apt update && apt install -y proot tar bsdtar python
'"

# 2. Check if Debian rootfs already exists
echo "[*] Step 2/5: Checking for Debian rootfs..."
DEBIAN_DIR="/data/data/com.termux/files/home/debian"
EXISTS=$($ADB_CMD shell "run-as com.termux sh -c 'test -d $DEBIAN_DIR/etc && echo YES || echo NO'")

if [ "$EXISTS" = "YES" ]; then
    echo "[-] Debian rootfs already present at $DEBIAN_DIR. Skipping download."
else
    echo "[-] Downloading Debian Bookworm rootfs..."
    ROOTFS_URL="https://blr1mirror01.do.images.linuxcontainers.org/images/debian/bookworm/arm64/default/20261028_05%3A24/rootfs.tar.xz"
    TMP_TAR="/tmp/debian-rootfs.tar"
    
    if [ ! -f "$TMP_TAR" ]; then
        curl -L --progress-bar -o "$TMP_TAR.xz" "$ROOTFS_URL"
        xz -dc "$TMP_TAR.xz" > "$TMP_TAR"
        rm -f "$TMP_TAR.xz"
    fi

    echo "[-] Pushing rootfs archive to device..."
    $ADB_CMD push "$TMP_TAR" /data/local/tmp/debian-rootfs.tar

    echo "[-] Extracting Debian rootfs on device..."
    $ADB_CMD shell "run-as com.termux sh -c '
    export TMPDIR=/data/data/com.termux/files/usr/tmp
    mkdir -p \$TMPDIR $DEBIAN_DIR
    cd \$TMPDIR
    cat << \"PYEOF\" > extract.py
import tarfile, sys, os
tar_path = \"/data/local/tmp/debian-rootfs.tar\"
dest_path = \"$DEBIAN_DIR\"
os.makedirs(dest_path, exist_ok=True)
count = 0
with tarfile.open(tar_path) as tar:
    for m in tar.getmembers():
        if m.name.startswith((\"./dev/\", \"dev/\")) or m.name in (\".\", \"./\", \"./dev\", \"dev\"):
            continue
        try:
            tar.extract(m, path=dest_path)
            count += 1
            if count % 3000 == 0:
                print(\"Extracted %d files...\" % count)
                sys.stdout.flush()
        except Exception:
            pass
print(\"Extracted %d files total.\" % count)
PYEOF
    export LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib
    export PATH=/data/data/com.termux/files/usr/bin:\$PATH
    python3 extract.py
    rm -f extract.py
    '"
    $ADB_CMD shell "rm -f /data/local/tmp/debian-rootfs.tar"
fi

# 3. Configure DNS & Hostname in Debian rootfs
echo "[*] Step 3/5: Configuring DNS and hostname..."
$ADB_CMD shell "run-as com.termux sh -c '
rm -f $DEBIAN_DIR/etc/resolv.conf
echo \"nameserver 1.1.1.1\" > $DEBIAN_DIR/etc/resolv.conf
echo \"nameserver 8.8.8.8\" >> $DEBIAN_DIR/etc/resolv.conf
chmod 644 $DEBIAN_DIR/etc/resolv.conf
echo \"127.0.0.1 localhost redmi3s-debian\" > $DEBIAN_DIR/etc/hosts
'"

# 4. Install `debian` command launcher into Termux usr/bin
echo "[*] Step 4/5: Creating debian command launcher..."
$ADB_CMD shell "run-as com.termux sh -c '
export TMPDIR=/data/data/com.termux/files/usr/tmp
mkdir -p \$TMPDIR
cd \$TMPDIR
cat << \"EOF\" > /data/data/com.termux/files/usr/bin/debian
#!/data/data/com.termux/files/usr/bin/sh
unset LD_PRELOAD
export LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib
export PATH=/data/data/com.termux/files/usr/bin:\$PATH

ROOTFS=/data/data/com.termux/files/home/debian

# Ensure DNS is set
echo \"nameserver 1.1.1.1\" > \"\$ROOTFS/etc/resolv.conf\"
echo \"nameserver 8.8.8.8\" >> \"\$ROOTFS/etc/resolv.conf\"
chmod 644 \"\$ROOTFS/etc/resolv.conf\"

if [ \$# -gt 0 ]; then
  exec proot \
    --link2symlink \
    -0 \
    -r \"\$ROOTFS\" \
    -b /dev \
    -b /proc \
    -b /sys \
    -b /data/data/com.termux/files/home:/root/termux_home \
    -b /sdcard:/sdcard \
    -w /root \
    /usr/bin/env -i \
    HOME=/root \
    LANG=C.UTF-8 \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    TERM=\"\${TERM:-xterm-256color}\" \
    /bin/bash -c \"\$*\"
else
  exec proot \
    --link2symlink \
    -0 \
    -r \"\$ROOTFS\" \
    -b /dev \
    -b /proc \
    -b /sys \
    -b /data/data/com.termux/files/home:/root/termux_home \
    -b /sdcard:/sdcard \
    -w /root \
    /usr/bin/env -i \
    HOME=/root \
    LANG=C.UTF-8 \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    TERM=\"\${TERM:-xterm-256color}\" \
    /bin/bash --login
fi
EOF
chmod 755 /data/data/com.termux/files/usr/bin/debian
'"

# 5. Install common developer tools inside Debian
echo "[*] Step 5/5: Installing developer tools inside Debian..."
$ADB_CMD shell "run-as com.termux /data/data/com.termux/files/usr/bin/debian \"apt update && apt install -y --no-install-recommends curl htop nano git procps net-tools ca-certificates\""

echo ""
echo "=== Debian 12 Setup Complete! ==="
echo "You can now enter Debian by running: 'debian'"
