///|
pub suberror SamplingError {
  InvalidSample(String)
}

///|
pub struct ElevationHit {
  surface_number : Int
  surface_name : String
  face_number : Int
  elevation : Double
  point_ids : Array[String]
}

///|
pub struct ElevationSample {
  northing : Double
  easting : Double
  linear_unit : String?
  hits : Array[ElevationHit]
}

///|
fn finite_sample_value(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}

///|
fn barycentric_elevation(
  a : Point,
  b : Point,
  c : Point,
  northing : Double,
  easting : Double,
) -> Double? {
  if northing < a.northing.min(b.northing).min(c.northing) ||
    northing > a.northing.max(b.northing).max(c.northing) ||
    easting < a.easting.min(b.easting).min(c.easting) ||
    easting > a.easting.max(b.easting).max(c.easting) {
    return None
  }
  let bx = b.easting - a.easting
  let by = b.northing - a.northing
  let cx = c.easting - a.easting
  let cy = c.northing - a.northing
  let qx = easting - a.easting
  let qy = northing - a.northing
  let determinant = bx * cy - by * cx
  if determinant == 0.0 || !finite_sample_value(determinant) {
    return None
  }
  let w_b = (qx * cy - qy * cx) / determinant
  let w_c = (bx * qy - by * qx) / determinant
  let w_a = 1.0 - w_b - w_c
  // Roundoff at a shared edge can put one weight just below zero.
  let slack = 1.0e-12
  if w_a < -slack || w_b < -slack || w_c < -slack {
    return None
  }
  let a_weight = w_a.max(0.0)
  let b_weight = w_b.max(0.0)
  let c_weight = w_c.max(0.0)
  let total = a_weight + b_weight + c_weight
  let elevation = a_weight / total * a.elevation +
    b_weight / total * b.elevation +
    c_weight / total * c.elevation
  if finite_sample_value(elevation) {
    Some(elevation)
  } else {
    None
  }
}

///|
/// Returns every visible face containing the query position in file order.
/// Multiple hits let callers inspect shared edges and overlapping surfaces.
pub fn sample_elevation(
  terrain : Terrain,
  northing : Double,
  easting : Double,
  surface_name? : String,
) -> ElevationSample raise SamplingError {
  if !finite_sample_value(northing) || !finite_sample_value(easting) {
    raise InvalidSample("query coordinates must be finite")
  }
  let hits = []
  each_visible_triangle(terrain, surface_name, fn(triangle) {
    if barycentric_elevation(
        triangle.a,
        triangle.b,
        triangle.c,
        northing,
        easting,
      )
      is Some(elevation) {
      hits.push(triangle_hit(triangle, elevation))
    }
  })
  { northing, easting, linear_unit: terrain.linear_unit, hits, }
}

///|
priv struct SamplingTriangle {
  surface_number : Int
  surface_name : String
  face_number : Int
  a : Point
  b : Point
  c : Point
}

///|
fn each_visible_triangle(
  terrain : Terrain,
  surface_name : String?,
  visit : (SamplingTriangle) -> Unit,
) -> Unit raise SamplingError {
  let mut matched = false
  for index, surface in terrain.surfaces {
    if surface_name is Some(name) && name != surface.name {
      continue
    }
    matched = true
    let points : Map[String, Point] = Map([])
    for point in surface.points {
      if points.contains(point.id) || !point_is_finite(point) {
        raise InvalidSample(
          "surface '\{surface.name}': ambiguous or invalid point '\{point.id}'",
        )
      }
      points[point.id] = point
    }
    for face_index, face in surface.faces {
      let (a_id, b_id, c_id) = face.vertices
      guard (points.get(a_id), points.get(b_id), points.get(c_id))
        is (Some(a), Some(b), Some(c)) else {
        raise InvalidSample(
          "surface '\{surface.name}': face #\{face_index + 1} references a missing point",
        )
      }
      if face.visible {
        visit({
          surface_number: index + 1,
          surface_name: surface.name,
          face_number: face_index + 1,
          a,
          b,
          c,
        })
      }
    }
  }
  if surface_name is Some(name) && !matched {
    raise InvalidSample("surface '\{name}' was not found")
  }
}

///|
pub fn ElevationHit::to_json(self : ElevationHit) -> Json {
  {
    "surface_number": ToJson::to_json(self.surface_number),
    "surface_name": ToJson::to_json(self.surface_name),
    "face_number": ToJson::to_json(self.face_number),
    "elevation": ToJson::to_json(self.elevation),
    "point_ids": ToJson::to_json(self.point_ids),
  }
}

///|
pub fn ElevationSample::to_json(self : ElevationSample) -> Json {
  {
    "schema_version": 1,
    "northing": ToJson::to_json(self.northing),
    "easting": ToJson::to_json(self.easting),
    "linear_unit": match self.linear_unit {
      Some(unit) => ToJson::to_json(unit)
      None => Json::null()
    },
    "hits": ToJson::to_json(self.hits.map(fn(hit) { hit.to_json() })),
  }
}

///|
fn triangle_hit(
  triangle : SamplingTriangle,
  elevation : Double,
) -> ElevationHit {
  {
    surface_number: triangle.surface_number,
    surface_name: triangle.surface_name,
    face_number: triangle.face_number,
    elevation,
    point_ids: [triangle.a.id, triangle.b.id, triangle.c.id],
  }
}
