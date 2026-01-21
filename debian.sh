#!/bin/bash
set -e

# ==========================================
# Yuki Linux Build Script (Final Architecture)
# Target: Debian 13 (Trixie) - Pure SysVinit
# ==========================================

# 1. 準備
echo "[*] Installing build dependencies..."
sudo apt-get update
sudo apt-get install -y live-build live-manual live-config doc-debian debootstrap squashfs-tools xorriso

WORK_DIR="$HOME/yuki-trixie-final"
echo "[*] Setting up work directory at $WORK_DIR..."

if [ -d "$WORK_DIR" ]; then
    sudo rm -rf "$WORK_DIR"
fi
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# 2. 基本設定 (lb config)
# 【最重要修正点】
# --debootstrap-options: ベースシステム構築時に sysvinit-core を入れ、systemd-sysv を除外する
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
    --iso-volume "Yuki_Linux_Trixie" \
    --bootappend-live "boot=live components quiet splash hostname=yukilinux" \
    --linux-packages "linux-image linux-headers" \
    --debootstrap-options "--include=sysvinit-core --exclude=systemd-sysv,systemd"

# 3. パッケージリスト作成
# ここではシンプルなリストにする（競合回避のため）
mkdir -p config/package-lists

cat <<EOF > config/package-lists/yuki-core.list.chroot
# --- Init System ---
# debootstrapで既に入っているが、念のため指定
sysvinit-core
sysv-rc
# 以下の除外記述は念のため残すが、debootstrap除外が効いていればConflictしない
!systemd-sysv
!systemd

# --- Network ---
isc-dhcp-client
iproute2
net-tools
iputils-ping
firmware-linux-free
network-manager

# --- GUI Base ---
xserver-xorg-core
xinit
x11-xserver-utils
x11-utils
# 骨董品PC向けドライバ
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

# 4. ディレクトリ作成
echo "[*] Creating directory structure..."
mkdir -p config/hooks/live
mkdir -p config/includes.chroot/etc/skel
mkdir -p config/includes.chroot/etc/profile.d
mkdir -p config/includes.chroot/etc/apt/apt.conf.d
mkdir -p config/includes.chroot/root

# 5. フック設定

# OS名変更
cat <<'EOF' > config/hooks/live/01-branding.hook.chroot
#!/bin/sh
cat <<RELEASE > /etc/os-release
PRETTY_NAME="Yuki Linux (Trixie/SysV)"
NAME="Yuki Linux"
VERSION_ID="13"
VERSION="13 (trixie)"
ID=yukilinux
ID_LIKE=debian
HOME_URL="http://localhost"
SUPPORT_URL="http://localhost"
BUG_REPORT_URL="http://localhost"
RELEASE
echo "Yuki Linux (SysV)" > /etc/issue
echo "yukilinux" > /etc/hostname
EOF
chmod +x config/hooks/live/01-branding.hook.chroot

# 掃除
cat <<'EOF' > config/hooks/live/99-clean.hook.chroot
#!/bin/sh
rm -rf /usr/share/doc/*
rm -rf /usr/share/man/*
find /usr/share/locale -maxdepth 1 -mindepth 1 -type d | grep -v "en" | xargs rm -rf
rm -rf /usr/share/backgrounds/*
rm -rf /usr/share/icons/Adwaita
EOF
chmod +x config/hooks/live/99-clean.hook.chroot

# APT設定
echo 'APT::Install-Recommends "0";' > config/includes.chroot/etc/apt/apt.conf.d/01norecommends

# .xinitrc
cat <<'EOF' > config/includes.chroot/etc/skel/.xinitrc
#!/bin/sh
xset m 0 0
xsetroot -solid black
exec evilwm &
exec xterm -geometry 80x24+0+0 -bg black -fg white
EOF
cp config/includes.chroot/etc/skel/.xinitrc config/includes.chroot/root/.xinitrc

# startxスクリプト
cat <<'EOF' > config/includes.chroot/etc/profile.d/startx.sh
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ] && [ -z "$SSH_CONNECTION" ]; then
    echo "Welcome to Yuki Linux."
    startx
fi
EOF

# 6. ビルド実行
echo "[*] Starting build process..."
sudo lb build

echo "=========================================="
echo "Build Complete!"
echo "ISO: $WORK_DIR/live-image-amd64.hybrid.iso"
echo "=========================================="
