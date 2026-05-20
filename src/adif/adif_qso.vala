/* src/adif/adif_qso.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Artemis.Adif {
    public static Document document_from_spot_qso (Spot spot) throws Error {
        var station_callsign = (spot.spotter ?? "").strip ();
        var contacted_callsign = (spot.callsign ?? "").strip ();
        var band = (spot.band ?? "").strip ();
        var mode = (spot.mode ?? "").strip ().up ();
        var park_ref = (spot.park_ref ?? "").strip ();

        if (station_callsign == "")
            throw new Error.INVALID_VALUE ("Station callsign is required");
        if (contacted_callsign == "")
            throw new Error.INVALID_VALUE ("Contacted callsign is required");
        if ((band == "") || (band == "All") || (band == "Other"))
            throw new Error.INVALID_VALUE ("A valid amateur band is required");
        if (mode == "")
            throw new Error.INVALID_VALUE ("Mode is required");

        var qso_time = spot.spot_time.to_utc ();
        var document = new Document ();
        var record = new Record ();
        record.set ("STATION_CALLSIGN", station_callsign);
        record.set ("CALL", contacted_callsign);
        record.set ("QSO_DATE", qso_time.format ("%Y%m%d"));
        record.set ("TIME_ON", qso_time.format ("%H%M"));
        record.set ("BAND", band);
        record.set ("MODE", mode);

        if (spot.frequency_khz > 0)
            record.set ("FREQ", format_frequency_mhz_from_khz (spot.frequency_khz));

        if (park_ref != "") {
            record.set ("SIG", "POTA");
            record.set ("SIG_INFO", park_ref);
            record.set ("POTA_REF", park_ref);
            record.set ("NOTES", "POTA - %s".printf (park_ref));
        }

        if ((spot.rst_sent ?? "").strip () != "")
            record.set ("RST_SENT", spot.rst_sent.strip ());
        if ((spot.rst_rcvd ?? "").strip () != "")
            record.set ("RST_RCVD", spot.rst_rcvd.strip ());

        var comment = (spot.spotter_comment ?? "").strip ();
        if (comment != "")
            record.set ("COMMENT", comment);

        document.records.add (record);
        return document;
    }

    public static string spot_qso_to_string (Spot spot) throws Error {
        return Generator.to_string (document_from_spot_qso (spot));
    }
}
