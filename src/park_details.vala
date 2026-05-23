/* src/park_details.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

public struct PotaParkDetails {
    public string reference;
    public string name;
    public string location_desc;
}

public interface ParkDetailsProvider : Object {
    public abstract async PotaParkDetails fetch_park_details (string park_ref) throws Error;
}
