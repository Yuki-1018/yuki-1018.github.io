#!/bin/bash
set -e

# ==========================================
# Yuki Linux Build Script (Trixie/SysVinit/Elogind)
# Codename: Snowdrop / Version: 1.0
# ==========================================

# 1. 準備
echo "[*] Installing build dependencies..."
sudo apt-get update
sudo apt-get install -y live-build live-manual live-config doc-debian debootstrap squashfs-tools xorriso

WORK_DIR="$HOME/yuki-trixie-sysv"
echo "[*] Setting up work directory at $WORK_DIR..."

if [ -d "$WORK_DIR" ]; then
    sudo rm -rf "$WORK_DIR"
fi
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# 2. 基本設定 (lb config)
# --variant=minbase: 最小構成から開始
# --include: 必須ツールと、依存解決の鍵となる 'elogind' を初期段階で含める
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
    --debootstrap-options "--variant=minbase --include=apt,dpkg,sysvinit-core,sysv-rc,elogind,libpam-elogind,linux-image-amd64,live-boot --exclude=systemd-sysv,systemd,libpam-systemd"

# 3. APT Preferences (Pinning) 設定
# これが依存関係地獄を解決する鍵です。
# systemd関連を禁止し、代わりにelogindやsysvinitを優先させます。
mkdir -p config/archives
cat <<EOF > config/archives/no-systemd.pref.chroot
Package: systemd-sysv
Pin: release *
Pin-Priority: -1

Package: systemd
Pin: release *
Pin-Priority: -1

Package: libpam-systemd
Pin: release *
Pin-Priority: -1

Package: sysvinit-core
Pin: release *
Pin-Priority: 1001

Package: elogind
Pin: release *
Pin-Priority: 1001

Package: libpam-elogind
Pin: release *
Pin-Priority: 1001
EOF

# インストール後のOSにもこの設定を引き継ぐ
mkdir -p config/includes.chroot/etc/apt/preferences.d
cp config/archives/no-systemd.pref.chroot config/includes.chroot/etc/apt/preferences.d/no-systemd.pref

# 4. パッケージリスト作成
# 依存関係エラーを防ぐため、systemdに強く依存するものは避け、代替品を選びます。
mkdir -p config/package-lists

cat <<EOF > config/package-lists/yuki-core.list.chroot
# --- Init System (SysV + Elogind) ---
sysvinit-core
sysv-rc
orphan-sysvinit-scripts
insserv
startpar
initscripts
# Systemdのログイン管理機能の代わり
elogind
libpam-elogind

# --- Kernel & Base ---
linux-image-amd64
live-boot
coreutils
util-linux
procps
kmod
e2fsprogs
psmisc

# --- Network (Low dependency) ---
isc-dhcp-client
iproute2
net-tools
iputils-ping
# connmanは依存が軽い
connman
# Wi-Fiファームウェア
firmware-linux-free

# --- GUI Base ---
xserver-xorg-core
xinit
x11-xserver-utils
x11-utils
# Xorgの依存関係でsystemdが入らないよう、推奨パッケージはオフにしてあるが
# policykitなどはelogindで満足させる

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

# --- Misc for Antique Hardware ---
kbd
console-setup
EOF

# 5. ディレクトリ構造作成
echo "[*] Creating directory structure..."
mkdir -p config/hooks/live
mkdir -p config/includes.chroot/etc/skel
mkdir -p config/includes.chroot/etc/profile.d
mkdir -p config/includes.chroot/etc/apt/apt.conf.d
mkdir -p config/includes.chroot/root

# 6. カスタマイズ設定

# フック: OS独自ブランド化
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
# Hosts設定
echo "127.0.0.1   localhost" > /etc/hosts
echo "127.0.1.1   yukilinux" >> /etc/hosts
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

# GUI設定 (.xinitrc)
cat <<'EOF' > config/includes.chroot/etc/skel/.xinitrc
#!/bin/sh
xset m 0 0
xsetroot -solid black
exec evilwm &
exec xterm -geometry 80x24+0+0 -bg black -fg white
EOF
cp config/includes.chroot/etc/skel/.xinitrc config/includes.chroot/root/.xinitrc

# 自動起動スクリプト
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
