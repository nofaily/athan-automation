#!/bin/bash

# Prayer Times Generator - Adaptive Shell Script Wrapper
# This script checks dependencies, sets paths, and runs the Python prayer times calculator.
# It uses an adaptive approach for portability between different Linux distributions.

set -e

echo "=== Prayer Times Generator ==="
echo

# --- Configuration Variables ---
VENV_PATH="/usr/local/share/athan-automation/venv"
FINAL_DESTINATION="/var/lib/athan-automation/prayer_times.csv"
REQUIRED_PACKAGES=("praytimes" "hijridate")

# --- Function to check for required binaries in VENV ---

check_venv_binaries() {
    PYTHON="$VENV_PATH/bin/python"
    PIP="$VENV_PATH/bin/pip"

    if [ ! -f "$PYTHON" ]; then
        echo "Error: Python binary not found in virtual environment at $PYTHON"
        return 1
    fi
    if [ ! -f "$PIP" ]; then
        echo "Warning: pip binary not found in virtual environment at $PIP. Dependency check may fail."
    fi
    return 0
}

# --- Main Script Start ---

# Check if virtual environment exists and is usable
if [ ! -d "$VENV_PATH" ] || [ ! -f "$VENV_PATH/bin/activate" ]; then
    echo "Error: Virtual environment not found or incomplete at $VENV_PATH"
    echo "Please run the setup script first."
    exit 1
fi

# Activate virtual environment
source "$VENV_PATH/bin/activate"

# Check and set VENV binaries
if ! check_venv_binaries; then
    deactivate
    exit 1
fi

# Check and install required Python packages
echo "Checking Python dependencies in virtual environment..."

MISSING_PACKAGES=()

for package in "${REQUIRED_PACKAGES[@]}"; do
    # Using python to check if module is importable
    if ! "$PYTHON" -c "import ${package//-/_}" 2>/dev/null; then
        MISSING_PACKAGES+=("$package")
    fi
done

if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
    echo "Installing missing packages: ${MISSING_PACKAGES[*]}"
    "$PIP" install "${MISSING_PACKAGES[@]}" || {
        echo "Error: Failed to install required packages."
        echo "Please run: $PIP install ${MISSING_PACKAGES[*]} and try again."
        deactivate
        exit 1
    }
    echo "Dependencies installed successfully!"
    echo
fi

# Check if the Python script exists
# Note: The assumption that the Python script is in the same directory must hold.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_SCRIPT="$SCRIPT_DIR/prayer_times_python.py"

if [ ! -f "$PYTHON_SCRIPT" ]; then
    echo "Error: Python script 'prayer_times_python.py' not found in $SCRIPT_DIR"
    echo "Please ensure both scripts are in the same directory."
    deactivate
    exit 1
fi

# Create a temporary directory for output and run script from there
TEMP_DIR=$(mktemp -d)
TEMP_CSV="$TEMP_DIR/prayer_times.csv"
cd "$TEMP_DIR"

# Run the Python script
echo "Starting prayer times calculator..."
echo "Output will be temporarily saved to: $TEMP_CSV"
echo
# The python script will prompt for input here
"$PYTHON" "$PYTHON_SCRIPT"

# Check if the CSV was created successfully
if [ -f "prayer_times.csv" ]; then
    echo
    echo "✓ Success! Prayer times CSV has been generated."
    
    # --- AUTOMATIC FILE MOVEMENT ---
    echo "Moving file to final location: $FINAL_DESTINATION (requires sudo)..."
    
    # Ensure the destination directory exists before moving
    sudo mkdir -p "$(dirname "$FINAL_DESTINATION")"

    sudo mv "prayer_times.csv" "$FINAL_DESTINATION"
    sudo chmod 644 "$FINAL_DESTINATION"
    
    if [ -f "$FINAL_DESTINATION" ]; then
        echo "✓ File successfully installed."
        echo "  File: $FINAL_DESTINATION"
        echo "  Total lines: $(wc -l < "$FINAL_DESTINATION")"
        echo
    else
        echo
        echo "✗ Error: Failed to move prayer_times.csv to $FINAL_DESTINATION"
        exit 1
    fi
else
    echo
    echo "✗ Error: prayer_times.csv was not created by the Python script."
    exit 1
fi

# Cleanup
rm -rf "$TEMP_DIR"
deactivate

# Exit successfully
exit 0
