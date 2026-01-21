#!/bin/bash
set -e

# ==========================================
# Yuki Linux Build Script (Trixie/SysV Fix)
# Strategy: Allow Systemd initally, then Purge it.
# ==========================================

# 1. 準備
echo "[*] Installing build dependencies..."
sudo apt-get update
sudo apt-get install -y live-build live-manual live-config doc-debian debootstrap squashfs-tools xorriso

WORK_DIR="$HOME/yuki-trixie-v5"
echo "[*] Setting up work directory at $WORK_DIR..."

if [ -d "$WORK_DIR" ]; then
    sudo rm -rf "$WORK_DIR"
fi
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# 2. 基本設定 (lb config)
# 【修正点】
# --debootstrap-options: exclude/include から init 関連を削除し、Debianの標準挙動に任せる。
# これにより "Failure while installing base packages" を回避する。
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

# 3. APT Preferences (Pinning)
# ビルドの後半（chrootステージ）で SysVinit を強制し、Systemd を拒否する設定。
# debootstrapが終わった後に効力を発揮する。
mkdir -p config/archives
cat <<EOF > config/archives/prefer-sysv.pref.chroot
Package: systemd-sysv
Pin: release *
Pin-Priority: -1

Package: systemd
Pin: release *
Pin-Priority: -1

Package: sysvinit-core
Pin: release *
Pin-Priority: 1001

Package: elogind
Pin: release *
Pin-Priority: 1001
EOF

# OS内にも残す
mkdir -p config/includes.chroot/etc/apt/preferences.d
cp config/archives/prefer-sysv.pref.chroot config/includes.chroot/etc/apt/preferences.d/prefer-sysv.pref

# 4. パッケージリスト作成
# ここで sysvinit-core を入れると、APTが systemd-sysv を自動削除してくれる。
mkdir -p config/package-lists

cat <<EOF > config/package-lists/yuki-core.list.chroot
# --- Init Replacement (The Swap) ---
sysvinit-core
sysv-rc
orphan-sysvinit-scripts
elogind
libpam-elogind

# --- Kernel & Utils ---
linux-image-amd64
live-boot
coreutils
util-linux
procps
kmod
e2fsprogs
psmisc
# 骨董品対策
kbd
console-setup

# --- Network ---
isc-dhcp-client
iproute2
net-tools
iputils-ping
connman
firmware-linux-free

# --- GUI Base ---
xserver-xorg-core
xinit
x11-xserver-utils
x11-utils
# ドライバ (骨董品PC向け)
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

# --- フック: ブランド化 (Yuki Linux) ---
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

# --- フック: Systemd抹殺と掃除 ---
cat <<'EOF' > config/hooks/live/99-purge-systemd.hook.chroot
#!/bin/sh
echo "Purging Systemd remnants..."

# すでにパッケージリストでの指定によりAPTレベルでは削除されているはずだが、
# 念のため残留パッケージをパージする
apt-get purge -y systemd systemd-sysv libpam-systemd || true

# Systemdのディレクトリを物理削除
rm -rf /etc/systemd
rm -rf /lib/systemd
rm -rf /var/lib/systemd

# 不要ファイル掃除
rm -rf /usr/share/doc/*
rm -rf /usr/share/man/*
find /usr/share/locale -maxdepth 1 -mindepth 1 -type d | grep -v "en" | xargs rm -rf
rm -rf /usr/share/backgrounds/*
rm -rf /usr/share/icons/Adwaita
EOF
chmod +x config/hooks/live/99-purge-systemd.hook.chroot

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
echo "Note: Systemd was installed during bootstrap but purged during build."
echo "=========================================="
