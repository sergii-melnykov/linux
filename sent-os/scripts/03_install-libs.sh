#!/usr/bin/env bash
set -e

echo "🔧 Installing gcc, kernel-devel, kernel-headers, make, bzip2, perl..."
dnf install gcc kernel-devel kernel-headers make bzip2 perl -y