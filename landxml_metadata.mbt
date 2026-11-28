///|
/// Metadata supplied by the caller for a normalized TIN document.
/// Dates use YYYY-MM-DD and times use HH:MM:SS.
pub(all) struct LandXmlMetadata {
  date : String?
  time : String?
  project : String?
  description : String?
}

///|
fn parse_timestamp_part(text : StringView, width : Int32) -> Int32? {
  if text.length() != width {
    return None
  }
  let mut value = 0
  for ch in text {
    if !ch.is_ascii_digit() {
      return None
    }
    value = value * 10 + ch.to_int() - '0'.to_int()
  }
  Some(value)
}

///|
fn legal_landxml_date(date : String) -> Bool {
  guard date.split("-").collect() is [year, month, day] else { return false }
  guard (
      parse_timestamp_part(year, 4),
      parse_timestamp_part(month, 2),
      parse_timestamp_part(day, 2),
    )
    is (Some(y), Some(m), Some(d)) else {
    return false
  }
  if y == 0 || m < 1 || m > 12 || d < 1 {
    return false
  }
  let leap = y % 400 == 0 || (y % 4 == 0 && y % 100 != 0)
  let days = match m {
    2 => if leap { 29 } else { 28 }
    4 | 6 | 9 | 11 => 30
    _ => 31
  }
  d <= days
}

///|
fn legal_landxml_time(time : String) -> Bool {
  guard time.split(":").collect() is [hour, minute, second] else {
    return false
  }
  guard (
      parse_timestamp_part(hour, 2),
      parse_timestamp_part(minute, 2),
      parse_timestamp_part(second, 2),
    )
    is (Some(h), Some(m), Some(s)) else {
    return false
  }
  h < 24 && m < 60 && s < 60
}

///|
fn add_landxml_timestamp(
  attributes : Array[(String, String)],
  metadata : LandXmlMetadata,
) -> Unit raise TerrainWriteError {
  match (metadata.date, metadata.time) {
    (None, None) => ()
    (Some(date), Some(time)) => {
      if !legal_landxml_date(date) || !legal_landxml_time(time) {
        raise InvalidTerrainOutput(
          "timestamp requires a valid YYYY-MM-DD date and HH:MM:SS time",
        )
      }
      attributes.push(("date", date))
      attributes.push(("time", time))
    }
    _ =>
      raise InvalidTerrainOutput(
        "both date and time are required for a LandXML timestamp",
      )
  }
}

///|
fn write_landxml_project(
  writer : @xml.Writer,
  metadata : LandXmlMetadata,
) -> Unit raise {
  match metadata.project {
    Some(name) => {
      if name.trim().is_empty() {
        raise InvalidTerrainOutput("project name must not be blank")
      }
      let attributes = [("name", name)]
      if metadata.description is Some(description) {
        attributes.push(("desc", description))
      }
      writer.empty_element("Project", attributes)
    }
    None =>
      if metadata.description is Some(_) {
        raise InvalidTerrainOutput(
          "a project description requires a project name",
        )
      }
  }
}
