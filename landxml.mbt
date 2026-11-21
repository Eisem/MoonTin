///|
pub suberror LandXmlError {
  InvalidLandXml(String)
}

///|
priv struct XmlNode {
  name : String
  location : SourceLocation
  attributes : Array[@xml.NamespaceAttribute]
  children : Array[XmlNode]
  mut text : StringBuilder?
  mut has_child_elements : Bool
}

///|
const LANDXML_NAMESPACE = "http://www.landxml.org/schema/LandXML-1.2"

///|
fn xml_node(
  element : @xml.NamespaceElement,
  start : @xml.SourcePosition,
) -> XmlNode {
  {
    name: if element.name.namespace_uri == Some(LANDXML_NAMESPACE) {
      element.name.local_name
    } else {
      ""
    },
    location: { line: start.line, column: start.column, },
    attributes: element.attributes,
    children: [],
    text: None,
    has_child_elements: false,
  }
}

///|
fn XmlNode::attribute(self : XmlNode, name : String) -> String? {
  for attribute in self.attributes {
    if attribute.name.namespace_uri is None && attribute.name.local_name == name {
      return Some(attribute.value)
    }
  }
  None
}

///|
fn XmlNode::record_text(self : XmlNode) -> String {
  match self.text {
    Some(buffer) => buffer.to_string()
    None => ""
  }
}

///|
/// The namespace reader still consumes and checks the entire document.
/// Only nodes reachable through the supported TIN paths need to be retained.
fn retain_xml_node(
  stack : Array[XmlNode?],
  element : @xml.NamespaceElement,
) -> Bool {
  if stack.is_empty() {
    return true
  }
  guard stack.last() is Some(Some(parent)) else { return false }
  parent.has_child_elements = true
  if element.name.namespace_uri != Some(LANDXML_NAMESPACE) {
    return false
  }
  match (parent.name, element.name.local_name) {
    ("LandXML", "Units" | "Surfaces")
    | ("Units", "Metric" | "Imperial")
    | ("Surfaces", "Surface")
    | ("Surface", "Definition")
    | ("Definition", "Pnts" | "Faces")
    | ("Pnts", "P")
    | ("Faces", "F") => true
    _ => false
  }
}

///|
fn read_xml(source : String, max_records : Int) -> XmlNode raise {
  if source.contains("<!DOCTYPE") {
    raise InvalidLandXml("DOCTYPE declarations are unsupported")
  }
  let reader = @xml.NamespaceReader::from_string(source)
  let stack : Array[XmlNode?] = []
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
        let node = if retain_xml_node(stack, element) {
          Some(xml_node(element, event.span.start))
        } else {
          None
        }
        stack.push(node)
      }
      Empty(element) => {
        count_record(element)
        if !retain_xml_node(stack, element) {
          continue
        }
        let node = xml_node(element, event.span.start)
        match stack.last() {
          Some(Some(parent)) => parent.children.push(node)
          Some(None) => ()
          None => root = Some(node)
        }
      }
      End(_) => {
        guard stack.pop() is Some(retained) else {
          raise InvalidLandXml("unexpected closing tag")
        }
        guard retained is Some(node) else { continue }
        match stack.last() {
          Some(Some(parent)) => parent.children.push(node)
          Some(None) => ()
          None => root = Some(node)
        }
      }
      Text(value) | CData(value) =>
        if stack.last() is Some(Some(node)) &&
          (node.name == "P" || node.name == "F") {
          let buffer = match node.text {
            Some(buffer) => buffer
            None => {
              let buffer = StringBuilder()
              node.text = Some(buffer)
              buffer
            }
          }
          buffer.write_string(value)
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
  if node.attribute("pntRef") is Some(_) {
    raise InvalidLandXml(
      "\{location}: external point references are unsupported",
    )
  }
  guard !node.has_child_elements else {
    raise InvalidLandXml("\{location}: unexpected XML inside point record")
  }
  guard node.attribute("id") is Some(id) && !id.is_empty() else {
    raise InvalidLandXml("\{location}: missing point ID")
  }
  guard tokens(node.record_text()) is [north, east, elevation] else {
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
  guard !node.has_child_elements else {
    raise InvalidLandXml("\{location}: unexpected XML inside face record")
  }
  guard tokens(node.record_text()) is [a, b, c] else {
    raise InvalidLandXml("\{location}: expected three point IDs")
  }
  let visible = match node.attribute("i") {
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
  guard root.name == "LandXML" && root.attribute("version") == Some("1.2") else {
    raise InvalidLandXml("expected a LandXML 1.2 document")
  }
  let mut linear_unit = None
  for unit_group in children(root, "Units") {
    for unit in unit_group.children {
      if unit.name == "Metric" || unit.name == "Imperial" {
        linear_unit = unit.attribute("linearUnit")
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
      let name = surface.attribute("name").unwrap_or("(unnamed)")
      let definitions = children(surface, "Definition").filter(fn(item) {
        item.attribute("surfType") == Some("TIN")
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
        if definition.attribute("surfType") != Some("TIN") {
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
