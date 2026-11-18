///|
pub struct FaceGeometry {
  projected_area : Double?
  surface_area : Double?
  min_grade_percent : Double?
  max_grade_percent : Double?
  measured_faces : Int
  overflow_faces : Int
}

///|
priv struct GeometryAccumulator {
  mut projected_area : Double
  mut surface_area : Double
  mut min_grade : Double?
  mut max_grade : Double?
  mut measured_faces : Int
  mut overflow_faces : Int
}

///|
fn GeometryAccumulator::new() -> GeometryAccumulator {
  {
    projected_area: 0.0,
    surface_area: 0.0,
    min_grade: None,
    max_grade: None,
    measured_faces: 0,
    overflow_faces: 0,
  }
}

///|
fn scaled_norm(x : Double, y : Double, z : Double) -> Double {
  let scale = x.abs().max(y.abs()).max(z.abs())
  if scale == 0.0 || !finite_sample_value(scale) {
    return scale
  }
  let a = x / scale
  let b = y / scale
  let c = z / scale
  scale * (a * a + b * b + c * c).sqrt()
}

///|
fn GeometryAccumulator::add_face(
  self : GeometryAccumulator,
  a : Point,
  b : Point,
  c : Point,
  area : Double,
) -> Unit {
  self.projected_area += area
  let east_b = b.easting - a.easting
  let north_b = b.northing - a.northing
  let elevation_b = b.elevation - a.elevation
  let east_c = c.easting - a.easting
  let north_c = c.northing - a.northing
  let elevation_c = c.elevation - a.elevation
  // Scale the cross product by one half to obtain the triangle area.
  let east_component = north_b * (elevation_c / 2.0) -
    elevation_b * (north_c / 2.0)
  let north_component = elevation_b * (east_c / 2.0) -
    east_b * (elevation_c / 2.0)
  let surface_area = scaled_norm(east_component, north_component, area)
  let grade = scaled_norm(east_component, north_component, 0.0) / area * 100.0
  if !finite_sample_value(surface_area) || !finite_sample_value(grade) {
    self.overflow_faces += 1
    return
  }
  self.surface_area += surface_area
  self.measured_faces += 1
  self.min_grade = Some(
    match self.min_grade {
      Some(previous) => previous.min(grade)
      None => grade
    },
  )
  self.max_grade = Some(
    match self.max_grade {
      Some(previous) => previous.max(grade)
      None => grade
    },
  )
}

///|
fn GeometryAccumulator::summarize(self : GeometryAccumulator) -> FaceGeometry {
  {
    projected_area: if finite_sample_value(self.projected_area) {
      Some(self.projected_area)
    } else {
      None
    },
    surface_area: if self.overflow_faces == 0 &&
      finite_sample_value(self.surface_area) {
      Some(self.surface_area)
    } else {
      None
    },
    min_grade_percent: self.min_grade,
    max_grade_percent: self.max_grade,
    measured_faces: self.measured_faces,
    overflow_faces: self.overflow_faces,
  }
}

///|
fn metric_json(value : Double?) -> Json {
  match value {
    Some(number) => number.to_json()
    None => Json::null()
  }
}

///|
pub fn FaceGeometry::to_json(self : FaceGeometry) -> Json {
  {
    "projected_area": metric_json(self.projected_area),
    "surface_area": metric_json(self.surface_area),
    "min_grade_percent": metric_json(self.min_grade_percent),
    "max_grade_percent": metric_json(self.max_grade_percent),
    "measured_faces": self.measured_faces.to_json(),
    "overflow_faces": self.overflow_faces.to_json(),
  }
}
