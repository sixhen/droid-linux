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
    if [[ ! -d "/data/data/com.termux" ]]; then
        log_warn "Notice: This script is optimized for Termux on Android."
    fi

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
    log_info "Updating Termux packages and installing PRoot..."
    pkg update -y >/dev/null 2>&1 || true
    pkg install -y proot-distro curl tar pulseaudio >/dev/null 2>&1
    log_ok "Core dependencies installed (proot-distro, curl, pulseaudio)."
}

provision_distro() {
    if proot-distro list 2>/dev/null | grep -q "$DISTRO_NAME (installed)"; then
        log_warn "$DISTRO_NAME is already installed in proot-distro."
    else
        log_info "Downloading and installing official Ubuntu LTS rootfs..."
        proot-distro install "$DISTRO_NAME"
        log_ok "Ubuntu rootfs successfully extracted."
    fi

    local termux_prefix="${PREFIX:-/data/data/com.termux/files/usr}"
    local rootfs_dir="$termux_prefix/var/lib/proot-distro/installed-rootfs/$DISTRO_NAME"

    # Fix DNS resolution
    local resolv_conf="$rootfs_dir/etc/resolv.conf"
    if [[ -d "$rootfs_dir/etc" ]]; then
        printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" > "$resolv_conf" 2>/dev/null || true
        log_ok "Patched DNS resolution (Cloudflare & Google DNS)."
    fi

    # Create root .zshrc
    if [[ -d "$rootfs_dir/root" ]]; then
        cat << 'ZSH_EOF' > "$rootfs_dir/root/.zshrc"
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
PROMPT='%F{cyan}droid-linux%f %F{green}%~%f %F{yellow}❯%f '

alias ll='ls -lah --color=auto'
alias update='apt update && apt upgrade -y'
alias ports='ss -tulpn'
alias cls='clear'
alias py='python3'

printf "\033[38;5;141mWelcome to droid-linux (Ubuntu LTS on Android)\033[0m\n"
printf "\033[38;5;242mType 'update' to upgrade packages, or 'exit' to return to Termux.\033[0m\n\n"
ZSH_EOF
        log_ok "Configured customized Zsh profile."
    fi

    # Write provisioning script into rootfs /tmp
    local prov_script="$rootfs_dir/tmp/droid-provision.sh"
    cat << 'PROV_EOF' > "$prov_script"
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -y >/dev/null 2>&1
apt-get install -y --no-install-recommends \
    git curl wget sudo zsh python3 python3-pip nodejs npm \
    locales nano micro htop build-essential >/dev/null 2>&1

locale-gen en_US.UTF-8 >/dev/null 2>&1 || true
update-locale LANG=en_US.UTF-8 >/dev/null 2>&1 || true
chsh -s /bin/zsh root >/dev/null 2>&1 || true
PROV_EOF
    chmod +x "$prov_script"

    log_info "Configuring dev packages, locales and dev tools inside Ubuntu (this takes 1-2 minutes)..."
    proot-distro login "$DISTRO_NAME" -- bash /tmp/droid-provision.sh
    rm -f "$prov_script"
    log_ok "Ubuntu environment provisioned with developer toolchain."
}

install_launcher() {
    local termux_prefix="${PREFIX:-/data/data/com.termux/files/usr}"
    local bin_path="$termux_prefix/bin/droid-linux"
    log_info "Installing global CLI launcher to $bin_path..."

    cat << 'LAUNCHER_EOF' > "$bin_path"
#!/usr/bin/env bash
# droid-linux CLI launcher
set -e

DISTRO="ubuntu"

case "${1:-shell}" in
    shell|"")
        exec proot-distro login "$DISTRO" --user root --shared-tmp
        ;;
    gui|desktop)
        echo "Starting XFCE4 Desktop & TigerVNC..."
        proot-distro login "$DISTRO" --user root --shared-tmp -- /bin/bash -c '
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
        proot-distro login "$DISTRO" --user root -- /bin/bash -c "vncserver -kill :1 2>/dev/null || true"
        echo "✓ Services stopped."
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
        echo "Usage: droid-linux [shell | gui | stop | backup | status]"
        ;;
    *)
        echo "Unknown command: $1. Run 'droid-linux help' for usage."
        exit 1
        ;;
esac
LAUNCHER_EOF
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
