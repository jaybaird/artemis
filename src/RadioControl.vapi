[CCode (cname = "enum RadioMode")]
public enum RadioMode {
    UNKNOWN,
    AM,
    CW,
    CW_R,
    USB,
    LSB,
    DIGITAL_L,
    DIGITAL_U,
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

    // Property
    public bool is_rig_connected { get; }

    public static unowned RadioModel[] get_radio_models ();

    // Signals
    [CCode (cname = "radio-connected")]
    public signal void radio_connected ();
    
    [CCode (cname = "radio-disconnected")]
    public signal void radio_disconnected ();
    
    [CCode (cname = "radio-status")]
    public signal void radio_status (int frequency, RadioMode mode);
    
    [CCode (cname = "radio-error")]
    public signal void radio_error (GLib.Error error);
}
