/* tests/test-wsjtx-packet.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using Artemis.Wsjtx;

private uint8[] append_trailing_bytes (uint8[] datagram, uint8[] trailing) {
    uint8[] combined = new uint8[datagram.length + trailing.length];
    for (int i = 0; i < datagram.length; i++)
        combined[i] = datagram[i];
    for (int i = 0; i < trailing.length; i++)
        combined[datagram.length + i] = trailing[i];
    return combined;
}

private void assert_packet_error (uint8[] datagram, int expected) {
    var parser = new PacketParser ();

    try {
        parser.parse (datagram);
        assert_not_reached ();
    } catch (PacketError err) {
        switch (expected) {
            case PacketError.BAD_MAGIC:
                assert (err is PacketError.BAD_MAGIC);
                break;
            case PacketError.UNSUPPORTED_SCHEMA:
                assert (err is PacketError.UNSUPPORTED_SCHEMA);
                break;
            case PacketError.MALFORMED_PACKET:
                assert (err is PacketError.MALFORMED_PACKET);
                break;
            case PacketError.INVALID_UTF8:
                assert (err is PacketError.INVALID_UTF8);
                break;
            case PacketError.UNKNOWN_TYPE:
                assert (err is PacketError.UNKNOWN_TYPE);
                break;
        }
    } catch (Error err) {
        assert_not_reached ();
    }
}

private void test_bad_magic_rejected () {
    var datagram = PacketWriter.build_heartbeat ("Artemis", "2.7.0", "r1");
    datagram[0] = 0x00;
    assert_packet_error (datagram, (int) PacketError.BAD_MAGIC);
}

private void test_unsupported_schema_rejected () {
    var datagram = PacketWriter.build_heartbeat ("Artemis", "2.7.0", "r1");
    datagram[7] = 0x04;
    assert_packet_error (datagram, (int) PacketError.UNSUPPORTED_SCHEMA);
}

private void test_heartbeat_parse () {
    var parser = new PacketParser ();
    var datagram = PacketWriter.build_heartbeat ("WSJT-X", "2.7.0", "devel");
    var packet = parser.parse (datagram);

    assert (packet.type == MessageType.HEARTBEAT);
    var heartbeat = packet.get_heartbeat ();
    assert (heartbeat.header.id == "WSJT-X");
    assert (heartbeat.max_schema == MAX_SCHEMA);
    assert (heartbeat.version == "2.7.0");
    assert (heartbeat.revision == "devel");
}

private void test_decode_parse () {
    var writer = new PacketWriter ();
    writer.write_header (MessageType.DECODE, "WSJT-X");
    writer.write_bool (true);
    WsjtxTime time = {};
    time.msecs_since_midnight = 45296000;
    writer.write_qtime (time);
    writer.write_i32 (-12);
    writer.write_double (0.3);
    writer.write_u32 (1450);
    writer.write_utf8 ("FT8");
    writer.write_utf8 ("CQ TEST K1ABC FN31");
    writer.write_bool (false);
    writer.write_bool (false);

    var parser = new PacketParser ();
    var packet = parser.parse (writer.finish ());

    assert (packet.type == MessageType.DECODE);
    var decode = packet.get_decode ();
    assert (decode.is_new);
    assert (decode.time.hour == 12);
    assert (decode.time.minute == 34);
    assert (decode.time.second == 56);
    assert (decode.snr == -12);
    assert (Math.fabs (decode.delta_time - 0.3) < 0.0001);
    assert (decode.delta_frequency_hz == 1450);
    assert (decode.mode == "FT8");
    assert (decode.text == "CQ TEST K1ABC FN31");
    assert (!decode.low_confidence);
    assert (!decode.off_air);
}

private void test_status_parse () {
    var writer = new PacketWriter ();
    writer.write_header (MessageType.STATUS, "WSJT-X");
    writer.write_u64 (14074000);
    writer.write_utf8 ("FT8");
    writer.write_utf8 ("K1ABC");
    writer.write_utf8 ("-10");
    writer.write_utf8 ("FT8");
    writer.write_bool (true);
    writer.write_bool (false);
    writer.write_bool (true);
    writer.write_u32 (1500);
    writer.write_u32 (1700);
    writer.write_utf8 ("N0CALL");
    writer.write_utf8 ("FN31");
    writer.write_utf8 ("EM10");
    writer.write_bool (false);
    writer.write_utf8 ("");
    writer.write_bool (false);
    writer.write_u8 (0);
    writer.write_u32 (400);
    writer.write_u32 (15);
    writer.write_utf8 ("Default");
    writer.write_utf8 ("CQ K1ABC FN31");

    var parser = new PacketParser ();
    var packet = parser.parse (writer.finish ());

    assert (packet.type == MessageType.STATUS);
    var status = packet.get_status ();
    assert (status.dial_frequency_hz == 14074000);
    assert (status.mode == "FT8");
    assert (status.dx_call == "K1ABC");
    assert (status.report == "-10");
    assert (status.tx_enabled);
    assert (!status.transmitting);
    assert (status.decoding);
    assert (status.rx_df == 1500);
    assert (status.tx_df == 1700);
    assert (status.configuration_name == "Default");
}

private void test_utf8_string_parsing () {
    var parser = new PacketParser ();
    var datagram = PacketWriter.build_heartbeat (
        "WSJT-\u00d8",
        "2.7.\u010c",
        "rev-\u00f1"
    );
    var packet = parser.parse (datagram);
    var heartbeat = packet.get_heartbeat ();

    assert (heartbeat.header.id == "WSJT-\u00d8");
    assert (heartbeat.version == "2.7.\u010c");
    assert (heartbeat.revision == "rev-\u00f1");
}

private void test_unknown_packet_does_not_crash () {
    var writer = new PacketWriter ();
    writer.write_u32 (MAGIC);
    writer.write_u32 (MAX_SCHEMA);
    writer.write_u32 (99);
    writer.write_utf8 ("WSJT-X");
    writer.write_u8 (0xaa);
    writer.write_u8 (0xbb);

    var parser = new PacketParser ();
    var packet = parser.parse (writer.finish ());

    assert (packet.is_unknown);
    var unknown = packet.get_unknown ();
    assert (unknown.raw_type == 99);
    assert (unknown.payload.length == 2);
    assert (unknown.payload[0] == 0xaa);
    assert (unknown.payload[1] == 0xbb);
}

private void test_trailing_bytes_tolerated () {
    var parser = new PacketParser ();
    var datagram = PacketWriter.build_heartbeat ("WSJT-X", "2.7.0", "devel");
    var combined = append_trailing_bytes (datagram, { 0xde, 0xad, 0xbe, 0xef });
    var packet = parser.parse (combined);

    assert (packet.type == MessageType.HEARTBEAT);
    assert (packet.get_heartbeat ().version == "2.7.0");
}

public static int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/wsjtx/bad-magic", test_bad_magic_rejected);
    Test.add_func ("/wsjtx/unsupported-schema", test_unsupported_schema_rejected);
    Test.add_func ("/wsjtx/heartbeat", test_heartbeat_parse);
    Test.add_func ("/wsjtx/decode", test_decode_parse);
    Test.add_func ("/wsjtx/status", test_status_parse);
    Test.add_func ("/wsjtx/utf8", test_utf8_string_parsing);
    Test.add_func ("/wsjtx/unknown", test_unknown_packet_does_not_crash);
    Test.add_func ("/wsjtx/trailing-bytes", test_trailing_bytes_tolerated);

    return Test.run ();
}
