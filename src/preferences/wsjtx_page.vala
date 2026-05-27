/* src/preferences/wsjtx_page.vala
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

[GtkTemplate (ui = "/com/k0vcz/artemis/ui/preferences/wsjtx_page.ui")]
public sealed class WsjtxPreferencesPage : Adw.PreferencesPage {
    [GtkChild]
    private unowned Adw.SwitchRow wsjtx_active;

    [GtkChild]
    private unowned Adw.PreferencesGroup wsjtx_status_group;

    [GtkChild]
    private unowned Adw.EntryRow row_wsjtx_listen_ip;

    [GtkChild]
    private unowned Adw.EntryRow row_wsjtx_listen_port;

    [GtkChild]
    private unowned Adw.ActionRow wsjtx_status_row;

    [GtkChild]
    private unowned Gtk.Image wsjtx_status_icon;

    [GtkChild]
    private unowned Gtk.Label wsjtx_status_label;

    public WsjtxPreferencesPage () {
        Object ();
    }

    public void setup () {
        Application.settings.bind ("enable-wsjtx-integration", wsjtx_active, "active",
            SettingsBindFlags.DEFAULT);
        wsjtx_active.notify["active"].connect (update_controls_sensitivity);
        update_controls_sensitivity ();
        Application.settings.bind ("wsjtx-listen-ip", row_wsjtx_listen_ip, "text",
            SettingsBindFlags.DEFAULT);
        bind_wsjtx_port_entry ();
        Application.wsjtx_session.status_changed.connect (update_wsjtx_status);
        update_wsjtx_status ();
    }

    private void update_controls_sensitivity () {
        row_wsjtx_listen_ip.sensitive = wsjtx_active.active;
        row_wsjtx_listen_port.sensitive = wsjtx_active.active;
        wsjtx_status_group.sensitive = wsjtx_active.active;
    }

    private void bind_wsjtx_port_entry () {
        sync_wsjtx_port_entry ();

        row_wsjtx_listen_port.changed.connect (() => {
            int parsed_port;
            if (!try_parse_port (row_wsjtx_listen_port.text, out parsed_port))
                return;

            if (Application.settings.get_int ("wsjtx-listen-port") != parsed_port)
                Application.settings.set_int ("wsjtx-listen-port", parsed_port);
        });

        Application.settings.changed["wsjtx-listen-port"].connect (() => {
            sync_wsjtx_port_entry ();
        });
    }

    private void sync_wsjtx_port_entry () {
        var current_port = Application.settings.get_int ("wsjtx-listen-port").to_string ();
        if (row_wsjtx_listen_port.text != current_port)
            row_wsjtx_listen_port.text = current_port;
    }

    private void update_wsjtx_status () {
        if (Application.wsjtx_session == null)
            return;

        wsjtx_status_row.subtitle = Application.wsjtx_session.status_subtitle;
        wsjtx_status_label.label = Application.wsjtx_session.status_label;

        if (Application.wsjtx_session.connected)
            wsjtx_status_icon.icon_name = "network-idle-symbolic";
        else if (Application.wsjtx_session.listening)
            wsjtx_status_icon.icon_name = "network-workgroup-symbolic";
        else
            wsjtx_status_icon.icon_name = "network-offline-symbolic";
    }
}
