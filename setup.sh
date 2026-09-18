#!/usr/bin/env bash
# droid-linux - Automated, High-Performance Linux on Android (Termux)
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
      _           _     _       _ _                  
   __| |_ __ ___ (_) __| |     | (_)_ __  _   ___  __
  / _` | '__/ _ \| |/ _` |_____| | | '_ \| | | \ \/ /
 | (_| | | | (_) | | (_| |_____| | | | | | |_| |>  < 
  \__,_|_|  \___/|_|\__,_|     |_|_|_| |_|\__,_/_/\_\
BANNER_EOF
    printf "${C_RESET}${C_GRAY}   Automated Linux Environment for Android · by sixhen${C_RESET}\n\n"
}

check_environment() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        aarch64|arm64)
            log_ok "Detected architecture: $arch (64-bit ARM - full speed)"
            ;;
        armv7l|arm)
            log_warn "Detected 32-bit ARM ($arch). Some modern 64-bit packages may be unavailable."
            ;;
        x86_64|amd64)
            log_ok "Detected x86_64 architecture."
            ;;
        *)
            log_warn "Architecture $arch detected. Compatibility may vary."
            ;;
    esac
}

install_dependencies() {
    log_info "Checking Termux core dependencies..."
    pkg install -y proot-distro curl tar pulseaudio >/dev/null 2>&1 || true
    log_ok "Core dependencies ready (proot-distro, curl, pulseaudio)."
}

provision_distro() {
    if proot-distro list 2>/dev/null | grep -i -q "$DISTRO_NAME.*installed"; then
        log_warn "Container '$DISTRO_NAME' đã có sẵn trên máy. Đang đồng bộ công cụ & cấu hình..."
    else
        log_info "Downloading and installing official Ubuntu LTS rootfs..."
        proot-distro install "$DISTRO_NAME" || true
        log_ok "Ubuntu rootfs ready."
    fi

    # Fix broken shell in /etc/passwd first via proot-distro run
    log_info "Verifying container shell integrity..."
    proot-distro run "$DISTRO_NAME" -- /bin/sed -i 's|:/bin/zsh|:/bin/bash|g' /etc/passwd 2>/dev/null || true

    log_info "Configuring dev packages, shell & system inside Ubuntu..."
    
    local prov_b64
    prov_b64=$(base64 -w0 << 'PROV_EOF'
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

# Ensure root shell in /etc/passwd is /bin/bash for safety
sed -i 's|:/bin/zsh|:/bin/bash|g' /etc/passwd 2>/dev/null || true

# Preserve existing DNS if valid, otherwise fallback to 1.1.1.1 & 8.8.8.8
if ! grep -q "nameserver" /etc/resolv.conf 2>/dev/null; then
    printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" > /etc/resolv.conf 2>/dev/null || true
fi

# Update and install dev tools
apt-get update -y
apt-get install -y --no-install-recommends \
    zsh git curl wget sudo python3 python3-pip nodejs npm \
    locales nano micro htop build-essential || \
apt-get install -y zsh git curl wget python3 nano micro htop || true

# Locales
if command -v locale-gen >/dev/null 2>&1; then
    locale-gen en_US.UTF-8 2>/dev/null || true
    update-locale LANG=en_US.UTF-8 2>/dev/null || true
fi

# Configure bashrc
cat << 'BASHRC_EOF' > /root/.bashrc
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
PS1='\[\033[38;5;39m\]droid-linux\[\033[0m\] \[\033[38;5;48m\]\w\[\033[0m\] \[\033[38;5;220m\]❯\[\033[0m\] '

alias ll='ls -lah --color=auto'
alias update='apt update && apt upgrade -y'
alias ports='ss -tulpn'
alias cls='clear'
alias py='python3'

if [ -z "$DROID_BANNER_PRINTED" ]; then
    export DROID_BANNER_PRINTED=1
    printf "\033[38;5;141mWelcome to droid-linux (Ubuntu LTS on Android)\033[0m\n"
    printf "\033[38;5;242mType 'update' to upgrade packages, or 'exit' to return to Termux.\033[0m\n\n"
fi
BASHRC_EOF

# Configure zshrc
cat << 'ZSH_EOF' > /root/.zshrc
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
PROMPT='%F{cyan}droid-linux%f %F{green}%~%f %F{yellow}❯%f '

alias ll='ls -lah --color=auto'
alias update='apt update && apt upgrade -y'
alias ports='ss -tulpn'
alias cls='clear'
alias py='python3'

if [ -z "$DROID_BANNER_PRINTED" ]; then
    export DROID_BANNER_PRINTED=1
    printf "\033[38;5;141mWelcome to droid-linux (Ubuntu LTS on Android)\033[0m\n"
    printf "\033[38;5;242mType 'update' to upgrade packages, or 'exit' to return to Termux.\033[0m\n\n"
fi
ZSH_EOF

# If zsh is available, update shell in /etc/passwd
if [ -x /bin/zsh ]; then
    chsh -s /bin/zsh root 2>/dev/null || true
fi
PROV_EOF
    )

    # Run provisioner safely using proot-distro run (bypasses login shell check)
    proot-distro run "$DISTRO_NAME" -- /bin/bash -c "echo '$prov_b64' | base64 -d | /bin/bash" || true
    log_ok "Ubuntu environment provisioned with developer toolchain."
}

install_launcher() {
    local termux_prefix="${PREFIX:-/data/data/com.termux/files/usr}"
    local bin_path="$termux_prefix/bin/droid-linux"
    log_info "Installing global CLI launcher to $bin_path..."

    local launcher_b64
    launcher_b64=$(base64 -w0 << 'LAUNCHER_EOF'
#!/usr/bin/env bash
# droid-linux CLI launcher
set -e

DISTRO="ubuntu"

case "${1:-shell}" in
    shell|"")
        exec proot-distro run "$DISTRO" --user root --shared-tmp -- /bin/bash -c '
            if [ -x /bin/zsh ]; then
                exec /bin/zsh -l
            else
                exec /bin/bash -l
            fi
        '
        ;;
    gui|desktop)
        echo "Starting XFCE4 Desktop & TigerVNC..."
        proot-distro run "$DISTRO" --user root --shared-tmp -- /bin/bash -c '
            if ! command -v vncserver >/dev/null 2>&1; then
                echo "Installing XFCE4 & TigerVNC desktop packages (first run)..."
                apt update -y && apt install -y xfce4 xfce4-terminal tigervnc-standalone-server dbus-x11
            fi
            vncserver -kill :1 >/dev/null 2>&1 || true
            vncserver :1 -geometry 1280x720 -depth 24
            echo "✓ VNC Server running at localhost:5901 (Display :1)"
            echo "Connect using any VNC Viewer app (address: 127.0.0.1:5901)"
        '
        ;;
    stop)
        echo "Stopping background services..."
        proot-distro run "$DISTRO" --user root -- /bin/bash -c "vncserver -kill :1 2>/dev/null || true"
        echo "✓ Services stopped."
        ;;
    reset)
        echo "Resetting Ubuntu container to factory fresh state..."
        proot-distro reset "$DISTRO"
        echo "✓ Ubuntu has been reset."
        ;;
    backup)
        OUT="${2:-$HOME/droid-linux-backup.tar.gz}"
        echo "Backing up droid-linux rootfs to $OUT..."
        proot-distro backup "$DISTRO" --output "$OUT"
        echo "✓ Backup complete: $OUT"
        ;;
    status)
        echo "=== droid-linux status ==="
        proot-distro list | grep "$DISTRO"
        ;;
    help|-h|--help)
        echo "Usage: droid-linux [shell | gui | stop | reset | backup | status]"
        ;;
    *)
        echo "Unknown command: $1. Run 'droid-linux help' for usage."
        exit 1
        ;;
esac
LAUNCHER_EOF
    )

    echo "$launcher_b64" | base64 -d > "$bin_path"
    chmod +x "$bin_path"
    
    # Symlink for ultra-short command: dlinux
    ln -sf "$bin_path" "$termux_prefix/bin/dlinux"
    log_ok "Global launcher created: 'droid-linux' & 'dlinux'"
}

main() {
    banner
    check_environment
    install_dependencies
    provision_distro
    install_launcher

    printf "\n${C_GREEN}${C_BOLD}✓ Installation Completed Successfully!${C_RESET}\n\n"
    printf "To start Linux anytime, simply type:\n"
    printf "  ${C_BOLD}${C_BLUE}droid-linux${C_RESET}   (hoặc ${C_BOLD}${C_BLUE}dlinux${C_RESET})\n\n"
    printf "To start Desktop GUI (XFCE4 / VNC):\n"
    printf "  ${C_BOLD}${C_BLUE}droid-linux gui${C_RESET}\n\n"
}

main "$@"
