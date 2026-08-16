/* src/selection_sync_guard.vala
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

public delegate void SelectionSyncFunc ();

public sealed class SelectionSyncGuard : Object {
    private bool syncing_selection = false;
    private bool suppress_selection_changes = false;
    private uint clear_suppression_idle_id = 0;

    public bool should_ignore_changes {
        get {
            return syncing_selection || suppress_selection_changes;
        }
    }

    public void begin_model_sync () {
        suppress_selection_changes = true;
        cancel_clear_suppression_idle ();
    }

    public void finish_model_sync (SelectionSyncFunc restore_selection) {
        restore_selection ();
        cancel_clear_suppression_idle ();
        clear_suppression_idle_id = Idle.add (() => {
            clear_suppression_idle_id = 0;
            suppress_selection_changes = false;
            return Source.REMOVE;
        });
    }

    public void run_programmatic_sync (SelectionSyncFunc sync) {
        syncing_selection = true;
        sync ();
        syncing_selection = false;
    }

    private void cancel_clear_suppression_idle () {
        if (clear_suppression_idle_id != 0) {
            Source.remove (clear_suppression_idle_id);
            clear_suppression_idle_id = 0;
        }
    }

    ~SelectionSyncGuard () {
        cancel_clear_suppression_idle ();
    }
}
