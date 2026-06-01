/* src/signal_report_mqtt_session.vala
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

public enum SignalReportStreamState {
    OFFLINE,
    CONNECTING,
    LIVE,
    RECEIVING,
    FAILED,
    STOPPING
}

public class SignalReportMqttSession : Object {
    private const string PSKREPORTER_MQTT_URI = "mqtt://mqtt.pskreporter.info:1883";
    private const string MQTT_CLIENT_ID = "artemis-pskreporter";
    private const uint RECONNECT_INITIAL_DELAY_SECONDS = 2;
    private const uint RECONNECT_MAX_DELAY_SECONDS = 60;

    private HeatmapModel model;
    private Settings settings;
    private PskReporterClient preload_client;
    private PskReporterReportCache preload_cache;
    private MqttClient? client = null;
    private bool _active = false;
    private MqttStatus _mqtt_status = MqttStatus.DISCONNECTED;
    private SignalReportStreamState _stream_state = SignalReportStreamState.OFFLINE;
    private uint _received_count = 0;
    private uint start_serial = 0;
    private uint reconnect_attempt = 0;
    private uint reconnect_timeout_id = 0;

    public signal void state_changed ();

    public bool active {
        get { return _active; }
        private set {
            if (_active == value)
                return;

            _active = value;
            state_changed ();
        }
    }

    public SignalReportStreamState stream_state {
        get { return _stream_state; }
        private set {
            if (_stream_state == value)
                return;

            _stream_state = value;
            state_changed ();
        }
    }

    public uint received_count {
        get { return _received_count; }
        private set {
            if (_received_count == value)
                return;

            _received_count = value;
            state_changed ();
        }
    }

    public MqttStatus mqtt_status {
        get { return _mqtt_status; }
    }

    public SignalReportMqttSession (HeatmapModel model, Settings settings) {
        Object ();
        this.model = model;
        this.settings = settings;
        preload_client = new PskReporterClient ();
        preload_cache = new PskReporterReportCache ();

        settings.changed["callsign"].connect (() => {
            if (active)
                restart ();
        });
    }

    ~SignalReportMqttSession () {
        stop ();
    }

    public void start () {
        if (active)
            return;

        active = true;
        var serial = ++start_serial;
        preload_then_connect.begin (serial, (obj, res) => {
            preload_then_connect.end (res);
        });
    }

    public void stop () {
        active = false;
        set_mqtt_status (MqttStatus.DISCONNECTED);
        start_serial++;
        cancel_reconnect ();
        reconnect_attempt = 0;

        if (client != null) {
            client.shutdown ();
            client = null;
        }
    }

    public void restart () {
        stop ();
        start ();
    }

    private async void preload_then_connect (uint serial) {
        var callsign = settings.get_string ("callsign").strip ().ascii_up ();
        if (callsign == "") {
            warning ("Signal report overlay enabled, but callsign is not configured");
            active = false;
            set_mqtt_status (MqttStatus.DISCONNECTED);
            return;
        }

        if (settings.get_boolean ("signal-report-preload-history"))
            yield preload_reports (callsign);

        if (!active || serial != start_serial)
            return;

        connect_client (callsign);
    }

    private async void preload_reports (string callsign) {
        var cached_reports = preload_cache.get_reports (callsign);
        if (cached_reports != null && cached_reports.size > 0) {
            model.add_reports (cached_reports);
            return;
        }

        try {
            var flow_start_seconds = model.max_age_seconds == 0
                ? -3600
                : - ((int) model.max_age_seconds);
            var fetched_reports = yield preload_client.fetch_reception_reports (
                callsign,
                flow_start_seconds
            );
            if (fetched_reports.size == 0)
                return;

            model.add_reports (fetched_reports);
            preload_cache.store_reports_now (fetched_reports, callsign);
        } catch (Error err) {
            warning ("Unable to preload PSKReporter signal reports: %s", err.message);
        }
    }

    private void connect_client (string callsign) {
        var serial = start_serial;
        cancel_reconnect ();

        client = new MqttClient (normalize_mqtt_uri (PSKREPORTER_MQTT_URI), MQTT_CLIENT_ID);
        client.status_changed.connect ((status) => {
            if (!active || serial != start_serial)
                return;

            set_mqtt_status (status);

            switch (status) {
                case MqttStatus.CONNECTED:
                    subscribe (callsign, serial);
                    break;
                case MqttStatus.SUBSCRIBED:
                    reconnect_attempt = 0;
                    break;
                case MqttStatus.DISCONNECTED:
                case MqttStatus.FAILED:
                    schedule_reconnect (callsign, serial);
                    break;
                default:
                    break;
            }
        });
        client.message_received.connect (on_message_received);
        client.mqtt_error.connect ((code, message) => {
            if (!active || serial != start_serial)
                return;

            warning ("PSKReporter MQTT error %d: %s", code, message);
        });

        try {
            set_mqtt_status (MqttStatus.CONNECTING);
            client.connect ();
        } catch (Error err) {
            warning ("Unable to connect to PSKReporter MQTT: %s", err.message);
            set_mqtt_status (MqttStatus.FAILED);
            client = null;
            schedule_reconnect (callsign, serial);
        }
    }

    private void subscribe (string callsign, uint serial) {
        if (!active || serial != start_serial)
            return;

        if (client == null)
            return;

        var topic = "pskr/filter/v2/+/+/%s/#".printf (callsign);
        try {
            set_mqtt_status (MqttStatus.SUBSCRIBING);
            client.subscribe (topic, 0);
        } catch (Error err) {
            warning ("Unable to subscribe to PSKReporter MQTT topic %s: %s", topic, err.message);
            set_mqtt_status (MqttStatus.FAILED);
            schedule_reconnect (callsign, serial);
        }
    }

    private void schedule_reconnect (string callsign, uint serial) {
        if (!active || serial != start_serial)
            return;

        if (reconnect_timeout_id != 0)
            return;

        if (client != null) {
            client.shutdown ();
            client = null;
        }

        var delay = reconnect_delay_seconds ();
        reconnect_attempt++;
        reconnect_timeout_id = Timeout.add_seconds (delay, () => {
            reconnect_timeout_id = 0;

            if (!active || serial != start_serial)
                return Source.REMOVE;

            connect_client (callsign);
            return Source.REMOVE;
        });
    }

    private void cancel_reconnect () {
        if (reconnect_timeout_id == 0)
            return;

        Source.remove (reconnect_timeout_id);
        reconnect_timeout_id = 0;
    }

    private uint reconnect_delay_seconds () {
        var exponent = uint.min (reconnect_attempt, 5);
        var delay = RECONNECT_INITIAL_DELAY_SECONDS << exponent;
        return uint.min (delay, RECONNECT_MAX_DELAY_SECONDS);
    }

    private void on_message_received (string topic, Bytes payload) {
        try {
            model.add_report (PskReporterDecoder.decode_payload (topic, payload));
            received_count++;
            if (_mqtt_status == MqttStatus.SUBSCRIBED)
                stream_state = SignalReportStreamState.RECEIVING;
        } catch (Error err) {
            warning ("Unable to decode PSKReporter MQTT payload: %s", err.message);
        }
    }

    private void set_mqtt_status (MqttStatus status) {
        if (_mqtt_status == status)
            return;

        _mqtt_status = status;
        state_changed ();
        stream_state = stream_state_for_mqtt_status (status);
    }

    private SignalReportStreamState stream_state_for_mqtt_status (MqttStatus status) {
        switch (status) {
            case MqttStatus.CONNECTING:
            case MqttStatus.SUBSCRIBING:
            case MqttStatus.CONNECTED:
                return SignalReportStreamState.CONNECTING;
            case MqttStatus.SUBSCRIBED:
                return received_count > 0 ?
                    SignalReportStreamState.RECEIVING :
                    SignalReportStreamState.LIVE;
            case MqttStatus.FAILED:
                return SignalReportStreamState.FAILED;
            case MqttStatus.SHUTTING_DOWN:
                return SignalReportStreamState.STOPPING;
            case MqttStatus.DISCONNECTED:
            default:
                return SignalReportStreamState.OFFLINE;
        }
    }

    private static string normalize_mqtt_uri (string uri) {
        if (uri.has_prefix ("mqtt://"))
            return "tcp://%s".printf (uri.substring ("mqtt://".length));

        return uri;
    }
}
