#!/bin/bash
set -e

# ==========================================
# Yuki Linux 1.0 (Codename: Snowdrop) Build Script
# Base: Debian 13 (Trixie) with Systemd (Stable Path)
# ==========================================

# 1. 準備: ビルドツールのインストール
echo "[*] Installing build dependencies..."
sudo apt-get update
sudo apt-get install -y live-build live-manual live-config doc-debian debootstrap squashfs-tools xorriso

# 作業ディレクトリのクリーンアップ
WORK_DIR="$HOME/yuki-linux-trixie"
echo "[*] Setting up work directory at $WORK_DIR..."
if [ -d "$WORK_DIR" ]; then
    sudo rm -rf "$WORK_DIR"
fi
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# 2. 基本設定 (lb config)
# --apt-recommends false: 推奨パッケージを入れない（軽量化の肝）
# --security/updates false: Trixie(Testing)ビルドエラー回避
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
    --linux-packages "linux-image linux-headers"

# 3. パッケージリストの作成 (最小限のGUIとツール)
mkdir -p config/package-lists
cat <<EOF > config/package-lists/yuki-core.list.chroot
# --- Core System (Systemd based) ---
systemd
systemd-sysv
udev
apt
coreutils
util-linux
procps
kmod
e2fsprogs
psmisc

# --- Network ---
network-manager
iproute2
iputils-ping
isc-dhcp-client
firmware-linux-free

# --- GUI Base (Minimal Xorg) ---
xserver-xorg-core
xinit
x11-xserver-utils
x11-utils
# 汎用ビデオドライバ
xserver-xorg-video-vesa
xserver-xorg-video-fbdev
xserver-xorg-input-libinput

# --- Window Manager & Apps ---
evilwm
xterm
# 最低限のコンパイル・編集用 (aptから追加可能なので最小限)
make
binutils
nano

# --- Hardware Support ---
pciutils
usbutils
kbd
console-setup
EOF

# 4. ディレクトリ構造の作成
echo "[*] Creating directory structure..."
mkdir -p config/hooks/live
mkdir -p config/includes.chroot/etc/skel
mkdir -p config/includes.chroot/etc/profile.d
mkdir -p config/includes.chroot/etc/apt/apt.conf.d
mkdir -p config/includes.chroot/root

# 5. カスタマイズ設定

# --- フック: Yuki Linux ブランド化 ---
cat <<'EOF' > config/hooks/live/01-branding.hook.chroot
#!/bin/sh
# OS名の上書き
cat <<RELEASE > /etc/os-release
PRETTY_NAME="Yuki Linux 1.0 (Snowdrop)"
NAME="Yuki Linux"
VERSION_ID="1.0"
VERSION="1.0 (Snowdrop)"
ID=yukilinux
ID_LIKE=debian
HOME_URL="http://localhost"
RELEASE

# ログインバナー
echo "Yuki Linux 1.0 (Snowdrop) \n \l" > /etc/issue
echo "yukilinux" > /etc/hostname

# ホスト設定
echo "127.0.0.1   localhost" > /etc/hosts
echo "127.0.1.1   yukilinux" >> /etc/hosts
EOF
chmod +x config/hooks/live/01-branding.hook.chroot

# --- フック: 不要なデータの徹底削除 ---
cat <<'EOF' > config/hooks/live/99-clean-bloat.hook.chroot
#!/bin/sh
# ドキュメント、マニュアル、ロケールの削除
rm -rf /usr/share/doc/*
rm -rf /usr/share/man/*
rm -rf /usr/share/info/*
find /usr/share/locale -maxdepth 1 -mindepth 1 -type d | grep -v "en" | xargs rm -rf

# 不要なSystemdユニットの無効化（さらに軽量化したい場合）
# systemctl disable bluetooth.service || true
# systemctl disable cups.service || true

# 装飾データの削除
rm -rf /usr/share/backgrounds/*
rm -rf /usr/share/icons/Adwaita
EOF
chmod +x config/hooks/live/99-clean-bloat.hook.chroot

# --- APT設定: 推奨パッケージを今後も入れない ---
echo 'APT::Install-Recommends "0";' > config/includes.chroot/etc/apt/apt.conf.d/01norecommends

# --- .xinitrc (GUIの起動定義) ---
cat <<'EOF' > config/includes.chroot/etc/skel/.xinitrc
#!/bin/sh
# 背景を黒に
xsetroot -solid black
# マウス加速を切る
xset m 0 0
# EvilWMをバックグラウンドで起動
exec evilwm &
# メインのターミナルを起動
exec xterm -geometry 80x24+0+0 -bg black -fg white
EOF
cp config/includes.chroot/etc/skel/.xinitrc config/includes.chroot/root/.xinitrc

# --- 自動GUI起動スクリプト ---
cat <<'EOF' > config/includes.chroot/etc/profile.d/startx.sh
# TTY1でログインした時のみ自動でGUIを起動
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ] && [ -z "$SSH_CONNECTION" ]; then
    echo "Welcome to Yuki Linux Snowdrop."
    startx
fi
EOF

# 6. ビルド実行
echo "[*] Starting build process (Systemd-base)..."
sudo lb build

echo "=========================================="
echo "Build Complete!"
echo "ISO Location: $WORK_DIR/live-image-amd64.hybrid.iso"
echo "OS Name: Yuki Linux 1.0 (Snowdrop)"
echo "GUI: EvilWM + xterm"
echo "=========================================="
