#!/usr/bin/env bash
set -e

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
