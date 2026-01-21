#!/bin/bash
set -e

# ==========================================
# Yuki Linux 1.0 (Snowdrop) - Ultra Slim Edition
# ==========================================

echo "[*] Cleaning up previous build..."
WORK_DIR="$HOME/yuki-slim-build"
sudo rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# 1. 基本設定 (lb config)
# --compression xz: 圧縮率を最大にする
# --debian-installer live: テキストモードのインストーラーのみにする
echo "[*] Configuring live-build with XZ compression..."
lb config \
    --distribution trixie \
    --archive-areas "main contrib non-free-firmware" \
    --security false \
    --updates false \
    --apt-recommends false \
    --apt-indices false \
    --cache false \
    --compression xz \
    --iso-volume "Yuki_Slim" \
    --bootappend-live "boot=live components quiet splash hostname=yukilinux" \
    --linux-packages "linux-image" \
    --debian-installer live \
    --debian-installer-gui false

# 2. パッケージリストの厳選
mkdir -p config/package-lists
cat <<EOF > config/package-lists/yuki-core.list.chroot
# --- Core (Systemd) ---
systemd
systemd-sysv
udev
apt
coreutils
procps

# --- Network (NetworkManagerを捨ててConnmanへ) ---
connman
isc-dhcp-client
iproute2
firmware-linux-free

# --- GUI (Metapackageを避け、最小構成) ---
xserver-xorg-core
xinit
xterm
evilwm
xserver-xorg-video-vesa
xserver-xorg-video-fbdev
xserver-xorg-input-libinput

# --- Hardware & Lang ---
kbd
console-setup
pciutils
EOF

# 3. ディレクトリ作成
mkdir -p config/hooks/live
mkdir -p config/includes.chroot/etc/skel
mkdir -p config/includes.chroot/etc/profile.d
mkdir -p config/includes.chroot/root

# 4. 極限まで削るフック (More Aggressive Cleanup)
cat <<'EOF' > config/hooks/live/99-ultra-clean.hook.chroot
#!/bin/sh
echo "Aggressive cleaning..."
# ドキュメント、マニュアル、ロケールを完全に抹殺
rm -rf /usr/share/doc/*
rm -rf /usr/share/man/*
rm -rf /usr/share/info/*
rm -rf /usr/share/help/*
rm -rf /usr/share/gnome/help/*
find /usr/share/locale -maxdepth 1 -mindepth 1 -type d | grep -v "en" | xargs rm -rf

# 不要なライブラリやキャッシュ
apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/apt/archives/*.deb

# 巨大なファームウェアのなかで骨董品に関係ないものを消す (任意)
# rm -rf /lib/firmware/amdgpu # AMDが不要なら
EOF
chmod +x config/hooks/live/99-ultra-clean.hook.chroot

# 5. ブランド化フック
cat <<'EOF' > config/hooks/live/01-branding.hook.chroot
#!/bin/sh
cat <<RELEASE > /etc/os-release
PRETTY_NAME="Yuki Linux 1.0 (Snowdrop)"
NAME="Yuki Linux"
ID=yukilinux
RELEASE
echo "Yuki Linux 1.0" > /etc/issue
echo "yukilinux" > /etc/hostname
EOF
chmod +x config/hooks/live/01-branding.hook.chroot

# 6. 設定ファイル
cat <<'EOF' > config/includes.chroot/etc/skel/.xinitrc
#!/bin/sh
xsetroot -solid black
evilwm &
exec xterm -geometry 80x24+0+0 -bg black -fg white
EOF
cp config/includes.chroot/etc/skel/.xinitrc config/includes.chroot/root/.xinitrc

cat <<'EOF' > config/includes.chroot/etc/profile.d/startx.sh
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    startx
fi
EOF

# 7. ビルド
echo "[*] Building Yuki Linux Slim..."
sudo lb build

echo "=========================================="
echo "Build Complete!"
echo "ISO Location: $WORK_DIR/live-image-amd64.hybrid.iso"
echo "Check the size now!"
echo "=========================================="
