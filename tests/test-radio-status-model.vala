/* tests/test-radio-status-model.vala
 *
 * Copyright 2026 Jay Baird (K0VCZ)
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

private void test_disconnected_defaults () {
    var snapshot = RadioStatusSnapshot.disconnected ();

    assert (!snapshot.connected);
    assert (snapshot.frequency_khz == -1.0);
    assert (snapshot.mode == "Unknown");
    assert (!snapshot.tx_active);
    assert (!snapshot.rx_active);
}

private void test_connected_status_sets_rx_when_not_transmitting () {
    var snapshot = RadioStatusSnapshot.connected_status (14074.0, "USB-D", false);

    assert (snapshot.connected);
    assert (snapshot.frequency_khz == 14074.0);
    assert (snapshot.mode == "USB-D");
    assert (!snapshot.tx_active);
    assert (snapshot.rx_active);
}

private void test_connected_status_sets_tx_without_rx () {
    var snapshot = RadioStatusSnapshot.connected_status (14074.0, "USB-D", true);

    assert (snapshot.connected);
    assert (snapshot.tx_active);
    assert (!snapshot.rx_active);
}

private void test_blank_mode_normalizes_to_unknown () {
    var snapshot = RadioStatusSnapshot.connected_status (7100.0, "  ", false);

    assert (snapshot.mode == "Unknown");
}

private void test_model_suppresses_duplicate_updates () {
    var model = new RadioStatusModel ();
    RadioStatusSnapshot previous;

    assert (model.update_connected_status (14074.0, "USB-D", false, out previous));
    assert (!previous.connected);
    assert (model.connected);
    assert (model.rx_active);

    assert (!model.update_connected_status (14074.0, "USB-D", false, out previous));

    assert (model.update_connected_status (14074.0, "USB-D", true, out previous));
    assert (!previous.tx_active);
    assert (model.tx_active);
    assert (!model.rx_active);

    assert (model.update_disconnected (out previous));
    assert (previous.connected);
    assert (!model.connected);
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/radio-status-model/disconnected-defaults",
        test_disconnected_defaults);
    Test.add_func ("/radio-status-model/connected-rx",
        test_connected_status_sets_rx_when_not_transmitting);
    Test.add_func ("/radio-status-model/connected-tx",
        test_connected_status_sets_tx_without_rx);
    Test.add_func ("/radio-status-model/blank-mode",
        test_blank_mode_normalizes_to_unknown);
    Test.add_func ("/radio-status-model/duplicate-suppression",
        test_model_suppresses_duplicate_updates);

    return Test.run ();
}
