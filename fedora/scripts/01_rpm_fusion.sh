#!/usr/bin/env bash
set -e

echo "📦 Installing RPM Fusion..."
DNF_FUSION_FREE="https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"
DNF_FUSION_NONFREE="https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"

dnf install -y $DNF_FUSION_FREE $DNF_FUSION_NONFREE
