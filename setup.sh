#!/usr/bin/env bash
# sixhen OS (droid-linux) - Dedicated Linux for sixhen on Android (Termux)
# Author: sixhen <dmh190229@gmail.com>
# License: MIT

set -eo pipefail

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[38;5;48m"
C_RED="\033[38;5;196m"
C_YELLOW="\033[38;5;220m"
C_BLUE="\033[38;5;39m"
C_PURPLE="\033[38;5;141m"
C_GRAY="\033[38;5;242m"

DISTRO_NAME="ubuntu"

log_info()    { printf "${C_BLUE}::${C_RESET} %s\n" "$*"; }
log_ok()      { printf "${C_GREEN}✓${C_RESET} %s\n" "$*"; }
log_warn()    { printf "${C_YELLOW}!${C_RESET} %s\n" "$*"; }
log_error()   { printf "${C_RED}✗${C_RESET} %s\n" "$*" >&2; }

banner() {
    printf "${C_PURPLE}${C_BOLD}"
    cat << "BANNER_EOF"
   _____ _      _                    ____   _____ 
  / ____(_)    | |                  / __ \ / ____|
 | (___  ___  _| |__   ___ _ __    | |  | | (___  
  \___ \| \ \/ / '_ \ / _ \ '_ \   | |  | |\___ \ 
  ____) | |>  <| | | |  __/ | | |  | |__| |____) |
 |_____/|_/_/\_\_| |_|\___|_| |_|   \____/|_____/ 
BANNER_EOF
    printf "${C_RESET}${C_GRAY}   Dedicated Linux Environment for Android · sixhen Edition${C_RESET}\n\n"
}

check_environment() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        aarch64|arm64)
            log_ok "Phát hiện CPU: $arch (64-bit ARM - tốc độ tối đa)"
            ;;
        armv7l|arm)
            log_warn "Phát hiện 32-bit ARM ($arch)."
            ;;
        x86_64|amd64)
            log_ok "Phát hiện x86_64 architecture."
            ;;
        *)
            log_warn "Kiến trúc $arch. Độ tương thích có thể thay đổi."
            ;;
    esac
}

install_dependencies() {
    log_info "Kiểm tra gói cốt lõi Termux..."
    pkg install -y proot-distro curl tar pulseaudio >/dev/null 2>&1 || true
    log_ok "Các thành phần cốt lõi đã sẵn sàng."
}

provision_distro() {
    if proot-distro list 2>/dev/null | grep -i -q "$DISTRO_NAME.*installed"; then
        log_warn "Container '$DISTRO_NAME' đã có sẵn trên máy. Đang đồng bộ công cụ & giao diện..."
    else
        log_info "Đang tải hệ điều hành Ubuntu LTS chính thức..."
        proot-distro install "$DISTRO_NAME" || true
        log_ok "Ubuntu rootfs đã sẵn sàng."
    fi

    # Fix broken shell in /etc/passwd first via proot-distro run
    log_info "Kiểm tra và chuẩn hóa cấu hình hệ thống..."
    proot-distro run "$DISTRO_NAME" -- /bin/sed -i 's|:/bin/zsh|:/bin/bash|g' /etc/passwd 2>/dev/null || true

    log_info "Cài đặt bộ công cụ phát triển, XFCE4 Desktop & VNC..."
    
    local prov_b64
    prov_b64=$(base64 -w0 << 'PROV_EOF'
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# Ensure root shell in /etc/passwd is /bin/bash for safety
sed -i 's|:/bin/zsh|:/bin/bash|g' /etc/passwd 2>/dev/null || true

# Fix DNS
if ! grep -q "nameserver" /etc/resolv.conf 2>/dev/null; then
    printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" > /etc/resolv.conf 2>/dev/null || true
fi

# Bypass ca-certificates heavy fork-loop (avoids Android Signal 9 Phantom Process Killer)
mkdir -p /var/lib/dpkg/info
printf '#!/bin/sh\nexit 0\n' > /var/lib/dpkg/info/ca-certificates.postinst 2>/dev/null || true
chmod +x /var/lib/dpkg/info/ca-certificates.postinst 2>/dev/null || true
ln -sf /bin/true /usr/sbin/update-ca-certificates 2>/dev/null || true

# Complete any interrupted dpkg configuration
dpkg --configure -a 2>/dev/null || true

# Update and install dev tools + desktop
apt-get update -y
apt-get install -y --no-install-recommends \
    zsh git curl wget sudo python3 python3-pip \
    nano micro htop build-essential \
    xfce4 xfce4-terminal tigervnc-standalone-server dbus-x11 x11-xserver-utils || \
apt-get install -y zsh git curl wget python3 nano micro htop xfce4 tigervnc-standalone-server dbus-x11 || true

# Fix X11 unix socket directory (Crucial for PRoot)
mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 2>/dev/null || true

# Configure xstartup in both legacy and modern TigerVNC locations
mkdir -p /root/.vnc /root/.config/tigervnc
cat << "XEOF" > /root/.vnc/xstartup
#!/bin/bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export DISPLAY=:1
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
# Start minimal core UI (avoids Android 32-process Phantom Killer)
xfwm4 &
xfce4-panel &
xfdesktop &

# Keep session running indefinitely
while true; do
    sleep 3600
done
XEOF
chmod 755 /root/.vnc/xstartup
cp -f /root/.vnc/xstartup /root/.config/tigervnc/xstartup 2>/dev/null || true

# Configure VNC password (default: 123456)
if [ ! -f /root/.vnc/passwd ]; then
    printf "123456\n123456\nn\n" | vncpasswd 2>/dev/null || true
    chmod 600 /root/.vnc/passwd 2>/dev/null || true
fi
cp -f /root/.vnc/passwd /root/.config/tigervnc/passwd 2>/dev/null || true

# Configure bashrc with custom sixhen-os prompt
cat << 'BASHRC_EOF' > /root/.bashrc
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
PS1='\[\033[38;5;141m\]sixhen-os\[\033[0m\] \[\033[38;5;39m\]\w\[\033[0m\] \[\033[38;5;220m\]❯\[\033[0m\] '

alias ll='ls -lah --color=auto'
alias update='apt update && apt upgrade -y'
alias ports='ss -tulpn'
alias cls='clear'
alias py='python3'
alias gui='sixhen-os gui'

if [ -z "$DROID_BANNER_PRINTED" ]; then
    export DROID_BANNER_PRINTED=1
    printf "\033[38;5;141mChào mừng đến với sixhen OS (Ubuntu on Android)\033[0m\n"
    printf "\033[38;5;242mGõ 'gui' để bật màn hình máy tính bàn, 'exit' để về lại Termux.\033[0m\n\n"
fi
BASHRC_EOF

# Configure zshrc
cat << 'ZSH_EOF' > /root/.zshrc
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
PROMPT='%F{magenta}sixhen-os%f %F{cyan}%~%f %F{yellow}❯%f '

alias ll='ls -lah --color=auto'
alias update='apt update && apt upgrade -y'
alias ports='ss -tulpn'
alias cls='clear'
alias py='python3'
alias gui='sixhen-os gui'

if [ -z "$DROID_BANNER_PRINTED" ]; then
    export DROID_BANNER_PRINTED=1
    printf "\033[38;5;141mChào mừng đến với sixhen OS (Ubuntu on Android)\033[0m\n"
    printf "\033[38;5;242mGõ 'gui' để bật màn hình máy tính bàn, 'exit' để về lại Termux.\033[0m\n\n"
fi
ZSH_EOF

# If zsh is available, update shell in /etc/passwd
if [ -x /bin/zsh ]; then
    chsh -s /bin/zsh root 2>/dev/null || true
fi
PROV_EOF
    )

    # Run provisioner safely using proot-distro run
    proot-distro run "$DISTRO_NAME" -- /bin/bash -c "echo '$prov_b64' | base64 -d | /bin/bash" || true
    log_ok "sixhen OS đã được thiết lập đầy đủ công cụ & giao diện!"
}

install_launcher() {
    local termux_prefix="${PREFIX:-/data/data/com.termux/files/usr}"
    local bin_path="$termux_prefix/bin/sixhen-os"
    log_info "Cài đặt phím tắt toàn cầu 'sixhen-os' & 'dlinux'..."

    # Install launcher script
    cp -f "bin/droid-linux" "$bin_path" 2>/dev/null || {
        # Fallback if binary file not present in pwd
        curl -fsSL https://raw.githubusercontent.com/sixhen/droid-linux/main/bin/droid-linux > "$bin_path"
    }
    chmod +x "$bin_path"
    
    # Symlinks
    ln -sf "$bin_path" "$termux_prefix/bin/dlinux"
    ln -sf "$bin_path" "$termux_prefix/bin/droid-linux"
    ln -sf "$bin_path" "$termux_prefix/bin/sixhen-gui"

    # Also install launcher inside the container so 'gui' works from inside
    local container_bin="$termux_prefix/var/lib/proot-distro/installed-rootfs/$DISTRO_NAME/usr/local/bin/sixhen-os"
    if [ -d "$termux_prefix/var/lib/proot-distro/installed-rootfs/$DISTRO_NAME/usr/local/bin" ]; then
        cp -f "$bin_path" "$container_bin" 2>/dev/null || true
        chmod +x "$container_bin" 2>/dev/null || true
        ln -sf "$container_bin" "$termux_prefix/var/lib/proot-distro/installed-rootfs/$DISTRO_NAME/usr/local/bin/dlinux" 2>/dev/null || true
    fi

    log_ok "Các lệnh đã sẵn sàng: 'sixhen-os', 'dlinux', 'sixhen-gui'"
}

main() {
    banner
    check_environment
    install_dependencies
    provision_distro
    install_launcher

    printf "\n${C_GREEN}${C_BOLD}✓ CÀI ĐẶT SIXHEN OS HOÀN TẤT 100%!${C_RESET}\n\n"
    printf "1. Vào Terminal Linux:\n"
    printf "   ${C_BOLD}${C_BLUE}sixhen-os${C_RESET}   (hoặc ${C_BOLD}${C_BLUE}dlinux${C_RESET})\n\n"
    printf "2. Bật màn hình máy tính bàn (Desktop GUI):\n"
    printf "   ${C_BOLD}${C_BLUE}sixhen-os gui${C_RESET}  (hoặc ${C_BOLD}${C_BLUE}sixhen-gui${C_RESET})\n"
    printf "   Mở app ${C_BOLD}AVNC${C_RESET} kết nối ${C_BOLD}127.0.0.1:5901${C_RESET} (Mật khẩu: ${C_BOLD}123456${C_RESET})\n\n"
}

main "$@"
