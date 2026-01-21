#!/bin/bash
set -e

# ==========================================
# Yuki Linux Build Script (Fixed Version)
# ==========================================

# 1. 必要なツールのインストール
echo "[*] Installing build dependencies..."
sudo apt-get update
sudo apt-get install -y live-build live-manual live-config doc-debian debootstrap squashfs-tools xorriso

# 作業ディレクトリの作成
WORK_DIR="$HOME/yuki-linux-build"
echo "[*] Creating work directory at $WORK_DIR..."
# 既存のディレクトリがあるとエラーの原因になることがあるためクリーンアップ
if [ -d "$WORK_DIR" ]; then
    echo "Cleaning up previous build..."
    sudo rm -rf "$WORK_DIR"
fi
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# 2. 基本設定 (lb config)
echo "[*] Configuring live-build..."
lb config \
    --distribution bookworm \
    --debian-installer live \
    --archive-areas "main contrib non-free-firmware" \
    --apt-recommends false \
    --apt-indices false \
    --cache false \
    --iso-volume "Yuki_Linux_1.0" \
    --bootappend-live "boot=live components quiet splash hostname=yukilinux" \
    --linux-packages "linux-image linux-headers"

# 3. パッケージリストの作成
mkdir -p config/package-lists

cat <<EOF > config/package-lists/yuki-core.list.chroot
# --- Core System ---
sysvinit-core
sysv-rc
e2fsprogs
coreutils
util-linux
procps
kmod
orphan-sysvinit-scripts
!systemd
!systemd-sysv

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

# 4. ブランディングと痕跡の消去 (Hooks)
mkdir -p config/hooks/live
mkdir -p config/includes.chroot/etc

# フック1: OS名の変更
cat <<'EOF' > config/hooks/live/01-branding.hook.chroot
#!/bin/sh
cat <<RELEASE > /etc/os-release
PRETTY_NAME="Yuki Linux 1.0"
NAME="Yuki Linux"
VERSION_ID="1.0"
VERSION="1.0"
ID=yukilinux
ID_LIKE=debian
HOME_URL="https://localhost"
SUPPORT_URL="https://localhost"
BUG_REPORT_URL="https://localhost"
RELEASE

echo "Yuki Linux 1.0 \n \l" > /etc/issue
echo "Yuki Linux" > /etc/issue.net
echo "yukilinux" > /etc/hostname
echo "127.0.0.1   localhost" > /etc/hosts
echo "127.0.1.1   yukilinux" >> /etc/hosts
EOF
chmod +x config/hooks/live/01-branding.hook.chroot

# フック2: ブロートウェア削除
cat <<'EOF' > config/hooks/live/99-clean.hook.chroot
#!/bin/sh
rm -rf /usr/share/doc/*
rm -rf /usr/share/man/*
rm -rf /usr/share/info/*
rm -rf /usr/share/lintian/*
rm -rf /usr/share/linda/*
rm -rf /var/cache/apt/archives/*.deb
find /usr/share/locale -maxdepth 1 -mindepth 1 -type d | grep -v "en" | xargs rm -rf
rm -rf /usr/share/backgrounds/*
rm -rf /usr/share/icons/Adwaita
rm -rf /usr/share/themes/*

echo 'APT::Install-Recommends "0";' > /etc/apt/apt.conf.d/01norecommends
echo 'APT::Install-Suggests "0";' >> /etc/apt/apt.conf.d/01norecommends
EOF
chmod +x config/hooks/live/99-clean.hook.chroot

# 5. 自動GUI起動設定 (.xinitrc / .profile)
mkdir -p config/includes.chroot/root
mkdir -p config/includes.chroot/etc/skel
# 【修正】以下の行を追加しました
mkdir -p config/includes.chroot/etc/profile.d

# .xinitrc (GUI起動時の動作)
cat <<'EOF' > config/includes.chroot/etc/skel/.xinitrc
#!/bin/sh
xset m 0 0
xsetroot -solid black
exec evilwm &
exec xterm -geometry 80x24+0+0 -bg black -fg white
EOF

# root用にもコピー
cp config/includes.chroot/etc/skel/.xinitrc config/includes.chroot/root/.xinitrc

# オートログイン & startx (profile.dスクリプト)
cat <<'EOF' > config/includes.chroot/etc/profile.d/startx.sh
# TTY1かつSSHでない場合のみ自動起動
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
