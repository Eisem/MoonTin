///|
pub(all) struct ReferencePlane {
  northing : Double
  easting : Double
  elevation : Double
  north_grade : Double
  east_grade : Double
}

///|
pub struct VolumeSurface {
  number : Int32
  name : String
  faces : Int32
  above_faces : Int32
  below_faces : Int32
  crossing_faces : Int32
  coincident_faces : Int32
  projected_area : Double
  above_area : Double
  below_area : Double
  cut : Double
  fill : Double
}

///|
pub struct VolumeReport {
  reference : ReferencePlane
  linear_unit : String?
  surfaces : Array[VolumeSurface]
  cut : Double
  fill : Double
}

///|
priv struct VolumeAccumulator {
  number : Int32
  name : String
  mut faces : Int32
  mut above_faces : Int32
  mut below_faces : Int32
  mut crossing_faces : Int32
  mut coincident_faces : Int32
  mut projected_area : Double
  mut above_area : Double
  mut below_area : Double
  mut cut : Double
  mut fill : Double
  face_keys : Map[(String, String, String), Bool]
}

///|
fn VolumeAccumulator::new(triangle : SamplingTriangle) -> VolumeAccumulator {
  {
    number: triangle.surface_number,
    name: triangle.surface_name,
    faces: 0,
    above_faces: 0,
    below_faces: 0,
    crossing_faces: 0,
    coincident_faces: 0,
    projected_area: 0.0,
    above_area: 0.0,
    below_area: 0.0,
    cut: 0.0,
    fill: 0.0,
    face_keys: Map([]),
  }
}

///|
fn ReferencePlane::height_difference(
  self : ReferencePlane,
  point : Point,
) -> Double {
  let north = if self.north_grade == 0.0 {
    0.0
  } else {
    (point.northing - self.northing) * self.north_grade
  }
  let east = if self.east_grade == 0.0 {
    0.0
  } else {
    (point.easting - self.easting) * self.east_grade
  }
  point.elevation - self.elevation - north - east
}

///|
priv struct VolumeVertex {
  x : Double
  y : Double
  difference : Double
}

///|
/// Clips the triangle in barycentric coordinates to one side of the plane.
fn clip_volume_face(
  vertices : Array[VolumeVertex],
  above : Bool,
) -> Array[VolumeVertex] {
  let polygon = []
  let mut previous = vertices[2]
  for current in vertices {
    let previous_inside = if above {
      previous.difference >= 0.0
    } else {
      previous.difference <= 0.0
    }
    let current_inside = if above {
      current.difference >= 0.0
    } else {
      current.difference <= 0.0
    }
    if previous_inside != current_inside {
      let first = previous.difference.abs()
      let second = current.difference.abs()
      let scale = first.max(second)
      let fraction = first / scale / (first / scale + second / scale)
      polygon.push({
        x: previous.x + fraction * (current.x - previous.x),
        y: previous.y + fraction * (current.y - previous.y),
        difference: 0.0,
      })
    }
    if current_inside {
      polygon.push(current)
    }
    previous = current
  }
  polygon
}

///|
fn integrate_volume_polygon(
  polygon : Array[VolumeVertex],
  face_area : Double,
) -> (Double, Double) {
  let mut area = 0.0
  let mut volume = 0.0
  if polygon.length() < 3 {
    return (area, volume)
  }
  let origin = polygon[0]
  for index = 1; index + 1 < polygon.length(); index = index + 1 {
    let b = polygon[index]
    let c = polygon[index + 1]
    let fraction = ((b.x - origin.x) * (c.y - origin.y) -
    (b.y - origin.y) * (c.x - origin.x)).abs()
    let part_area = face_area * fraction
    let average = origin.difference.abs() / 3.0 +
      b.difference.abs() / 3.0 +
      c.difference.abs() / 3.0
    area += part_area
    volume += part_area * average
  }
  (area, volume)
}

///|
fn VolumeAccumulator::add(
  self : VolumeAccumulator,
  triangle : SamplingTriangle,
  reference : ReferencePlane,
) -> String? {
  let ids = [triangle.a.id, triangle.b.id, triangle.c.id]
  ids.sort()
  let key = (ids[0], ids[1], ids[2])
  if self.face_keys.contains(key) {
    return Some(
      "surface '\{self.name}': duplicate face #\{triangle.face_number}",
    )
  }
  self.face_keys[key] = true
  let area = projected_area(triangle.a, triangle.b, triangle.c)
  let a = reference.height_difference(triangle.a)
  let b = reference.height_difference(triangle.b)
  let c = reference.height_difference(triangle.c)
  if area <= 0.0 || !finite_sample_value(area) {
    return Some(
      "surface '\{self.name}': invalid projected area at face #\{triangle.face_number}",
    )
  }
  if ![a, b, c].all(finite_sample_value) {
    return Some(
      "surface '\{self.name}': reference height difference exceeds numeric range",
    )
  }
  self.faces += 1
  self.projected_area += area
  let positive = a > 0.0 || b > 0.0 || c > 0.0
  let negative = a < 0.0 || b < 0.0 || c < 0.0
  match (positive, negative) {
    (true, true) => {
      self.crossing_faces += 1
      let vertices : Array[VolumeVertex] = [
        { x: 0.0, y: 0.0, difference: a, },
        { x: 1.0, y: 0.0, difference: b, },
        { x: 0.0, y: 1.0, difference: c, },
      ]
      let (upper_area, cut) = integrate_volume_polygon(
        clip_volume_face(vertices, true),
        area,
      )
      let (lower_area, fill) = integrate_volume_polygon(
        clip_volume_face(vertices, false),
        area,
      )
      self.above_area += upper_area
      self.below_area += lower_area
      self.cut += cut
      self.fill += fill
    }
    (true, false) => {
      self.above_faces += 1
      self.above_area += area
      self.cut += area * (a / 3.0 + b / 3.0 + c / 3.0)
    }
    (false, true) => {
      self.below_faces += 1
      self.below_area += area
      self.fill += area * (a.abs() / 3.0 + b.abs() / 3.0 + c.abs() / 3.0)
    }
    (false, false) => self.coincident_faces += 1
  }
  if ![
      self.projected_area,
      self.above_area,
      self.below_area,
      self.cut,
      self.fill,
    ].all(finite_sample_value) {
    return Some("surface '\{self.name}': volume or area exceeds numeric range")
  }
  None
}

///|
fn VolumeAccumulator::result(self : VolumeAccumulator) -> VolumeSurface {
  {
    number: self.number,
    name: self.name,
    faces: self.faces,
    above_faces: self.above_faces,
    below_faces: self.below_faces,
    crossing_faces: self.crossing_faces,
    coincident_faces: self.coincident_faces,
    projected_area: self.projected_area,
    above_area: self.above_area,
    below_area: self.below_area,
    cut: self.cut,
    fill: self.fill,
  }
}

///|
/// Integrates vertical cut and fill with respect to a planar reference.
/// Grades are rises per unit horizontal distance, not percentages.
pub fn estimate_volume(
  terrain : Terrain,
  reference : ReferencePlane,
  surface_name? : String,
) -> VolumeReport raise SamplingError {
  if ![
      reference.northing,
      reference.easting,
      reference.elevation,
      reference.north_grade,
      reference.east_grade,
    ].all(finite_sample_value) {
    raise InvalidSample("reference plane parameters must be finite")
  }
  let accumulators : Map[Int32, VolumeAccumulator] = Map([])
  let mut problem = None
  each_visible_triangle(terrain, surface_name, fn(triangle) {
    if problem is Some(_) {
      return
    }
    let accumulator = match accumulators.get(triangle.surface_number) {
      Some(accumulator) => accumulator
      None => {
        let accumulator = VolumeAccumulator::new(triangle)
        accumulators[triangle.surface_number] = accumulator
        accumulator
      }
    }
    problem = accumulator.add(triangle, reference)
  })
  if problem is Some(message) {
    raise InvalidSample(message)
  }
  let surfaces = []
  let mut cut = 0.0
  let mut fill = 0.0
  for index = 1; index <= terrain.surfaces.length(); index = index + 1 {
    if accumulators.get(index) is Some(accumulator) {
      surfaces.push(accumulator.result())
      cut += accumulator.cut
      fill += accumulator.fill
    }
  }
  if !finite_sample_value(cut) || !finite_sample_value(fill) {
    raise InvalidSample("combined cut or fill exceeds numeric range")
  }
  { reference, linear_unit: terrain.linear_unit, surfaces, cut, fill, }
}

///|
pub fn ReferencePlane::to_json(self : ReferencePlane) -> Json {
  {
    "northing": ToJson::to_json(self.northing),
    "easting": ToJson::to_json(self.easting),
    "elevation": ToJson::to_json(self.elevation),
    "north_grade": ToJson::to_json(self.north_grade),
    "east_grade": ToJson::to_json(self.east_grade),
  }
}

///|
pub fn VolumeSurface::to_json(self : VolumeSurface) -> Json {
  {
    "surface_number": ToJson::to_json(self.number),
    "surface_name": ToJson::to_json(self.name),
    "faces": ToJson::to_json(self.faces),
    "above_faces": ToJson::to_json(self.above_faces),
    "below_faces": ToJson::to_json(self.below_faces),
    "crossing_faces": ToJson::to_json(self.crossing_faces),
    "coincident_faces": ToJson::to_json(self.coincident_faces),
    "projected_area": ToJson::to_json(self.projected_area),
    "above_area": ToJson::to_json(self.above_area),
    "below_area": ToJson::to_json(self.below_area),
    "cut": ToJson::to_json(self.cut),
    "fill": ToJson::to_json(self.fill),
    "net_cut": ToJson::to_json(self.cut - self.fill),
  }
}

///|
pub fn VolumeReport::to_json(self : VolumeReport) -> Json {
  {
    "schema_version": 1,
    "reference": self.reference.to_json(),
    "linear_unit": match self.linear_unit {
      Some(unit) => ToJson::to_json(unit)
      None => Json::null()
    },
    "cut": ToJson::to_json(self.cut),
    "fill": ToJson::to_json(self.fill),
    "net_cut": ToJson::to_json(self.cut - self.fill),
    "surfaces": ToJson::to_json(
      self.surfaces.map(fn(surface) { surface.to_json() }),
    ),
  }
}
