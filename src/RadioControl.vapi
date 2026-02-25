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
    public int network_port;
    public int baud_rate;
}

[CCode (cname = "RadioModel", has_type_id = false)]
public struct RadioModel {
    public int model_id;
    public unowned string display_name;
}

[CCode (cname = "RadioControl", cheader_filename="../src/radio_control.h")]
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
    public Dex.Future set_vfo (int frequency);

    [CCode (cname = "radio_control_get_mode_async")]
    public Dex.Future get_mode ();
    [CCode (cname = "radio_control_set_mode_async")]
    public Dex.Future set_mode (RadioMode mode);

    public float frequency { get; }
    public RadioMode mode { get; }

    // Property
    public bool is_rig_connected { get; }

    public static unowned RadioModel[] get_radio_models ();

    [CCode (cname = "radio_control_hamlib_version")]
    public static unowned string hamlib_version ();

    [CCode (cname = "radio_control_hamlib_copyright")]
    public static unowned string hamlib_copyright ();

    // Signals
    [CCode (cname = "radio-connected")]
    public signal void radio_connected ();
    
    [CCode (cname = "radio-disconnected")]
    public signal void radio_disconnected ();
    
    [CCode (cname = "radio-status")]
    public signal void radio_status (int frequency, RadioMode mode);
    
    [CCode (cname = "radio-error")]
    public signal void radio_error (GLib.Error error);

    // Helpers
    public static string mode_string (RadioMode mode) {
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
