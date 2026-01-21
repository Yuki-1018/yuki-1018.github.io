#!/bin/bash
set -e

# ==========================================
# Yuki Linux Build Script (Minbase Strategy)
# Target: Debian 13 (Trixie)
# Codename: Snowdrop / Version: 1.0
# ==========================================

# 1. 準備: 依存ツールの確認とディレクトリ初期化
echo "[*] Installing build dependencies..."
sudo apt-get update
sudo apt-get install -y live-build live-manual live-config doc-debian debootstrap squashfs-tools xorriso

WORK_DIR="$HOME/yuki-linux-build"
echo "[*] Setting up work directory at $WORK_DIR..."

if [ -d "$WORK_DIR" ]; then
    sudo rm -rf "$WORK_DIR"
fi
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# 2. 基本設定 (lb config)
# 【修正の核心】
# --debootstrap-options "--variant=minbase":
#    Debianの「標準システム」をインストールせず、極小の基礎のみ作る。
#    これによりSystemdを要求するメタパッケージ(standard-system)が除外される。
# --include:
#    minbaseだとaptやカーネルすら入らないので、init関連と合わせて明示的に指定する。
echo "[*] Configuring live-build (Minbase Mode)..."
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
    --debootstrap-options "--variant=minbase --include=apt,dpkg,sysvinit-core,sysv-rc,insserv,startpar,initscripts,orphan-sysvinit-scripts,linux-image-amd64,live-boot,whiptail,pciutils,usbutils,kbd --exclude=systemd-sysv,systemd"

# 3. パッケージリスト作成
# minbaseなので、通常なら「あって当たり前」のコマンドも書く必要がある
mkdir -p config/package-lists

cat <<EOF > config/package-lists/yuki-core.list.chroot
# --- Init & Base System ---
sysvinit-core
sysv-rc
insserv
startpar
initscripts
orphan-sysvinit-scripts
# ブロック
!systemd-sysv
!systemd

# --- Kernel & Boot ---
linux-image-amd64
live-boot
systemd-standalone-sysusers 
# ↑これはsystemd本体ではなく、ユーザー管理用のごく小さなライブラリ。Trixieでは多くのツールが依存するため許容する(initには影響しない)

# --- Basic Utils (Minimal) ---
coreutils
util-linux
procps
kmod
e2fsprogs
iproute2
net-tools
iputils-ping
isc-dhcp-client
nano
# 骨董品PC対応: マウス/キーボード認識用
udev
kbd

# --- Network Manager ---
# systemdなしで動く軽量なConnection Manager
connman
connman-ui
# WiFi GUI (GTKなし)
ceni
firmware-linux-free

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

# --- User Apps ---
evilwm
xterm
make
binutils
!build-essential
!man-db
!manpages
EOF

# 4. ディレクトリ構造作成
echo "[*] Creating directory structure..."
mkdir -p config/hooks/live
mkdir -p config/includes.chroot/etc/skel
mkdir -p config/includes.chroot/etc/profile.d
mkdir -p config/includes.chroot/etc/apt/apt.conf.d
mkdir -p config/includes.chroot/root

# 5. カスタマイズ設定

# --- フック: OS独自ブランド化 (Yuki Linux) ---
cat <<'EOF' > config/hooks/live/01-branding.hook.chroot
#!/bin/sh
# /etc/os-release の完全書き換え
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

# /etc/issue (ログイン前表示)
echo "Yuki Linux 1.0 (Snowdrop) - Minbase Edition \n \l" > /etc/issue
echo "Yuki Linux" > /etc/issue.net
echo "yukilinux" > /etc/hostname

# localhost設定
echo "127.0.0.1   localhost" > /etc/hosts
echo "127.0.1.1   yukilinux" >> /etc/hosts

# lsb-release (念のため)
echo "DISTRIB_ID=YukiLinux" > /etc/lsb-release
echo "DISTRIB_RELEASE=1.0" >> /etc/lsb-release
echo "DISTRIB_CODENAME=snowdrop" >> /etc/lsb-release
echo "DISTRIB_DESCRIPTION=\"Yuki Linux 1.0\"" >> /etc/lsb-release
EOF
chmod +x config/hooks/live/01-branding.hook.chroot

# --- フック: クリーンアップ ---
cat <<'EOF' > config/hooks/live/99-clean.hook.chroot
#!/bin/sh
rm -rf /usr/share/doc/*
rm -rf /usr/share/man/*
# 英語以外削除
find /usr/share/locale -maxdepth 1 -mindepth 1 -type d | grep -v "en" | xargs rm -rf
# GTKテーマ等のゴミ削除
rm -rf /usr/share/themes/*
rm -rf /usr/share/icons/Adwaita
EOF
chmod +x config/hooks/live/99-clean.hook.chroot

# --- APT設定 ---
echo 'APT::Install-Recommends "0";' > config/includes.chroot/etc/apt/apt.conf.d/01norecommends

# --- GUI設定 (.xinitrc) ---
cat <<'EOF' > config/includes.chroot/etc/skel/.xinitrc
#!/bin/sh
# 骨董品PC向け: マウス加速無効
xset m 0 0
# 画面真っ黒
xsetroot -solid black
# タイトルバーさえない極限WM
exec evilwm &
# メインターミナル
exec xterm -geometry 80x24+0+0 -bg black -fg white
EOF
cp config/includes.chroot/etc/skel/.xinitrc config/includes.chroot/root/.xinitrc

# --- 自動起動 (startx) ---
cat <<'EOF' > config/includes.chroot/etc/profile.d/startx.sh
# TTY1ログイン時のみstartx
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ] && [ -z "$SSH_CONNECTION" ]; then
    echo "Welcome to Yuki Linux (Snowdrop)."
    startx
fi
EOF

# 6. ビルド実行
echo "[*] Starting build process..."
# minbaseはダウンロード数が少ないので速いですが、初期構築に慎重になります
sudo lb build

echo "=========================================="
echo "Build Complete!"
echo "ISO Location: $WORK_DIR/live-image-amd64.hybrid.iso"
echo "OS Name: Yuki Linux 1.0 (Snowdrop)"
echo "Base: Debian Trixie (Minbase/SysVinit)"
echo "=========================================="
