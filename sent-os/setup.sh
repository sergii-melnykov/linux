#!/usr/bin/env bash
# Main setup script that runs modular scripts in scripts/ directory
# It continues execution even if individual scripts fail.

echo "====================================="
echo "🚀 SENT OS SETUP STARTED (MODULAR)"
echo "====================================="

# Check for sudo
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run with sudo:"
   echo "sudo bash setup.sh"
   exit 1
fi

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"

if [ ! -d "$SCRIPTS_DIR" ]; then
    echo "Error: scripts directory not found at $SCRIPTS_DIR"
    exit 1
fi

# Initialize array to track failed scripts
FAILED_SCRIPTS=()

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
        else
            echo "❌ $script_name FAILED. Continuing to next script..."
            # Optional: Add to a list of failed scripts to report at the end
            FAILED_SCRIPTS+=("$script_name")
        fi
    fi
done

echo ""
echo "====================================="
echo "🎉 SETUP PROCESS COMPLETED!"
if [ ${#FAILED_SCRIPTS[@]} -ne 0 ]; then
    echo "⚠️  The following scripts encountered errors:"
    for failed in "${FAILED_SCRIPTS[@]}"; do
        echo "   - $failed"
    done
    echo "Please check the output above for details."
else
    echo "All scripts executed successfully."
fi
echo "Reboot required to finish VirtualBox installation (if installed)."
echo "====================================="
