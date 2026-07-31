/* src/radio_status_model.vala
 *
 * Copyright 2026 Jay Baird (K0VCZ)
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

public struct RadioStatusSnapshot {
    public bool connected;
    public double frequency_khz;
    public string mode;
    public bool tx_active;
    public bool rx_active;

    public static RadioStatusSnapshot disconnected () {
        RadioStatusSnapshot snapshot = RadioStatusSnapshot ();
        snapshot.connected = false;
        snapshot.frequency_khz = -1.0;
        snapshot.mode = "Unknown";
        snapshot.tx_active = false;
        snapshot.rx_active = false;
        return snapshot;
    }

    public static RadioStatusSnapshot connected_status (
        double frequency_khz,
        string mode,
        bool tx_active
    ) {
        RadioStatusSnapshot snapshot = RadioStatusSnapshot ();
        snapshot.connected = true;
        snapshot.frequency_khz = frequency_khz;
        snapshot.mode = normalize_mode (mode);
        snapshot.tx_active = tx_active;
        snapshot.rx_active = !tx_active;
        return snapshot;
    }

    public bool equal (RadioStatusSnapshot other) {
        return connected == other.connected &&
            frequency_khz == other.frequency_khz &&
            mode == other.mode &&
            tx_active == other.tx_active &&
            rx_active == other.rx_active;
    }

    private static string normalize_mode (string mode) {
        var normalized = mode.strip ();
        return normalized == "" ? "Unknown" : normalized;
    }
}

public sealed class RadioStatusModel : Object {
    private RadioStatusSnapshot current_snapshot;

    public bool connected {
        get { return current_snapshot.connected; }
    }

    public double frequency_khz {
        get { return current_snapshot.frequency_khz; }
    }

    public string mode {
        owned get { return current_snapshot.mode; }
    }

    public bool tx_active {
        get { return current_snapshot.tx_active; }
    }

    public bool rx_active {
        get { return current_snapshot.rx_active; }
    }

    public RadioStatusModel () {
        current_snapshot = RadioStatusSnapshot.disconnected ();
    }

    public RadioStatusSnapshot get_snapshot () {
        return current_snapshot;
    }

    public bool update (RadioStatusSnapshot next, out RadioStatusSnapshot previous) {
        previous = current_snapshot;
        if (current_snapshot.equal (next))
            return false;

        current_snapshot = next;
        return true;
    }

    public bool update_disconnected (out RadioStatusSnapshot previous) {
        return update (RadioStatusSnapshot.disconnected (), out previous);
    }

    public bool update_connected_status (
        double frequency_khz,
        string mode,
        bool tx_active,
        out RadioStatusSnapshot previous
    ) {
        return update (
            RadioStatusSnapshot.connected_status (frequency_khz, mode, tx_active),
            out previous
        );
    }
}
