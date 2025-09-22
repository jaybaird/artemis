#!/bin/bash

# Format all Vala files in the project using uncrustify

set -e

# Check if uncrustify is installed
if ! command -v uncrustify &> /dev/null; then
    echo "Error: uncrustify is not installed."
    echo "Install it with: sudo apt install uncrustify"
    echo "Or on other distros: sudo dnf install uncrustify, pacman -S uncrustify, etc."
    exit 1
fi

# Configuration file
CONFIG_FILE=".uncrustify.cfg"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: $CONFIG_FILE not found in current directory"
    exit 1
fi

# Find all Vala files
echo "Formatting Vala files..."

# Format files in src/ directory
if [ -d "src" ]; then
    find src -name "*.vala" -exec uncrustify -c "$CONFIG_FILE" --replace --no-backup {} \;
    echo "Formatted files in src/"
fi

# Format files in tests/ directory if it exists
if [ -d "tests" ]; then
    find tests -name "*.vala" -exec uncrustify -c "$CONFIG_FILE" --replace --no-backup {} \;
    echo "Formatted files in tests/"
fi

# Format any other .vala files in the root
find . -maxdepth 1 -name "*.vala" -exec uncrustify -c "$CONFIG_FILE" --replace --no-backup {} \;

echo "Code formatting complete!"