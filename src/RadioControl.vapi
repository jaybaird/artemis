[CCode (cname = "enum RadioMode")]
public enum RadioMode {
    UNKNOWN,
    CW,
    CW_R,
    USB,
    LSB,
    DIGITAL_U,
    DIGITAL_L,
    AM,
    FM,
    DIGITAL_FM
}

[CCode (cname = "RadioConfiguration", has_type_id = false)]
public struct RadioConfiguration {
    public int model_id;
    [CCode (cname = "connection_type")]
    public string? connection_type;
    [CCode (cname = "device_path")]
    public string? device_path;
    [CCode (cname = "network_host")]
    public string? network_host;
    public uint network_port;
    public uint baud_rate;
    public uint data_bits;
    public uint stop_bits;
    public uint handshake;
}

[CCode (cname = "RadioModel", has_type_id = false)]
public struct RadioModel {
    public int model_id;
    public unowned string display_name;
}

[CCode (cname = "RadioControl", cheader_filename="radio_control.h")]
public class RadioControl : GLib.Object {
    // Constructor
    public RadioControl ();

    // Async operations
    [CCode (cname = "radio_control_connect_async")]
    public Dex.Future connect (RadioConfiguration configuration);

    [CCode (cname = "radio_control_disconnect_async")]
    public Dex.Future disconnect ();

    [CCode (cname = "radio_control_get_vfo_async")]
    public Dex.Future get_vfo ();
    [CCode (cname = "radio_control_set_vfo_async")]
    public Dex.Future set_vfo (double frequency);

    [CCode (cname = "radio_control_get_mode_async")]
    public Dex.Future get_mode ();
    [CCode (cname = "radio_control_set_mode_async")]
    public Dex.Future set_mode (RadioMode mode);

    public double frequency { get; }
    public RadioMode mode { get; }

    // Property
    public bool is_rig_connected { get; }

    public static unowned RadioModel[] get_radio_models ();
    [CCode (cname = "radio_control_get_serial_devices")]
    public static unowned string[] get_serial_devices ();

    [CCode (cname = "radio_control_hamlib_version")]
    public static unowned string hamlib_version ();

    [CCode (cname = "radio_control_hamlib_copyright")]
    public static unowned string hamlib_copyright ();

    [CCode (cname = "radio_control_netrigctl_model_id")]
    public static int netrigctl_model_id ();

    // Signals
    [CCode (cname = "radio-connected")]
    public signal void radio_connected ();

    [CCode (cname = "radio-disconnected")]
    public signal void radio_disconnected ();

    [CCode (cname = "radio-status")]
    public signal void radio_status (double frequency, RadioMode mode, bool tx_active);

    [CCode (cname = "radio-error")]
    public signal void radio_error (GLib.Error error);

    // Helpers
    public static RadioMode mode_for_spot (Spot spot) {
        var text_mode = spot.mode.down ();
        if (text_mode == "ft8" || text_mode == "ft4")
            return RadioMode.DIGITAL_U;
        if (text_mode == "ssb")
            return (spot.frequency_khz >= 14000) ? RadioMode.USB : RadioMode.LSB;
        if (text_mode == "fm")
            return RadioMode.FM;
        if (text_mode == "am")
            return RadioMode.AM;
        if (text_mode == "cw")
            return RadioMode.CW;
        return RadioMode.UNKNOWN;
    }

    public void tune_to_spot (Spot spot) {
        if (!is_rig_connected)
            return;

        var mode = RadioControl.mode_for_spot (spot);
        new Dex.Future.finally (set_vfo (spot.frequency_khz), (result) => {
            try {
                result.await_boolean ();
            } catch (GLib.Error e) {
                GLib.warning ("Unable to tune VFO: %s", e.message);
                return null;
            }
            if (mode == RadioMode.UNKNOWN)
                return null;
            new Dex.Future.finally (set_mode (mode), (mode_result) => {
                try {
                    mode_result.await_boolean ();
                } catch (GLib.Error e) {
                    GLib.warning ("Unable to set mode: %s", e.message);
                }
                return null;
            }).disown ();
            return null;
        }).disown ();
    }

    public static unowned string mode_string (RadioMode mode) {
        switch (mode) {
            case AM: return "AM";
            case CW:
            case CW_R:
                return "CW";
            case USB: return "USB";
            case LSB: return "LSB";
            case DIGITAL_L: return "LSB-D";
            case DIGITAL_U: return "USB-D";
            case FM: return "FM";
            case DIGITAL_FM: return "FM-D";
            case UNKNOWN: return "Unknown";
            default: return "Unknown";
        }
    }
}
