/* src/space_weather_service.vala
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

public sealed class SpaceWeatherService : Object {
    private const uint REFRESH_INTERVAL_SECONDS = 30 * 60;

    private SpaceWeatherClient client;
    private Cancellable? cancellable = null;
    private uint refresh_timeout_id = 0;
    private bool started = false;

    public signal void changed ();

    public bool loading { get; private set; default = false; }
    public SpaceWeatherSnapshot? snapshot { get; private set; default = null; }

    public SpaceWeatherService (SpaceWeatherClient? client = null) {
        Object ();
        this.client = client ?? new SpaceWeatherClient ();
    }

    public void start () {
        if (started)
            return;

        started = true;
        refresh.begin ();
        schedule_refresh ();
    }

    public bool has_snapshot () {
        return snapshot != null;
    }

    public void refresh_now () {
        refresh.begin ();
    }

    private void schedule_refresh () {
        cancel_refresh_timer ();
        refresh_timeout_id = Timeout.add_seconds (REFRESH_INTERVAL_SECONDS, () => {
            refresh_timeout_id = 0;
            refresh.begin ();
            schedule_refresh ();
            return Source.REMOVE;
        });
    }

    private void cancel_refresh_timer () {
        if (refresh_timeout_id != 0) {
            Source.remove (refresh_timeout_id);
            refresh_timeout_id = 0;
        }
    }

    private async void refresh () {
        if (loading)
            return;

        loading = true;
        changed ();

        if (cancellable != null)
            cancellable.cancel ();
        cancellable = new Cancellable ();

        var next_snapshot = yield client.fetch_snapshot (cancellable);
        if (next_snapshot.has_any_value ()) {
            snapshot = next_snapshot.copy ();
            message (
                "Space weather updated: %s | %s".printf (
                    snapshot.primary_text (),
                    snapshot.secondary_text ()
                )
            );
        } else {
            message ("Space weather refresh completed with no usable values");
        }

        loading = false;
        changed ();
    }

    ~SpaceWeatherService () {
        cancel_refresh_timer ();

        if (cancellable != null) {
            cancellable.cancel ();
            cancellable = null;
        }
    }
}
