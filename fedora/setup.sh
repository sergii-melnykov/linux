#!/usr/bin/env bash
# Main setup script that runs modular scripts in scripts/setup/ directory
# It continues execution even if individual scripts fail.

echo "====================================="
echo "🚀 FEDORA FULL DEV SETUP STARTED (MODULAR)"
echo "====================================="

# Check for sudo
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run with sudo:"
   echo "sudo bash setup.sh"
   exit 1
fi

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
SCRIPTS_DIR="$SCRIPT_DIR/scripts/setup"

if [ ! -d "$SCRIPTS_DIR" ]; then
    echo "Error: scripts directory not found at $SCRIPTS_DIR"
    exit 1
fi

# Initialize arrays to track results
FAILED_SCRIPTS=()
SUCCESSFUL_SCRIPTS=()

# Iterate through scripts in order
for script in "$SCRIPTS_DIR"/*.sh; do
    if [ -f "$script" ]; then
        script_name=$(basename "$script")
        echo ""
        echo "-----------------------------------------------------------"
        echo "▶ Running $script_name..."
        echo "-----------------------------------------------------------"
        
        # Run the script and capture exit code
        # We do NOT use set -e in this loop so we can continue on error
        if bash "$script"; then
            echo "✅ $script_name completed successfully."
            SUCCESSFUL_SCRIPTS+=("$script_name")
        else
            echo "❌ $script_name FAILED. Continuing to next script..."
            FAILED_SCRIPTS+=("$script_name")
        fi
    fi
done

echo ""
echo "====================================="
echo "🎉 SETUP PROCESS COMPLETED!"

if [ ${#SUCCESSFUL_SCRIPTS[@]} -ne 0 ]; then
    echo "✅ The following scripts were successful:"
    for success in "${SUCCESSFUL_SCRIPTS[@]}"; do
        echo "   - $success"
    done
fi

if [ ${#FAILED_SCRIPTS[@]} -ne 0 ]; then
    echo ""
    echo "⚠️  The following scripts encountered errors:"
    for failed in "${FAILED_SCRIPTS[@]}"; do
        echo "   - $failed"
    done
    echo "Please check the output above for details."
else
    if [ ${#SUCCESSFUL_SCRIPTS[@]} -ne 0 ]; then
        echo ""
        echo "All scripts executed successfully."
    fi
fi
echo "Reboot required to finish VirtualBox installation (if installed)."
echo "====================================="
