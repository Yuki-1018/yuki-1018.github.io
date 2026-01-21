#!/bin/bash
set -e

# ==========================================
# Yuki Linux Final Build Script (Trixie/SysV)
# Solution: Conflict-based Swap (No Pinning)
# ==========================================

# 1. 準備
echo "[*] Installing build dependencies..."
sudo apt-get update
sudo apt-get install -y live-build live-manual live-config doc-debian debootstrap squashfs-tools xorriso

WORK_DIR="$HOME/yuki-final-build"
echo "[*] Setting up work directory at $WORK_DIR..."

if [ -d "$WORK_DIR" ]; then
    sudo rm -rf "$WORK_DIR"
fi
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# 2. 基本設定 (lb config)
# シンプルに構成します。
# --debootstrap-options: 標準的なminbaseを使います（systemdは一旦入りますが、後で消えます）
echo "[*] Configuring live-build..."
lb config \
    --distribution trixie \
    --debian-installer live \
    --archive-areas "main contrib non-free-firmware" \
    --security false \
    --updates false \
    --apt-recommends false \
    --apt-indices false \
    --cache false \
    --iso-volume "Yuki_Linux_1.0" \
    --bootappend-live "boot=live components quiet splash hostname=yukilinux" \
    --linux-packages "linux-image linux-headers" \
    --debootstrap-options "--variant=minbase --include=apt,dpkg,linux-image-amd64,live-boot"

# 3. APT Pinning は「作成しません」
# ここが前回のエラー回避ポイントです。

# 4. パッケージリスト作成
# sysvinit-coreを指定することで、インストール時にsystemd-sysvが削除されます。
mkdir -p config/package-lists

cat <<EOF > config/package-lists/yuki-core.list.chroot
# --- Init System Swap ---
sysvinit-core
sysv-rc
orphan-sysvinit-scripts
# Systemd代替としてのElogind
elogind
libpam-elogind

# --- Kernel & Base Utils ---
linux-image-amd64
live-boot
coreutils
util-linux
procps
kmod
e2fsprogs
psmisc
# 骨董品対応
kbd
console-setup
# USB/PCI認識
pciutils
usbutils

# --- Network (No systemd deps) ---
isc-dhcp-client
iproute2
net-tools
iputils-ping
# connmanは依存が軽くGUIなしでも使える
connman
# 最低限のファームウェア
firmware-linux-free

# --- GUI Base ---
xserver-xorg-core
xinit
x11-xserver-utils
x11-utils
# ドライバ (VESA/FBDEV/Intel/AMD legacy)
xserver-xorg-video-vesa
xserver-xorg-video-fbdev
xserver-xorg-input-evdev
xserver-xorg-input-libinput

# --- Apps ---
evilwm
xterm
apt
dpkg
make
binutils
!build-essential
!man-db
!manpages
EOF

# 5. ディレクトリ構造作成
echo "[*] Creating directory structure..."
mkdir -p config/hooks/live
mkdir -p config/includes.chroot/etc/skel
mkdir -p config/includes.chroot/etc/profile.d
mkdir -p config/includes.chroot/etc/apt/apt.conf.d
mkdir -p config/includes.chroot/root

# 6. カスタマイズ設定

# --- フック: OS独自ブランド化 ---
cat <<'EOF' > config/hooks/live/01-branding.hook.chroot
#!/bin/sh
cat <<RELEASE > /etc/os-release
PRETTY_NAME="Yuki Linux 1.0 (Codename: Snowdrop)"
NAME="Yuki Linux"
VERSION_ID="1.0"
VERSION="1.0 (Snowdrop)"
VERSION_CODENAME=snowdrop
ID=yukilinux
ID_LIKE=debian
HOME_URL="http://localhost"
SUPPORT_URL="http://localhost"
BUG_REPORT_URL="http://localhost"
RELEASE

echo "Yuki Linux 1.0 (Snowdrop) \n \l" > /etc/issue
echo "yukilinux" > /etc/hostname
echo "127.0.0.1   localhost" > /etc/hosts
echo "127.0.1.1   yukilinux" >> /etc/hosts
EOF
chmod +x config/hooks/live/01-branding.hook.chroot

# --- フック: 掃除とSystemd残骸処理 ---
# APTが処理しきれなかった設定ファイル等を消す
cat <<'EOF' > config/hooks/live/99-cleanup.hook.chroot
#!/bin/sh
echo "Performing final cleanup..."
rm -rf /usr/share/doc/*
rm -rf /usr/share/man/*
find /usr/share/locale -maxdepth 1 -mindepth 1 -type d | grep -v "en" | xargs rm -rf
rm -rf /usr/share/backgrounds/*
rm -rf /usr/share/icons/Adwaita

# Systemdの設定ディレクトリ消去
rm -rf /etc/systemd
rm -rf /lib/systemd
EOF
chmod +x config/hooks/live/99-cleanup.hook.chroot

# --- APT設定 ---
echo 'APT::Install-Recommends "0";' > config/includes.chroot/etc/apt/apt.conf.d/01norecommends

# --- GUI設定 (.xinitrc) ---
cat <<'EOF' > config/includes.chroot/etc/skel/.xinitrc
#!/bin/sh
xset m 0 0
xsetroot -solid black
exec evilwm &
exec xterm -geometry 80x24+0+0 -bg black -fg white
EOF
cp config/includes.chroot/etc/skel/.xinitrc config/includes.chroot/root/.xinitrc

# --- 自動起動スクリプト ---
cat <<'EOF' > config/includes.chroot/etc/profile.d/startx.sh
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ] && [ -z "$SSH_CONNECTION" ]; then
    echo "Welcome to Yuki Linux (Snowdrop)."
    startx
fi
EOF

# 7. ビルド実行
echo "[*] Starting build process..."
sudo lb build

echo "=========================================="
echo "Build Complete!"
echo "ISO Location: $WORK_DIR/live-image-amd64.hybrid.iso"
echo "=========================================="
