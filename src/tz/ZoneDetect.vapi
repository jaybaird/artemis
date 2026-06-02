/* src/tz/ZoneDetect.vapi
 *
 * Vala bindings for ZoneDetect.
 */

[CCode (cheader_filename = "tz/zonedetect.h")]
namespace ZoneDetect {
    [CCode (
        cname = "ZDLookupResult",
        cprefix = "ZD_LOOKUP_",
        has_type_id = false
    )]
    public enum LookupResult {
        IGNORE,
        END,
        PARSE_ERROR,
        NOT_IN_ZONE,
        IN_ZONE,
        IN_EXCLUDED_ZONE,
        ON_BORDER_VERTEX,
        ON_BORDER_SEGMENT
    }

    [CCode (cname = "ZoneDetectResult", has_type_id = false)]
    public struct Result {
        [CCode (cname = "lookupResult")]
        public LookupResult lookup_result;
        [CCode (cname = "polygonId")]
        public uint32 polygon_id;
        [CCode (cname = "metaId")]
        public uint32 meta_id;
        [CCode (cname = "numFields")]
        public uint8 num_fields;
        [CCode (cname = "fieldNames", array_length = false)]
        public unowned string[] field_names;
        [CCode (cname = "data", array_length = false)]
        public unowned string[] data;
    }

    [CCode (
        cname = "ZoneDetect",
        cheader_filename = "tz/zonedetect.h",
        free_function = "ZDCloseDatabase"
    )]
    [Compact]
    public class Database {
        [CCode (cname = "ZDOpenDatabase")]
        public static Database? open (string path);

        [CCode (cname = "ZDOpenDatabaseFromMemory")]
        public static Database? open_from_memory (void* buffer, size_t length);

        [CCode (cname = "ZDLookup")]
        public Result* lookup (float latitude, float longitude, float* safezone = null);

        [CCode (cname = "ZDGetNotice")]
        public unowned string? get_notice ();

        [CCode (cname = "ZDGetTableType")]
        public uint8 get_table_type ();

        [CCode (cname = "ZDPolygonToList")]
        public float* polygon_to_list (uint32 polygon_id, out size_t length);

        [CCode (cname = "ZDHelperSimpleLookupString")]
        public char* simple_lookup_string_raw (float latitude, float longitude);
    }

    [CCode (cname = "ZDFreeResults")]
    public static void free_results (Result* results);

    [CCode (cname = "ZDLookupResultToString")]
    public static unowned string lookup_result_to_string (LookupResult result);

    [CCode (cname = "ZDGetErrorString")]
    public static unowned string get_error_string (int error);

    [CCode (has_target = false)]
    public delegate void ErrorHandler (int zonedetect_error, int native_error);

    [CCode (cname = "ZDSetErrorHandler")]
    public static int set_error_handler (ErrorHandler? handler);

    [CCode (cname = "ZDHelperSimpleLookupStringFree")]
    public static void free_simple_lookup_string (char* str);
}
