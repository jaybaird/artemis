-- v1 SQL
-- October 2025

CREATE TABLE IF NOT EXISTS parks (
  reference TEXT PRIMARY KEY,
  park_name TEXT,
  location TEXT,
  first_qso_date DATETIME,
  qso_count INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS qsos (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  park_ref TEXT NOT NULL,
  callsign TEXT NOT NULL,
  mode TEXT,
  frequency_khz REAL,
  created_utc DATETIME NOT NULL,
  spotter TEXT,
  spotter_comment TEXT,
  activator_comment TEXT,
  local_adif_saved INTEGER NOT NULL DEFAULT 0,
  pota_spotted INTEGER NOT NULL DEFAULT 0,
  qrz_uploaded INTEGER NOT NULL DEFAULT 0,
  local_adif_error TEXT,
  pota_error TEXT,
  qrz_error TEXT,
  FOREIGN KEY(park_ref) REFERENCES parks(reference) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_qsos_park_ref ON qsos(park_ref);
CREATE INDEX IF NOT EXISTS idx_qsos_created  ON qsos(created_utc);

CREATE TRIGGER IF NOT EXISTS trg_qsos_ai
AFTER INSERT ON qsos
FOR EACH ROW BEGIN
  UPDATE parks
    SET qso_count = qso_count + 1,
        first_qso_date = CASE
            WHEN first_qso_date IS NULL THEN NEW.created_utc
            WHEN NEW.created_utc < first_qso_date THEN NEW.created_utc
            ELSE first_qso_date
        END
  WHERE reference = NEW.park_ref;
END;

CREATE TRIGGER IF NOT EXISTS trg_qsos_ad
AFTER DELETE ON qsos
FOR EACH ROW BEGIN
  UPDATE parks
    SET qso_count = CASE WHEN qso_count > 0 THEN qso_count - 1 ELSE 0 END,
        first_qso_date = (SELECT MIN(created_utc) FROM qsos WHERE park_ref = OLD.park_ref)
  WHERE reference = OLD.park_ref;
END;
