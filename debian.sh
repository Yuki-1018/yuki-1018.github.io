#!/bin/bash
set -e

# ==========================================
# Yuki Linux Build Script (Depency Fix)
# Target: Debian 13 (Trixie)
# ==========================================

# 1. 前準備
echo "[*] Installing build dependencies..."
sudo apt-get update
sudo apt-get install -y live-build live-manual live-config doc-debian debootstrap squashfs-tools xorriso

# 作業ディレクトリ
WORK_DIR="$HOME/yuki-trixie-fix"
echo "[*] Setting up work directory at $WORK_DIR..."

if [ -d "$WORK_DIR" ]; then
    echo "Cleaning up previous build files..."
    sudo rm -rf "$WORK_DIR"
fi
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# 2. 基本設定 (Trixie向け)
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
    --linux-packages "linux-image linux-headers"

# 3. APT Pinning 設定 (これが重要)
# ビルドプロセス中にSystemd-sysvがインストールされるのを防ぐ設定
mkdir -p config/archives
cat <<EOF > config/archives/no-systemd.pref.chroot
Package: systemd-sysv
Pin: release *
Pin-Priority: -1

Package: systemd
Pin: release *
Pin-Priority: -1

Package: sysvinit-core
Pin: release *
Pin-Priority: 1001
EOF

# インストール後のシステムにも同じ設定を残す
mkdir -p config/includes.chroot/etc/apt/preferences.d
cp config/archives/no-systemd.pref.chroot config/includes.chroot/etc/apt/preferences.d/no-systemd.pref

# 4. パッケージリストの作成 (修正版)
# 細かすぎる指定(sysv-rc等)や競合するもの(orphan-*)を削除し、
# sysvinit-core一本に絞って依存解決をAPTに任せる
mkdir -p config/package-lists

cat <<EOF > config/package-lists/yuki-core.list.chroot
# --- Core System (SysVinit) ---
sysvinit-core
# systemd系の明示的な除外
!systemd-sysv
!systemd

# --- Base Utils ---
e2fsprogs
coreutils
util-linux
procps
kmod

# --- Network ---
isc-dhcp-client
iproute2
net-tools
iputils-ping
firmware-linux-free
network-manager
# network-managerはsystemdを推奨するため、依存でsystemdが入ろうとするのを防ぐには
# 以下のパッケージでsysv対応させる必要がある場合があるが、
# Trixieではパッケージ名が変わっている可能性があるため、まずは単純化する。

# --- GUI Base ---
xserver-xorg-core
xinit
x11-xserver-utils
x11-utils
# ドライバ
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

# 5. ディレクトリ作成
echo "[*] Creating directory structure..."
mkdir -p config/hooks/live
mkdir -p config/includes.chroot/etc/skel
mkdir -p config/includes.chroot/etc/profile.d
mkdir -p config/includes.chroot/etc/apt/apt.conf.d
mkdir -p config/includes.chroot/root

# 6. 各種設定ファイルの作成

# フック: OS名
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

echo "Yuki Linux (SysV) \n \l" > /etc/issue
echo "yukilinux" > /etc/hostname
EOF
chmod +x config/hooks/live/01-branding.hook.chroot

# フック: クリーンアップ
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
echo 'APT::Install-Suggests "0";' >> config/includes.chroot/etc/apt/apt.conf.d/01norecommends

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

# 7. ビルド実行
echo "[*] Starting build process..."
# デバッグ情報を少し出すためにverboseを追加しても良い
sudo lb build

echo "=========================================="
echo "Build Complete!"
echo "ISO: $WORK_DIR/live-image-amd64.hybrid.iso"
echo "=========================================="
