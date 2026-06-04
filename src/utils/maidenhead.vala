/* src/utils/maidenhead.vala
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

using Shumate;

public errordomain MaidenheadLocatorError {
    INVALID_LENGTH,
    INVALID_CHARACTER
}

namespace Maidenhead {
    public string normalize (string grid) throws Error {
        var normalized = grid.strip ().ascii_up ();

        if (normalized.length != 4 &&
            normalized.length != 6 &&
            normalized.length != 8 &&
            normalized.length != 10) {
            throw new MaidenheadLocatorError.INVALID_LENGTH (
                "Grid locator %s must be 4, 6, 8, or 10 characters".printf (grid)
            );
        }

        validate_pair (normalized, 0, 'A', 'R');
        validate_pair (normalized, 2, '0', '9');

        if (normalized.length >= 6)
            validate_pair (normalized, 4, 'A', 'X');

        if (normalized.length >= 8)
            validate_pair (normalized, 6, '0', '9');

        if (normalized.length >= 10)
            validate_pair (normalized, 8, 'A', 'X');

        return normalized;
    }

    public bool is_valid (string grid) {
        try {
            normalize (grid);
            return true;
        } catch (Error err) {
            return false;
        }
    }

    public Coordinate center (string grid) throws Error {
        var loc = normalize (grid);

        double lon = -180.0;
        double lat = -90.0;
        double lon_width = 20.0;
        double lat_width = 10.0;

        lon += (loc[0] - 'A') * lon_width;
        lat += (loc[1] - 'A') * lat_width;

        lon_width = 2.0;
        lat_width = 1.0;
        lon += (loc[2] - '0') * lon_width;
        lat += (loc[3] - '0') * lat_width;

        if (loc.length >= 6) {
            lon_width /= 24.0;
            lat_width /= 24.0;
            lon += (loc[4] - 'A') * lon_width;
            lat += (loc[5] - 'A') * lat_width;
        }

        if (loc.length >= 8) {
            lon_width /= 10.0;
            lat_width /= 10.0;
            lon += (loc[6] - '0') * lon_width;
            lat += (loc[7] - '0') * lat_width;
        }

        if (loc.length >= 10) {
            lon_width /= 24.0;
            lat_width /= 24.0;
            lon += (loc[8] - 'A') * lon_width;
            lat += (loc[9] - 'A') * lat_width;
        }

        return new Coordinate.full (lat + (lat_width * 0.5), lon + (lon_width * 0.5));
    }

    private void validate_pair (string grid, int offset, char min_char, char max_char) throws Error {
        for (var i = offset; i < offset + 2; i++) {
            if (grid[i] < min_char || grid[i] > max_char) {
                throw new MaidenheadLocatorError.INVALID_CHARACTER (
                    "Invalid Maidenhead character %c in %s".printf (grid[i], grid)
                );
            }
        }
    }
}
