# Fedora Dev Setup

A complete, modular automated setup for Fedora workstations. This setup includes development tools, containerization, virtualization, NVIDIA drivers, and productivity applications.

## 📦 What's Included

### System & Repositories
- **System Updates** - Full system update via DNF
- **RPM Fusion** - Free and non-free repositories for additional software

### Development Tools
- **Git** - Version control with user configuration
- **Node.js** - Via NVM (Node Version Manager) with latest LTS
- **Python** - Python 3 and pip package manager
- **VS Code** - Microsoft's code editor

### Containerization & Orchestration
- **Docker Engine** - Container runtime with Docker Compose plugin
- **kubectl** - Kubernetes command-line tool
- **Minikube** - Local Kubernetes cluster
- **Skaffold** - Kubernetes development workflow tool

### Virtualization
- **VirtualBox** - With Secure Boot MOK key setup and kernel module signing

### Applications
- **Google Chrome** - Web browser
- **Google Antigravity** - AI-powered IDE
- **Viber** - Messaging application
- **Telegram** - Messaging application

### Desktop Environment
- **GNOME Extensions** - Including:
  - Vitals (system monitoring)
  - Sound Input & Output Device Chooser
  - Tiling Shell (window management)

### Graphics & AI
- **NVIDIA Drivers** - Automatic detection and installation for NVIDIA GPUs
- **GPU Application Config** - Configures Chrome and VS Code to use discrete GPU
- **Ollama** - Local AI model runner

### Security
- **SSH** - SSH key generation and configuration

---

## 🚀 Quick Install

### Option 1: Local Install
```bash
git clone https://github.com/sergii-melnykov/linux.git
cd linux/fedora
sudo bash setup.sh
```

---

## 📋 Script Execution Order

The scripts run in numerical order (01-20). The order is optimized for dependencies:

1. **01_update.sh** - System updates
2. **02_rpm_fusion.sh** - Third-party repositories
3. **03_git.sh** - Version control
4. **04_nodejs.sh** - Node.js via NVM
5. **05_python.sh** - Python environment
6. **06_vscode.sh** - Code editor
7. **07_ssh.sh** - SSH setup
8. **08_virtualbox.sh** - Virtualization platform
9. **09_chrome.sh** - Web browser
10. **10_antigravity.sh** - AI IDE
11. **11_skaffold.sh** - Kubernetes dev tool
12. **12_docker.sh** - Container runtime
13. **13_kubectl.sh** - Kubernetes CLI
14. **14_minikube.sh** - Local Kubernetes
15. **15_gnome_extensions.sh** - Desktop extensions
16. **16_viber.sh** - Messaging app
17. **17_telegram.sh** - Messaging app
18. **18_nvidia_drivers.sh** - GPU drivers (auto-detects NVIDIA)
19. **19_gpu_app_config.sh** - GPU application preferences
20. **20_ollama.sh** - AI model runner

---

## ⚙️ Features

### Modular Design
Each component is in a separate script in the `scripts/` directory. You can:
- Run individual scripts manually
- Comment out scripts you don't need
- Add your own custom scripts

### Error Resilience
The main `setup.sh` script continues execution even if individual scripts fail, reporting all failures at the end.

### User-Aware Installation
Scripts detect when run with `sudo` and configure settings for the actual user (not root), including:
- Docker group membership
- GNOME extensions
- GPU application preferences

### Hardware Detection
- **NVIDIA GPU**: Automatically detects and skips driver installation if no NVIDIA GPU is present
- **Secure Boot**: VirtualBox setup includes MOK key generation for Secure Boot systems

---

## 🔧 Requirements

- Fedora (tested on recent versions)
- Sudo/root access
- Internet connection

---

## 📝 Post-Installation Notes

### Required Actions
1. **Reboot** - Required for:
   - VirtualBox kernel modules
   - NVIDIA drivers
   - Docker group membership to take effect

2. **VirtualBox Secure Boot** - After reboot:
   - Select "Enroll MOK" in the boot menu
   - Enter the password you set during installation
   - Continue to boot

3. **GNOME Extensions** - After reboot:
   - Open the "Extensions" app
   - Enable/configure installed extensions

### Verification Commands
```bash
# Docker
docker --version
docker run hello-world

# Node.js
nvm --version
node --version

# Kubernetes tools
kubectl version --client
minikube version

# NVIDIA (if applicable)
nvidia-smi
```

---

## 🛠️ Customization

To modify what gets installed:

1. Edit `setup.sh` to skip specific scripts
2. Modify individual scripts in `scripts/` directory
3. Add your own numbered scripts (e.g., `21_custom.sh`)

---

## 📄 License

MIT License - Feel free to use and modify
