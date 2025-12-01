# Sent OS Setup Scripts

Automated setup scripts for configuring a Sent OS development environment.

## Overview

This repository contains modular shell scripts to automate the installation and configuration of essential packages and tools on Sent OS (RHEL/CentOS-based distribution).

## Prerequisites

- Fresh Sent OS installation
- Root/sudo access
- Internet connection

## Usage

Run the main setup script with sudo:

```bash
sudo bash setup.sh
```

The script will automatically execute all scripts in the `scripts/` directory in numerical order.

## What Gets Installed

The setup process includes:

1. **System Update** - Updates all system packages to the latest versions
2. **EPEL Release** - Installs Extra Packages for Enterprise Linux repository
3. **Development Libraries** - Installs essential build tools:
   - GCC compiler
   - Kernel development headers
   - Make build system
   - Bzip2 compression utility
   - Perl scripting language

## Script Structure

```
sent-os/
├── setup.sh              # Main orchestration script
└── scripts/
    ├── 01_update.sh                    # System update
    ├── 02_install-epel-release.sh      # EPEL repository
    └── 03_install-libs.sh              # Development libraries
```

## Features

- **Modular Design** - Each component is installed by a separate script
- **Error Handling** - Continues execution even if individual scripts fail
- **Progress Tracking** - Clear visual feedback for each installation step
- **Failure Reporting** - Summary of any failed scripts at the end

## Adding New Scripts

To add new installation scripts:

1. Create a new `.sh` file in the `scripts/` directory
2. Use numerical prefix for ordering (e.g., `04_nodejs.sh`)
3. Make it executable: `chmod +x scripts/04_your-script.sh`
4. Follow the existing script format:

```bash
#!/usr/bin/env bash
set -e

echo "🔧 Installing your-package..."
dnf install your-package
```

## Notes

- Scripts are executed in alphabetical/numerical order
- Each script runs with `set -e` to exit on errors
- The main setup.sh continues even if individual scripts fail
- A reboot may be required after installation completes

## License

This project is provided as-is for personal and educational use.
