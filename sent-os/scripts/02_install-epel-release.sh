#!/usr/bin/env bash
set -e

echo "🔧 Installing epel-release..."
dnf install epel-release -y
dnf update -y