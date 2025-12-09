#!/bin/bash

# Prayer Times Generator - Shell Script Wrapper
# This script checks dependencies and runs the Python prayer times calculator

set -e

echo "=== Prayer Times Generator ==="
echo

# Set virtual environment path
VENV_PATH="$HOME/athan-automation-env"

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
    if ! "$PYTHON" -c "import ${package//-/_}" 2>/dev/null; then
        MISSING_PACKAGES+=("$package")
    fi
done

if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
    echo "Installing missing packages: ${MISSING_PACKAGES[*]}"
    "$PIP" install "${MISSING_PACKAGES[@]}" || {
        echo "Error: Failed to install required packages."
        echo "Please run: $PIP install ${MISSING_PACKAGES[*]}"
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
    exit 1
fi

# Create a temporary directory for output
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Run the Python script
echo "Starting prayer times calculator..."
echo "Output will be saved to: $TEMP_DIR/prayer_times.csv"
echo
"$PYTHON" "$PYTHON_SCRIPT"

# Check if the CSV was created successfully
if [ -f "prayer_times.csv" ]; then
    echo
    echo "✓ Success! Prayer times have been saved to temporary location"
    echo "  File: $TEMP_DIR/prayer_times.csv"
    echo "  Total lines: $(wc -l < prayer_times.csv)"
    echo
    echo "To install the prayer times file, run:"
    echo "  sudo mv $TEMP_DIR/prayer_times.csv /var/lib/athan-automation/prayer_times.csv"
    echo "  sudo chmod 644 /var/lib/athan-automation/prayer_times.csv"
    echo
    echo "Or to view it first:"
    echo "  cat $TEMP_DIR/prayer_times.csv | head -20"
    echo
    echo "Note: The file will be deleted when you reboot unless you move it."
else
    echo
    echo "✗ Error: prayer_times.csv was not created."
    cd ~
    rm -rf "$TEMP_DIR"
    exit 1
fi
