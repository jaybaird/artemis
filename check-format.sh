#!/bin/bash

# Check if all Vala files are properly formatted

set -e

# Check if uncrustify is installed
if ! command -v uncrustify &> /dev/null; then
    echo "Error: uncrustify is not installed."
    echo "Install it with: sudo apt install uncrustify"
    exit 1
fi

# Configuration file
CONFIG_FILE=".uncrustify.cfg"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: $CONFIG_FILE not found in current directory"
    exit 1
fi

# Find all Vala files and check formatting
echo "Checking Vala file formatting..."

FAILED_FILES=()

check_file() {
    local file="$1"
    local temp_file=$(mktemp)

    # Format file to temp location
    uncrustify -c "$CONFIG_FILE" -f "$file" -o "$temp_file" 2>/dev/null

    # Compare with original
    if ! diff -q "$file" "$temp_file" >/dev/null 2>&1; then
        FAILED_FILES+=("$file")
        echo "❌ $file is not properly formatted"
    else
        echo "✅ $file is properly formatted"
    fi

    rm -f "$temp_file"
}

# Check files in src/ directory
if [ -d "src" ]; then
    while IFS= read -r -d '' file; do
        check_file "$file"
    done < <(find src -name "*.vala" -print0)
fi

# Check files in tests/ directory if it exists
if [ -d "tests" ]; then
    while IFS= read -r -d '' file; do
        check_file "$file"
    done < <(find tests -name "*.vala" -print0)
fi

# Check any other .vala files in the root
while IFS= read -r -d '' file; do
    check_file "$file"
done < <(find . -maxdepth 1 -name "*.vala" -print0)

# Report results
if [ ${#FAILED_FILES[@]} -eq 0 ]; then
    echo ""
    echo "🎉 All files are properly formatted!"
    exit 0
else
    echo ""
    echo "❌ ${#FAILED_FILES[@]} file(s) need formatting:"
    for file in "${FAILED_FILES[@]}"; do
        echo "  - $file"
    done
    echo ""
    echo "Run './format.sh' to fix formatting issues."
    exit 1
fi