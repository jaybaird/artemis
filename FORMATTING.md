# Code Formatting

This project uses [uncrustify](https://github.com/uncrustify/uncrustify) to automatically format Vala code according to GNOME coding standards.

## Installation

Install uncrustify on your system:

**Ubuntu/Debian:**
```bash
sudo apt install uncrustify
```

**Fedora:**
```bash
sudo dnf install uncrustify
```

**Arch Linux:**
```bash
sudo pacman -S uncrustify
```

**macOS:**
```bash
brew install uncrustify
```

## Usage

### Format all code
```bash
./format.sh
```
or using meson:
```bash
meson compile -C build format
```

### Check formatting without changing files
```bash
./check-format.sh
```
or using meson:
```bash
meson compile -C build check-format
```

## Automatic Formatting

### Pre-commit Hook
A pre-commit hook is automatically installed that checks formatting before each commit. If formatting issues are found, the commit will be rejected.

To bypass the check (not recommended):
```bash
git commit --no-verify
```

### Editor Integration

#### Visual Studio Code
Install the "Uncrustify" extension and add this to your settings.json:
```json
{
    "uncrustify.configPath": ".uncrustify.cfg",
    "editor.formatOnSave": true,
    "[vala]": {
        "editor.defaultFormatter": "LaurentTreguier.uncrustify"
    }
}
```

#### Vim/Neovim
Add to your vimrc:
```vim
autocmd FileType vala setlocal formatprg=uncrustify\ -c\ .uncrustify.cfg\ -l\ VALA
```

#### Emacs
```elisp
(add-hook 'vala-mode-hook
          (lambda ()
            (setq-local uncrustify-config-file ".uncrustify.cfg")))
```

## Configuration

The formatting configuration is in `.uncrustify.cfg`. This follows GNOME Vala coding standards with:

- 4 spaces for indentation (no tabs)
- Consistent spacing around operators and braces
- Consistent newline placement
- Automatic brace insertion for control structures

## Troubleshooting

### Permission denied
Make sure the scripts are executable:
```bash
chmod +x format.sh check-format.sh
```

### Uncrustify not found
Ensure uncrustify is installed and in your PATH:
```bash
which uncrustify
```

### Format check failing in CI
Make sure to run `./format.sh` locally before pushing to ensure all code is properly formatted.