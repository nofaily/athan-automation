#!/bin/bash

# Prayer Times Generator - Shell Script Wrapper
# This script checks dependencies and runs the Python prayer times calculator
# REVISED: Automatically moves the generated CSV to the final destination using sudo.

set -e

echo "=== Prayer Times Generator ==="
echo

# Set virtual environment path
VENV_PATH="$HOME/athan-automation-env"

# Final destination for the prayer times CSV
FINAL_DESTINATION="/var/lib/athan-automation/prayer_times.csv"

# Check if virtual environment exists
if [ ! -d "$VENV_PATH" ]; then
    echo "Error: Virtual environment not found at $VENV_PATH"
    echo "Please create it with: python3 -m venv $VENV_PATH"
    exit 1
fi

# Activate virtual environment
source "$VENV_PATH/bin/activate"

# Use the virtual environment's Python and pip
PYTHON="$VENV_PATH/bin/python"
PIP="$VENV_PATH/bin/pip"

# Check if Python exists in venv
if [ ! -f "$PYTHON" ]; then
    echo "Error: Python not found in virtual environment at $PYTHON"
    exit 1
fi

# Check and install required Python packages
echo "Checking Python dependencies in virtual environment..."

REQUIRED_PACKAGES=("praytimes" "hijridate")
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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_SCRIPT="$SCRIPT_DIR/prayer_times_python.py"

if [ ! -f "$PYTHON_SCRIPT" ]; then
    echo "Error: Python script 'prayer_times_python.py' not found in $SCRIPT_DIR"
    echo "Please ensure both scripts are in the same directory."
    deactivate
    exit 1
fi

# Create a temporary directory for output
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
        echo "  The file remains at: $TEMP_CSV"
        exit 1
    fi
else
    echo
    echo "✗ Error: prayer_times.csv was not created by the Python script."
    exit 1
fi

# Cleanup
cd ~
rm -rf "$TEMP_DIR"
deactivate

# Exit successfully
exit 0
