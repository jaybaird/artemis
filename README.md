# Artemis – POTA Logging and Spotting Application

**Artemis** is a desktop application designed for amateur radio operators participating in **Parks On The Air (POTA)**. It helps hunters track QSOs, log parks, fetch spots in real-time, and manage radio connections. Built with **Vala**, **GTK4/Libadwaita**, and **SQLite**, Artemis is cross-platform and lightweight.

## Features

- **Hunt QSOs and Parks**
  - Filter by band, mode, and program. Configure a "hit list," to be notified when a park, state, or callsign is spotted.
  - Track which parks have been hunted or activated.

- **Spot Management**
  - Fetch and display POTA spots in real-time.
  - Show latest QSOs per park.
  - Track spotter and activator comments.

- **Radio Integration**
  - Supports serial, USB, and network-connected radios via Hamlib.

- **Import/Export**
  - Import your already hunted parks from POTA.app
  - Ability to exporting hunter QSOs to QRZ, LoTW, UDP, or local ADIF log.

- **UI**
  - Modern GTK4/Libadwaita interface.

## Installation

### Linux (Flatpak recommended)
```bash
flatpak install flathub com.k0vcz.artemis
flatpak run com.k0vcz.artemis
```

## Build from Source

**Dependencies**
- Vala
- GTK 4
- Libadwaita
- GLib
- Gio
- Gee
- Hamlib
- JSON-GLib
- Dex
- WebKitGtk
- SQLite3

**Build using Meson**
```bash
git clone https://github.com/jaybaird/artemis-vala.git
cd artemis-vala
meson setup build
meson compile -C build
meson install -C build
```

## Usage

1. Configure your callsign, location, and radio settings via Preferences.
2. Import any CSV logbooks you have.
3. View live POTA spots and add QSOs.
4. Track which parks you’ve hunted and your activator activity.
5. Use distance and bearing calculations for planning activations.

** Contributions are welcome! Please submit pull requests or open issues for feature requests and bug reports. **

## License

Artemis is licensed under GPL-3.0-or-later. See LICENSE for details.