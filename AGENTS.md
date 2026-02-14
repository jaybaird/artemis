# Artemis Agent Guide

## Project Summary
Artemis is a Vala/GTK4 + Libadwaita desktop app for hunting Parks on the Air (POTA) spots.

Core features:
- Spot list and filtering (band/mode/program/search)
- Map visualization with Shumate
- Radio CAT control via Hamlib
- Local spot/QSO data in SQLite
- Packaging for Flatpak and AppImage

## Technology Stack
- Language: Vala (plus a C bridge for radio control)
- UI: GTK4, Libadwaita, Blueprint UI files
- Build: Meson + Ninja
- Data: SQLite
- Network/API: libsoup + JSON-GLib
- Map: libshumate
- Radio: Hamlib through `src/radio_control.c`

## Important Paths
- `src/` application logic
- `blueprints/` source UI definitions
- `data/ui/` generated UI XML resources
- `data/` desktop/metainfo/gschema/resources/icons
- `po/` translations and gettext config
- `com.k0vcz.Artemis.json` Flatpak manifest
- `scripts/release-flatpak.sh` Flatpak bundle build
- `scripts/release-appimage.sh` AppImage build

## Build and Validation
- Build: `meson setup build && meson compile -C build`
- Reconfigure: `meson setup build --reconfigure`
- Translation template: `ninja -C build com.k0vcz.Artemis-pot`

When changing UI/resources, ensure the build succeeds and generated resources remain valid.

## Release Notes
- Flatpak artifacts output to `dist/flatpak/`
- AppImage artifacts output to `dist/appimage/`
- CI release workflow: `.github/workflows/release.yml`

## Translation Notes
- Gettext domain: `com.k0vcz.Artemis`
- Keep `po/POTFILES.in` in sync with real source/UI files
- Do not introduce mixed domains (`artemis-vala` vs `com.k0vcz.Artemis`)

## Engineering Expectations for Future Agents
- Agents are a tool to assist engineering work, not a substitute for engineering judgment.
- Do not "vibe code" features without tracing behavior through code paths.
- Prefer fixes that are testable, minimal, and consistent with existing architecture.
- Surface root causes, not only symptoms.
- Do not silently swallow runtime errors when debugging asynchronous code paths.
- Preserve release quality: buildable, reviewable, and maintainable changes.

## Practical Workflow
1. Reproduce or trace the issue.
2. Identify root cause in current code, not assumptions.
3. Make targeted changes.
4. Compile and verify affected paths.
5. Document what changed and any remaining risk.
