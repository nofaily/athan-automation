#!/bin/bash

# Prayer Times Generator - Shell Script Wrapper
# This script checks dependencies and runs the Python prayer times calculator

set -e

echo "=== Prayer Times Generator ==="
echo

# Set virtual environment path
# Change this path to your Python virtual environment path as needed.
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
    echo "Error: Python script 'calculate_prayer_times.py' not found in $SCRIPT_DIR"
    echo "Please ensure both scripts are in the same directory."
    exit 1
fi

# Run the Python script
echo "Starting prayer times calculator..."
echo
python3 "$PYTHON_SCRIPT"

# Check if the CSV was created successfully
if [ -f "prayer_times.csv" ]; then
    echo
    echo "✓ Success! Prayer times have been saved to 'prayer_times.csv'"
    echo "Total lines: $(wc -l < prayer_times.csv)"
else
    echo
    echo "✗ Error: prayer_times.csv was not created."
    exit 1
fi