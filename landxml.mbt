///|
pub suberror LandXmlError {
  InvalidLandXml(String)
}

///|
priv struct XmlNode {
  name : String
  location : SourceLocation
  attributes : Map[String, String]
  children : Array[XmlNode]
  text : StringBuilder
}

///|
const LANDXML_NAMESPACE = "http://www.landxml.org/schema/LandXML-1.2"

///|
fn xml_node(
  element : @xml.NamespaceElement,
  start : @xml.SourcePosition,
) -> XmlNode {
  let attributes = Map([])
  for attribute in element.attributes {
    if attribute.name.namespace_uri is None {
      attributes[attribute.name.local_name] = attribute.value
    }
  }
  {
    name: if element.name.namespace_uri == Some(LANDXML_NAMESPACE) {
      element.name.local_name
    } else {
      ""
    },
    location: { line: start.line, column: start.column, },
    attributes,
    children: [],
    text: StringBuilder(),
  }
}

///|
fn read_xml(source : String, max_records : Int) -> XmlNode raise {
  if source.contains("<!DOCTYPE") {
    raise InvalidLandXml("DOCTYPE declarations are unsupported")
  }
  let reader = @xml.NamespaceReader::from_string(source)
  let stack : Array[XmlNode] = []
  let mut root = None
  let mut records = 0
  let count_record = fn(element : @xml.NamespaceElement) raise {
    let name = element.name
    if name.namespace_uri == Some(LANDXML_NAMESPACE) &&
      (name.local_name == "P" || name.local_name == "F") {
      records += 1
      if records > max_records {
        raise InvalidLandXml(
          "LandXML point and face record limit exceeded (\{max_records})",
        )
      }
    }
  }
  for count = 0; ; count = count + 1 {
    if count >= 5000000 || stack.length() >= 128 {
      raise InvalidLandXml("XML event or nesting limit exceeded")
    }
    let event = reader.read_event()
    match event.kind {
      Start(element) => {
        count_record(element)
        stack.push(xml_node(element, event.span.start))
      }
      Empty(element) => {
        count_record(element)
        let node = xml_node(element, event.span.start)
        match stack.last() {
          Some(parent) => parent.children.push(node)
          None => root = Some(node)
        }
      }
      End(_) => {
        guard stack.pop() is Some(node) else {
          raise InvalidLandXml("unexpected closing tag")
        }
        match stack.last() {
          Some(parent) => parent.children.push(node)
          None => root = Some(node)
        }
      }
      Text(value) | CData(value) =>
        if stack.last() is Some(node) && (node.name == "P" || node.name == "F") {
          node.text.write_string(value)
        }
      Eof => break
      _ => ()
    }
  }
  guard root is Some(node) else {
    raise InvalidLandXml("missing document root")
  }
  node
}

///|
fn children(node : XmlNode, name : String) -> Array[XmlNode] {
  node.children.filter(fn(child) { child.name == name })
}

///|
fn tokens(text : String) -> Array[String] {
  let result = []
  let word = StringBuilder()
  let mut in_word = false
  for ch in text {
    match ch {
      ' ' | '\n' | '\r' | '\t' =>
        if in_word {
          result.push(word.to_string())
          word.reset()
          in_word = false
        }
      _ => {
        word.write_char(ch)
        in_word = true
      }
    }
  }
  if in_word {
    result.push(word.to_string())
  }
  result
}

///|
fn decode_point(node : XmlNode, surface : String, number : Int) -> Point raise {
  let location = "surface \{surface}, point #\{number}"
  if node.attributes.contains("pntRef") {
    raise InvalidLandXml(
      "\{location}: external point references are unsupported",
    )
  }
  guard node.children.is_empty() else {
    raise InvalidLandXml("\{location}: unexpected XML inside point record")
  }
  guard node.attributes.get("id") is Some(id) && !id.is_empty() else {
    raise InvalidLandXml("\{location}: missing point ID")
  }
  guard tokens(node.text.to_string()) is [north, east, elevation] else {
    raise InvalidLandXml(
      "\{location}: expected northing, easting and elevation",
    )
  }
  {
    id,
    northing: @string.parse_double(north[:]),
    easting: @string.parse_double(east[:]),
    elevation: @string.parse_double(elevation[:]),
  } catch {
    _ => raise InvalidLandXml("\{location}: invalid coordinate")
  }
}

///|
fn decode_face(node : XmlNode, surface : String, number : Int) -> Face raise {
  let location = "surface \{surface}, face #\{number}"
  guard node.children.is_empty() else {
    raise InvalidLandXml("\{location}: unexpected XML inside face record")
  }
  guard tokens(node.text.to_string()) is [a, b, c] else {
    raise InvalidLandXml("\{location}: expected three point IDs")
  }
  let visible = match node.attributes.get("i") {
    None | Some("0") => true
    Some("1") => false
    Some(value) =>
      raise InvalidLandXml("\{location}: invalid invisibility flag \{value}")
  }
  { vertices: (a, b, c), visible, }
}

///|
pub(all) struct RecordIssue {
  surface_number : Int
  surface_name : String
  code : String
  record_kind : String
  record_number : Int
  message : String
  severity : Severity
  location : SourceLocation
}

///|
pub struct ParsedTerrain {
  terrain : Terrain
  issues : Array[RecordIssue]
  face_numbers : Array[Array[Int]]
}

///|
pub fn parse(source : String) -> Terrain raise {
  let parsed = parse_records(source)
  for issue in parsed.issues {
    if issue.severity is Error {
      raise InvalidLandXml(issue.message)
    }
  }
  parsed.terrain
}

///|
pub fn parse_records(source : String) -> ParsedTerrain raise {
  let issues = []
  let (terrain, face_numbers, _, _) = decode_records(source, 500000, fn(issue) {
    issues.push(issue)
  })
  { terrain, issues, face_numbers, }
}

///|
fn decode_records(
  source : String,
  max_records : Int,
  emit : (RecordIssue) -> Unit,
) -> (Terrain, Array[Array[Int]], Array[Int], Array[SurfaceLocations]) raise {
  let root = read_xml(source, max_records)
  guard root.name == "LandXML" && root.attributes.get("version") == Some("1.2") else {
    raise InvalidLandXml("expected a LandXML 1.2 document")
  }
  let mut linear_unit = None
  for unit_group in children(root, "Units") {
    for unit in unit_group.children {
      if unit.name == "Metric" || unit.name == "Imperial" {
        linear_unit = unit.attributes.get("linearUnit")
      }
    }
  }
  let surfaces = []
  let face_numbers = []
  let surface_numbers = []
  let locations = []
  let mut ordinal = 0
  if linear_unit is None {
    emit({
      surface_number: 0,
      surface_name: "",
      code: "missing_linear_unit",
      record_kind: "document",
      record_number: 0,
      message: "no linear unit declared",
      severity: Warning,
      location: root.location,
    })
  }
  for group in children(root, "Surfaces") {
    for surface in children(group, "Surface") {
      ordinal += 1
      let name = surface.attributes.get("name").unwrap_or("(unnamed)")
      let definitions = children(surface, "Definition").filter(fn(item) {
        item.attributes.get("surfType") == Some("TIN")
      })
      if definitions.is_empty() {
        emit({
          surface_number: ordinal,
          surface_name: name,
          record_kind: "surface",
          record_number: ordinal,
          code: "unsupported_surface",
          message: "surface \{name}: no supported TIN definition",
          severity: Warning,
          location: root.location,
        })
        continue
      }
      if definitions.length() > 1 {
        emit({
          surface_number: ordinal,
          surface_name: name,
          record_kind: "surface",
          record_number: ordinal,
          location: surface.location,
          code: "multiple_tin_definitions",
          message: "surface \{name}: multiple TIN definitions",
          severity: Error,
        })
        continue
      }
      for definition in definitions {
        if definition.attributes.get("surfType") != Some("TIN") {
          continue
        }
        let points = []
        let faces = []
        let numbers = []
        let point_locations = []
        let face_locations = Map([])
        let surface_number = ordinal
        let mut point_number = 0
        let mut face_number = 0
        for point_group in children(definition, "Pnts") {
          for point in children(point_group, "P") {
            point_number += 1
            try decode_point(point, name, point_number) catch {
              InvalidLandXml(message) =>
                emit({
                  surface_number,
                  surface_name: name,
                  location: point.location,
                  code: "invalid_point",
                  record_kind: "point",
                  record_number: point_number,
                  message,
                  severity: Error,
                })
              error => raise error
            } noraise {
              decoded => {
                points.push(decoded)
                point_locations.push(point.location)
              }
            }
          }
        }
        for face_group in children(definition, "Faces") {
          for face in children(face_group, "F") {
            face_number += 1
            try decode_face(face, name, face_number) catch {
              InvalidLandXml(message) =>
                emit({
                  surface_number,
                  surface_name: name,
                  location: face.location,
                  code: "invalid_face",
                  record_kind: "face",
                  record_number: face_number,
                  message,
                  severity: Error,
                })
              error => raise error
            } noraise {
              decoded => {
                faces.push(decoded)
                numbers.push(face_number)
                face_locations[face_number] = face.location
              }
            }
          }
        }
        if point_number == 0 || face_number == 0 {
          emit({
            surface_number,
            surface_name: name,
            record_kind: "surface",
            record_number: surface_number,
            location: definition.location,
            code: "empty_tin",
            message: "surface \{name}: expected inline points and faces",
            severity: Error,
          })
        }
        locations.push({ points: point_locations, faces: face_locations, })
        face_numbers.push(numbers)
        surface_numbers.push(ordinal)
        surfaces.push({ name, points, faces, })
      }
    }
  }
  guard !surfaces.is_empty() else {
    raise InvalidLandXml("no TIN surfaces found")
  }
  ({ linear_unit, surfaces, }, face_numbers, surface_numbers, locations)
}
