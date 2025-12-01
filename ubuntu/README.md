# Ubuntu Development Environment Setup

This directory contains a modular setup script for configuring a complete Ubuntu development environment.

## Overview

The setup process is organized into a main orchestrator script ([setup.sh](file:///home/sergii/projects/linux/ubuntu/setup.sh)) that executes individual installation scripts located in the `scripts/` directory. This modular approach allows for:

- **Easy maintenance**: Each component has its own script
- **Error resilience**: If one script fails, the setup continues with the next
- **Customization**: You can easily add, remove, or modify individual components

## Usage

Run the main setup script with sudo:

```bash
sudo bash setup.sh
```

The script will:
1. Execute all scripts in the `scripts/` directory in alphabetical order
2. Report success or failure for each script
3. Continue execution even if individual scripts fail
4. Provide a summary at the end showing which scripts (if any) failed

## Structure

```
ubuntu/
├── setup.sh          # Main orchestrator script
├── scripts/          # Individual installation scripts
│   ├── 01_*.sh      # First script to run
│   ├── 02_*.sh      # Second script to run
│   └── ...          # Additional scripts in order
└── README.md        # This file
```

## Adding New Scripts

To add a new installation component:

1. Create a new script in the `scripts/` directory
2. Use a numbered prefix (e.g., `15_myapp.sh`) to control execution order
3. Make sure the script is executable: `chmod +x scripts/15_myapp.sh`
4. The main `setup.sh` will automatically include it in the next run

## Requirements

- Ubuntu operating system
- Sudo privileges
- Internet connection for downloading packages

## Notes

- Some installations (like VirtualBox) may require a system reboot to complete
- The script will display a summary of any failed installations at the end
- Check the output for details if any script fails
