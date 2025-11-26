#!/usr/bin/env bash
set -e

echo "====================================="
echo "🚀 FEDORA FULL DEV SETUP STARTED"
echo "====================================="

# Check for sudo
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run with sudo:"
   echo "sudo bash setup.sh"
   exit 1
fi

echo ""
echo "🔧 Updating system..."
dnf update -y


# -----------------------------------------------------------
# 1. RPM Fusion
# -----------------------------------------------------------
echo ""
echo "📦 Installing RPM Fusion..."
DNF_FUSION_FREE="https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"
DNF_FUSION_NONFREE="https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"

dnf install -y $DNF_FUSION_FREE $DNF_FUSION_NONFREE


# -----------------------------------------------------------
# 2. Git + basic config
# -----------------------------------------------------------
echo ""
echo "🐙 Installing Git..."
dnf install -y git

echo "🛠 Applying Git config..."
git config --global init.defaultBranch main
git config --global pull.rebase false
git config --global core.editor "vim"
git config --global color.ui auto
git config --global user.email "melnykov.sergii.88@gmail.com"
git config --global user.name "Sergii Melnykov"



# -----------------------------------------------------------
# 3. Docker + docker-compose
# -----------------------------------------------------------
echo ""
echo "🐳 Installing Docker..."
dnf install -y docker docker-compose

systemctl enable docker
systemctl start docker

echo "✔ Adding current user to docker group..."
usermod -aG docker "$SUDO_USER"


# -----------------------------------------------------------
# 4. Node.js + pnpm
# -----------------------------------------------------------
echo ""
echo "🟩 Installing Node.js (LTS)..."
dnf module reset nodejs -y
dnf module enable nodejs:20 -y
dnf install -y nodejs

echo "📦 Installing pnpm..."
npm install -g pnpm


# -----------------------------------------------------------
# 5. Python + pip
# -----------------------------------------------------------
echo ""
echo "🐍 Installing Python & pip..."
dnf install -y python3 python3-pip


# -----------------------------------------------------------
# 6. VSCode
# -----------------------------------------------------------
echo ""
echo "🖥 Installing Visual Studio Code..."
rpm --import https://packages.microsoft.com/keys/microsoft.asc
cat <<EOF > /etc/yum.repos.d/vscode.repo
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

dnf install -y code


# -----------------------------------------------------------
# 7. SSH keys
# -----------------------------------------------------------
echo ""
echo "🔐 Generating SSH keys (ed25519)..."
sudo -u "$SUDO_USER" ssh-keygen -t ed25519 -f "/home/$SUDO_USER/.ssh/id_ed25519" -q -N "" || echo "SSH key already exists"


# -----------------------------------------------------------
# 8. VirtualBox + Secure Boot signing (akmod)
# -----------------------------------------------------------
echo ""
echo "📦 Installing VirtualBox..."
dnf install -y akmods kernel-devel kernel-headers gcc make perl elfutils-libelf-devel

dnf install -y VirtualBox

echo ""
echo "📝 Creating MOK key for Secure Boot..."
mkdir -p /root/secureboot
cd /root/secureboot

openssl req -new -x509 \
  -newkey rsa:2048 \
  -nodes \
  -days 3650 \
  -subj "/CN=VirtualBoxModule/" \
  -keyout MOK.key \
  -out MOK.crt

echo ""
echo "🔏 Importing key into MOK..."
mokutil --import /root/secureboot/MOK.crt

echo "👉 After reboot, select 'Enroll MOK' → 'Continue' → Enter password"
echo "⚠️ System will reboot after install"


echo ""
echo "⚙️ Rebuilding kernel modules..."
akmods --force
modprobe vboxdrv || true


# -----------------------------------------------------------
# Finished
# -----------------------------------------------------------
echo ""
echo "====================================="
echo "🎉 SETUP COMPLETE!"
echo "Reboot required to finish VirtualBox installation."
echo "====================================="
