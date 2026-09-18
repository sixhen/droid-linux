# droid-linux 🐧

Automated, high-performance, and lightweight Linux environment for Android (via Termux).

Copy, paste, and your full Linux workstation is ready in seconds.

[![Platform: Android](https://img.shields.io/badge/Platform-Termux%20%2F%20Android-green.svg)](https://termux.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## ⚡ 1-Line Quick Install

Open **Termux** on your phone and paste this command:

```bash
curl -fsSL https://raw.githubusercontent.com/sixhen/droid-linux/main/setup.sh | bash
```

> **Tip for fresh Termux**: If `curl` is not installed yet on your phone, run:
> ```bash
> pkg install -y curl && curl -fsSL https://raw.githubusercontent.com/sixhen/droid-linux/main/setup.sh | bash
> ```

Everything (PRoot, Ubuntu LTS rootfs, DNS patches, developer toolchain, and Zsh shell) is configured automatically without root permissions.

---

## 🚀 Usage

### 1. Enter Linux Terminal
Simply type:
```bash
droid-linux
# or short alias:
dlinux
```

### 2. Launch Graphical Desktop (XFCE4 + VNC)
Want a full desktop interface on your phone? Run:
```bash
droid-linux gui
```
Then open any VNC app on Android (such as **AVNC** or **VNC Viewer**), connect to:
- **Address**: `127.0.0.1:5901`
- **Password**: *(set on first launch)*

### 3. Stop Desktop Services
```bash
droid-linux stop
```

### 4. Backup Full System
```bash
droid-linux backup ~/my-linux-backup.tar.gz
```

---

## 📦 What's Included Out of the Box?

- **Base System**: Ubuntu LTS with multi-architecture support (`aarch64`, `arm`, `x86_64`).
- **Networking**: Pre-configured with Cloudflare & Google DNS (`1.1.1.1` / `8.8.8.8`) to avoid DNS resolve failures on mobile carriers.
- **Developer Tools**: `git`, `curl`, `wget`, `python3`, `pip`, `nodejs`, `npm`, `build-essential`, `nano`, `micro`, `htop`.
- **Shell Experience**: Custom Zsh shell with high-contrast prompt and productive aliases (`ll`, `update`, `ports`).
- **No Root Required**: Powered by userland PRoot technology.

---

## 🛠️ Uninstallation

If you ever want to completely remove the Linux container and free up space:

```bash
proot-distro remove ubuntu
rm -f $PREFIX/bin/droid-linux $PREFIX/bin/dlinux
```

---

## 📄 License

MIT License &copy; 2026 [sixhen](https://github.com/sixhen).
