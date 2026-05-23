/* src/preferences.vala
 *
 * Copyright 2026 Jay Baird (K0VCZ)
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

[GtkTemplate (ui = "/com/k0vcz/artemis/ui/preferences.ui")]
public sealed class PreferencesDialog : Adw.PreferencesDialog {
    [GtkChild] private unowned GeneralPreferencesPage general_page;
    [GtkChild] private unowned RadioPreferencesPage radio_page;
    [GtkChild] private unowned LoggingPreferencesPage logging_page;
    [GtkChild] private unowned WsjtxPreferencesPage wsjtx_page;

    public PreferencesDialog () {
        Object ();
    }

    construct {
        general_page.setup ();
        radio_page.setup ();
        logging_page.setup ();
        wsjtx_page.setup ();
    }
}
