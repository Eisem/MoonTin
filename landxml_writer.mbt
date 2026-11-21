///|
pub suberror TerrainWriteError {
  InvalidTerrainOutput(String)
}

///|
priv struct LandXmlUnits {
  element : String
  linear : String
  area : String
  volume : String
  temperature : String
  pressure : String
}

///|
fn output_units(linear : String) -> LandXmlUnits raise TerrainWriteError {
  match linear {
    "meter" | "millimeter" | "centimeter" | "kilometer" =>
      {
        element: "Metric",
        linear,
        area: "squareMeter",
        volume: "cubicMeter",
        temperature: "celsius",
        pressure: "milliBars",
      }
    "foot" | "USSurveyFoot" | "inch" | "mile" =>
      {
        element: "Imperial",
        linear,
        area: "squareFoot",
        volume: "cubicFeet",
        temperature: "fahrenheit",
        pressure: "inHG",
      }
    _ => raise InvalidTerrainOutput("unsupported linear unit '\{linear}'")
  }
}

///|
priv struct WritableSurface {
  name : String
  points : Array[Point]
  faces : Array[Face]
  output_ids : Map[String, String]
}

///|
fn valid_landxml_id(value : String) -> Bool {
  if value.is_empty() {
    return false
  }
  for ch in value {
    if ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n' {
      return false
    }
  }
  true
}

///|
fn prepare_writable_surface(
  surface : Surface,
  visible_only : Bool,
  renumber_points : Bool,
) -> WritableSurface? raise TerrainWriteError {
  let names : Map[String, Point] = Map([])
  for point in surface.points {
    if !valid_landxml_id(point.id) || names.contains(point.id) {
      raise InvalidTerrainOutput(
        "surface '\{surface.name}': blank, whitespace-delimited or duplicate point ID '\{point.id}'",
      )
    }
    if !point_is_finite(point) {
      raise InvalidTerrainOutput(
        "surface '\{surface.name}': non-finite coordinates for point '\{point.id}'",
      )
    }
    names[point.id] = point
  }
  let used : Map[String, Bool] = Map([])
  let face_keys : Map[(String, String, String), Bool] = Map([])
  let faces = []
  for index, face in surface.faces {
    if visible_only && !face.visible {
      continue
    }
    let (a, b, c) = face.vertices
    guard (names.get(a), names.get(b), names.get(c))
      is (Some(first), Some(second), Some(third)) else {
      raise InvalidTerrainOutput(
        "surface '\{surface.name}': face #\{index + 1} references a missing point",
      )
    }
    let ids = [a, b, c]
    ids.sort()
    let key = (ids[0], ids[1], ids[2])
    let area = projected_area(first, second, third)
    if a == b || b == c || a == c || !finite_sample_value(area) || area <= 0.0 {
      raise InvalidTerrainOutput(
        "surface '\{surface.name}': invalid face #\{index + 1}",
      )
    }
    if face_keys.contains(key) {
      raise InvalidTerrainOutput(
        "surface '\{surface.name}': duplicate face #\{index + 1}",
      )
    }
    face_keys[key] = true
    for id in ids {
      used[id] = true
    }
    faces.push(face)
  }
  if faces.is_empty() {
    return None
  }
  let points = []
  let output_ids = Map([])
  for point in surface.points {
    if visible_only && !used.contains(point.id) {
      continue
    }
    points.push(point)
    output_ids[point.id] = if renumber_points {
      points.length().to_string()
    } else {
      point.id
    }
  }
  Some({ name: surface.name, points, faces, output_ids, })
}

///|
fn write_landxml_units(
  writer : @xml.Writer,
  units : LandXmlUnits,
) -> Unit raise {
  writer.start_element("Units", [])
  writer.empty_element(units.element, [
    ("linearUnit", units.linear),
    ("areaUnit", units.area),
    ("volumeUnit", units.volume),
    ("temperatureUnit", units.temperature),
    ("pressureUnit", units.pressure),
  ])
  writer.end_element("Units")
}

///|
fn write_landxml_surface(
  writer : @xml.Writer,
  surface : WritableSurface,
) -> Unit raise {
  writer.start_element("Surface", [("name", surface.name)])
  writer.start_element("Definition", [("surfType", "TIN")])
  writer.start_element("Pnts", [])
  for point in surface.points {
    writer.start_element("P", [("id", surface.output_ids[point.id])])
    writer.text("\{point.northing} \{point.easting} \{point.elevation}")
    writer.end_element("P")
  }
  writer.end_element("Pnts")
  writer.start_element("Faces", [])
  for face in surface.faces {
    let attributes = if face.visible { [] } else { [("i", "1")] }
    let (a, b, c) = face.vertices
    writer.start_element("F", attributes)
    writer.text(
      "\{surface.output_ids[a]} \{surface.output_ids[b]} \{surface.output_ids[c]}",
    )
    writer.end_element("F")
  }
  writer.end_element("Faces")
  writer.end_element("Definition")
  writer.end_element("Surface")
}

///|
/// Writes the supported TIN subset of LandXML.
/// Visible-only output removes hidden faces and points no remaining face references.
pub fn write_landxml(
  terrain : Terrain,
  surface_name? : String,
  visible_only? : Bool = false,
  renumber_points? : Bool = false,
  metadata? : LandXmlMetadata,
) -> String raise {
  let units = match terrain.linear_unit {
    Some(unit) => Some(output_units(unit))
    None => None
  }
  let surfaces = []
  for surface in terrain.surfaces {
    if surface_name is Some(name) && name != surface.name {
      continue
    }
    match prepare_writable_surface(surface, visible_only, renumber_points) {
      Some(output) => surfaces.push(output)
      None =>
        if !visible_only {
          raise InvalidTerrainOutput(
            "surface '\{surface.name}' contains no faces",
          )
        }
    }
  }
  if surfaces.is_empty() {
    raise InvalidTerrainOutput("no matching TIN surfaces with exportable faces")
  }
  let writer = @xml.Writer::new()
  let attributes = [("xmlns", LANDXML_NAMESPACE), ("version", "1.2")]
  if metadata is Some(data) {
    add_landxml_timestamp(attributes, data)
  }
  writer.start_element("LandXML", attributes)
  if units is Some(spec) {
    write_landxml_units(writer, spec)
  }
  if metadata is Some(data) {
    write_landxml_project(writer, data)
  }
  writer.start_element("Surfaces", [])
  for surface in surfaces {
    write_landxml_surface(writer, surface)
  }
  writer.end_element("Surfaces")
  writer.end_element("LandXML")
  "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" + writer.to_string() + "\n"
}
