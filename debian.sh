#!/bin/bash
set -e

# ==========================================
# Yuki Linux Build Script (Debian 13 Trixie)
# ==========================================

# 1. 前準備: 必要なツールのインストール
# 注意: Trixie環境で実行することを推奨しますが、Bookworm環境でも動作します
echo "[*] Installing build dependencies..."
sudo apt-get update
sudo apt-get install -y live-build live-manual live-config doc-debian debootstrap squashfs-tools xorriso

# 作業ディレクトリの設定
WORK_DIR="$HOME/yuki-trixie-build"
echo "[*] Setting up work directory at $WORK_DIR..."

if [ -d "$WORK_DIR" ]; then
    echo "Cleaning up previous build files..."
    sudo rm -rf "$WORK_DIR"
fi
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# 2. 基本設定 (lb config for Trixie)
# --distribution trixie : ターゲットをTrixieに
# --security false / --updates false : Testing版のためこれらをオフにしないとエラーになることが多い
echo "[*] Configuring live-build for Trixie..."
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

# 3. パッケージリストの作成
echo "[*] Creating package lists..."
mkdir -p config/package-lists

cat <<EOF > config/package-lists/yuki-core.list.chroot
# --- Core System (SysVinit化) ---
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

# --- GUI Base (Minimal Xorg) ---
xserver-xorg-core
xinit
x11-xserver-utils
x11-utils
# TrixieでもVESA/FBDEVは骨董品PC向けに有効
xserver-xorg-video-vesa
xserver-xorg-video-fbdev
xserver-xorg-input-evdev
xserver-xorg-input-libinput

# --- Apps (Experience Ignored) ---
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

# 4. ファイル配置用ディレクトリの作成
# 【最重要】ここで確実にディレクトリ階層を作ります
echo "[*] Creating directory structure..."
mkdir -p config/hooks/live
mkdir -p config/includes.chroot/etc
mkdir -p config/includes.chroot/root
mkdir -p config/includes.chroot/etc/skel
mkdir -p config/includes.chroot/etc/profile.d
mkdir -p config/includes.chroot/etc/apt/apt.conf.d

# 5. 各種設定ファイルの書き込み

# --- フック: OS名の変更 (Trixie対応) ---
cat <<'EOF' > config/hooks/live/01-branding.hook.chroot
#!/bin/sh
cat <<RELEASE > /etc/os-release
PRETTY_NAME="Yuki Linux (Trixie Base)"
NAME="Yuki Linux"
VERSION_ID="13"
VERSION="13 (trixie)"
ID=yukilinux
ID_LIKE=debian
HOME_URL="https://localhost"
SUPPORT_URL="https://localhost"
BUG_REPORT_URL="https://localhost"
RELEASE

echo "Yuki Linux (Trixie) \n \l" > /etc/issue
echo "Yuki Linux" > /etc/issue.net
echo "yukilinux" > /etc/hostname
echo "127.0.0.1   localhost" > /etc/hosts
echo "127.0.1.1   yukilinux" >> /etc/hosts
EOF
chmod +x config/hooks/live/01-branding.hook.chroot

# --- フック: 不要ファイル削除 ---
cat <<'EOF' > config/hooks/live/99-clean.hook.chroot
#!/bin/sh
# ドキュメント類削除
rm -rf /usr/share/doc/*
rm -rf /usr/share/man/*
rm -rf /usr/share/info/*
rm -rf /usr/share/lintian/*
# キャッシュ削除
rm -rf /var/cache/apt/archives/*.deb
# 英語以外削除
find /usr/share/locale -maxdepth 1 -mindepth 1 -type d | grep -v "en" | xargs rm -rf
# 装飾系削除
rm -rf /usr/share/backgrounds/*
rm -rf /usr/share/icons/Adwaita
rm -rf /usr/share/themes/*
EOF
chmod +x config/hooks/live/99-clean.hook.chroot

# --- APT設定: 推奨パッケージ無視 ---
echo 'APT::Install-Recommends "0";' > config/includes.chroot/etc/apt/apt.conf.d/01norecommends
echo 'APT::Install-Suggests "0";' >> config/includes.chroot/etc/apt/apt.conf.d/01norecommends

# --- .xinitrc (GUI起動設定) ---
cat <<'EOF' > config/includes.chroot/etc/skel/.xinitrc
#!/bin/sh
# マウス加速オフ
xset m 0 0
# 背景黒
xsetroot -solid black
# ウィンドウマネージャ
exec evilwm &
# メインターミナル
exec xterm -geometry 80x24+0+0 -bg black -fg white
EOF

# rootにもコピー
cp config/includes.chroot/etc/skel/.xinitrc config/includes.chroot/root/.xinitrc

# --- 自動startxスクリプト ---
# 以前エラーが出た場所。上のmkdir -pで作成済みなので確実に書き込める
cat <<'EOF' > config/includes.chroot/etc/profile.d/startx.sh
# TTY1ログイン時のみstartx
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ] && [ -z "$SSH_CONNECTION" ]; then
    echo "Welcome to Yuki Linux (Trixie)."
    startx
fi
EOF

# 6. ビルド実行
echo "[*] Starting build process for Trixie..."
# Trixieのパッケージ取得に時間がかかる場合があります
sudo lb build

echo "=========================================="
echo "Build Complete!"
echo "ISO Location: $WORK_DIR/live-image-amd64.hybrid.iso"
echo "Target: Debian 13 (Trixie)"
echo "GUI: EvilWM + xterm (No Login Manager)"
echo "=========================================="
