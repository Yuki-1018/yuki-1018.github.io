#!/bin/bash
set -e

# ==========================================
# Yuki Linux Build Script (Ultra Minimal)
# ==========================================

# 1. 必要なツールのインストール
echo "[*] Installing build dependencies..."
sudo apt-get update
sudo apt-get install -y live-build live-manual live-config doc-debian debootstrap squashfs-tools xorriso

# 作業ディレクトリの作成
WORK_DIR="$HOME/yuki-linux-build"
echo "[*] Creating work directory at $WORK_DIR..."
if [ -d "$WORK_DIR" ]; then
    sudo rm -rf "$WORK_DIR"
fi
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# 2. 基本設定 (lb config)
# --apt-recommends false: 推奨パッケージを入れない（最重要）
# --architectures amd64: 骨董品でも64bit前提(Core2以降)。Pentium4以前ならi386にする必要あり
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

# 3. パッケージリストの作成 (極限まで削る)
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
# Systemd排除のための必須パッケージ
orphan-sysvinit-scripts
!systemd
!systemd-sysv

# --- Network (DHCP & Basic tools) ---
isc-dhcp-client
iproute2
net-tools
iputils-ping
# Wi-Fiは骨董品ではドライバが重いので有線前提だが、最小ファームだけ入れる
firmware-linux-free
network-manager

# --- GUI Base (Xorg Minimal) ---
xserver-xorg-core
xinit
x11-xserver-utils
x11-utils
# ドライバはVESAとFBDEVのみ（互換性重視・サイズ削減）
xserver-xorg-video-vesa
xserver-xorg-video-fbdev
xserver-xorg-input-evdev
xserver-xorg-input-libinput

# --- Window Manager & Terminal ---
evilwm
xterm

# --- Package Management & Compilation Prep ---
apt
dpkg
# 拡張用：コンパイラは入れないがmake等の最小ツールだけ残す
# (aptでgccを入れるためのネット接続が生命線)
make
binutils
!build-essential
!man-db
!manpages
EOF

# 4. ブランディングと痕跡の消去 (Hooks)
mkdir -p config/hooks/live
mkdir -p config/includes.chroot/etc

# フック1: OS名の変更とDebian痕跡の抹消
cat <<'EOF' > config/hooks/live/01-branding.hook.chroot
#!/bin/sh
echo "Applying Yuki Linux Branding..."

# OS Release
cat <<RELEASE > /etc/os-release
PRETTY_NAME="Yuki Linux 1.0 (Antique Edition)"
NAME="Yuki Linux"
VERSION_ID="1.0"
VERSION="1.0"
ID=yukilinux
ID_LIKE=debian
HOME_URL="https://localhost"
SUPPORT_URL="https://localhost"
BUG_REPORT_URL="https://localhost"
RELEASE

# Issue (Login banner)
echo "Yuki Linux 1.0 \n \l" > /etc/issue
echo "Yuki Linux" > /etc/issue.net

# Hostname
echo "yukilinux" > /etc/hostname
echo "127.0.0.1   localhost" > /etc/hosts
echo "127.0.1.1   yukilinux" >> /etc/hosts
EOF
chmod +x config/hooks/live/01-branding.hook.chroot

# フック2: ブロートウェアの物理削除 (ドキュメント、ロケール)
cat <<'EOF' > config/hooks/live/99-clean.hook.chroot
#!/bin/sh
echo "Purging unnecessary files..."

# 不要なドキュメントとマニュアル削除
rm -rf /usr/share/doc/*
rm -rf /usr/share/man/*
rm -rf /usr/share/info/*
rm -rf /usr/share/lintian/*
rm -rf /usr/share/linda/*
rm -rf /var/cache/apt/archives/*.deb

# 英語(en)以外のロケールを削除
find /usr/share/locale -maxdepth 1 -mindepth 1 -type d | grep -v "en" | xargs rm -rf

# 壁紙やテーマ系も削除 (Xtermと黒画面のみなので不要)
rm -rf /usr/share/backgrounds/*
rm -rf /usr/share/icons/Adwaita
rm -rf /usr/share/icons/gnome
rm -rf /usr/share/themes/*

# APT設定: 今後も推奨パッケージを入れない
echo 'APT::Install-Recommends "0";' > /etc/apt/apt.conf.d/01norecommends
echo 'APT::Install-Suggests "0";' >> /etc/apt/apt.conf.d/01norecommends
EOF
chmod +x config/hooks/live/99-clean.hook.chroot

# 5. 自動GUI起動設定 (.xinitrc / .profile)
mkdir -p config/includes.chroot/root
mkdir -p config/includes.chroot/etc/skel

# .xinitrc (GUI起動時の動作)
# EvilWMを起動し、その上でxtermを一つ立ち上げる
# xtermが閉じるとGUIも落ちる仕様
cat <<'EOF' > config/includes.chroot/etc/skel/.xinitrc
#!/bin/sh
# マウスの加速をオフ（骨董品向け）
xset m 0 0
# 画面を真っ黒にする
xsetroot -solid black
# ウィンドウマネージャ起動
exec evilwm &
# メインのターミナル（これが本体）
exec xterm -geometry 80x24+0+0 -bg black -fg white
EOF

# root用にもコピー
cp config/includes.chroot/etc/skel/.xinitrc config/includes.chroot/root/.xinitrc

# オートログイン & startx (tty1のみ)
mkdir -p config/includes.chroot/etc/systemd/system/getty@tty1.service.d
# SysVinitの場合のオートログイン設定は /etc/inittab の編集が必要だが
# live-config が自動調整するため、profileに仕込む
cat <<'EOF' > config/includes.chroot/etc/profile.d/startx.sh
# TTY1かつSSHでない場合のみ自動起動
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ] && [ -z "$SSH_CONNECTION" ]; then
    echo "Welcome to Yuki Linux."
    echo "Starting minimalist environment..."
    startx
fi
EOF

# 6. インストーラーの設定 (Preseed)
# ネットワークがないと詰むので、インストーラーにはnetcfgを含める
# ただし、debian-installerの設定は複雑なので、デフォルトのテキストモードを利用する

# 7. ビルド実行
echo "[*] Starting build process (This will take time)..."
sudo lb build

echo "=========================================="
echo "Build Complete!"
echo "ISO location: $WORK_DIR/live-image-amd64.hybrid.iso"
echo "Name: Yuki Linux"
echo "GUI: EvilWM + xterm"
echo "=========================================="
