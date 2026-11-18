///|
pub struct ProfileSegment {
  surface_number : Int
  surface_name : String
  face_number : Int
  start_distance : Double
  end_distance : Double
  start_elevation : Double
  end_elevation : Double
}

///|
pub struct ProfileRange {
  start_distance : Double
  end_distance : Double
}

///|
pub struct ElevationProfile {
  length : Double
  linear_unit : String?
  segments : Array[ProfileSegment]
  gaps : Array[ProfileRange]
}

///|
priv struct ProfileLine {
  northing : Double
  easting : Double
  north_delta : Double
  east_delta : Double
  length : Double
}

///|
fn profile_line(
  start : (Double, Double),
  end : (Double, Double),
) -> ProfileLine raise SamplingError {
  let (northing, easting) = start
  let (end_northing, end_easting) = end
  let north_delta = end_northing - northing
  let east_delta = end_easting - easting
  let scale = north_delta.abs().max(east_delta.abs())
  if scale == 0.0 ||
    !finite_sample_value(scale) ||
    !finite_sample_value(north_delta) ||
    !finite_sample_value(east_delta) {
    raise InvalidSample("profile endpoints must define a finite nonzero line")
  }
  let north = north_delta / scale
  let east = east_delta / scale
  let length = scale * (north * north + east * east).sqrt()
  if !finite_sample_value(length) {
    raise InvalidSample("profile length exceeds numeric range")
  }
  { northing, easting, north_delta, east_delta, length, }
}

///|
priv struct LinearWeight {
  initial : Double
  delta : Double
}

///|
fn triangle_weights(
  triangle : SamplingTriangle,
  line : ProfileLine,
) -> Array[LinearWeight]? {
  let a = triangle.a
  let b = triangle.b
  let c = triangle.c
  let bx = b.easting - a.easting
  let by = b.northing - a.northing
  let cx = c.easting - a.easting
  let cy = c.northing - a.northing
  let determinant = bx * cy - by * cx
  if determinant == 0.0 || !finite_sample_value(determinant) {
    return None
  }
  let qx = line.easting - a.easting
  let qy = line.northing - a.northing
  let wb = (qx * cy - qy * cx) / determinant
  let wc = (bx * qy - by * qx) / determinant
  let db = (line.east_delta * cy - line.north_delta * cx) / determinant
  let dc = (bx * line.north_delta - by * line.east_delta) / determinant
  let weights : Array[LinearWeight] = [
    { initial: 1.0 - wb - wc, delta: -db - dc, },
    { initial: wb, delta: db, },
    { initial: wc, delta: dc, },
  ]
  if weights.all(fn(weight) {
      finite_sample_value(weight.initial) && finite_sample_value(weight.delta)
    }) {
    Some(weights)
  } else {
    None
  }
}

///|
fn profile_elevation(
  weights : Array[LinearWeight],
  heights : Array[Double],
  fraction : Double,
) -> Double {
  let values = weights.map(fn(weight) {
    (weight.initial + fraction * weight.delta).max(0.0)
  })
  let total = values[0] + values[1] + values[2]
  values[0] / total * heights[0] +
  values[1] / total * heights[1] +
  values[2] / total * heights[2]
}

///|
fn profile_segment(
  triangle : SamplingTriangle,
  line : ProfileLine,
) -> ProfileSegment? {
  guard triangle_weights(triangle, line) is Some(weights) else { return None }
  let mut start = 0.0
  let mut end = 1.0
  // A point on the line lies in the face when all barycentric weights are nonnegative.
  for weight in weights {
    if weight.delta > 0.0 {
      start = start.max(-weight.initial / weight.delta)
    } else if weight.delta < 0.0 {
      end = end.min(-weight.initial / weight.delta)
    } else if weight.initial < -1.0e-12 {
      return None
    }
  }
  if start >= end {
    return None
  }
  let heights = [
    triangle.a.elevation,
    triangle.b.elevation,
    triangle.c.elevation,
  ]
  let start_elevation = profile_elevation(weights, heights, start)
  let end_elevation = profile_elevation(weights, heights, end)
  if !finite_sample_value(start_elevation) ||
    !finite_sample_value(end_elevation) {
    return None
  }
  Some({
    surface_number: triangle.surface_number,
    surface_name: triangle.surface_name,
    face_number: triangle.face_number,
    start_distance: start * line.length,
    end_distance: end * line.length,
    start_elevation,
    end_elevation,
  })
}

///|
fn profile_gaps(
  segments : Array[ProfileSegment],
  length : Double,
) -> Array[ProfileRange] {
  let gaps = []
  let mut covered = 0.0
  let tolerance = length * 1.0e-12
  for segment in segments {
    if segment.start_distance - covered > tolerance {
      gaps.push({
        start_distance: covered,
        end_distance: segment.start_distance,
      })
    }
    covered = covered.max(segment.end_distance)
  }
  if length - covered > tolerance {
    gaps.push({ start_distance: covered, end_distance: length, })
  }
  gaps
}

///|
/// Extracts piecewise linear elevation along a straight survey line.
/// Endpoints are (northing, easting). Shared edges and overlaps retain each hit.
pub fn elevation_profile(
  terrain : Terrain,
  start : (Double, Double),
  end : (Double, Double),
  surface_name? : String,
) -> ElevationProfile raise SamplingError {
  let line = profile_line(start, end)
  let segments = []
  each_visible_triangle(terrain, surface_name, fn(triangle) {
    if profile_segment(triangle, line) is Some(segment) {
      segments.push(segment)
    }
  })
  segments.sort_by(fn(a, b) {
    let order = a.start_distance.compare(b.start_distance)
    if order != 0 {
      order
    } else if a.surface_number != b.surface_number {
      a.surface_number.compare(b.surface_number)
    } else {
      a.face_number.compare(b.face_number)
    }
  })
  {
    length: line.length,
    linear_unit: terrain.linear_unit,
    gaps: profile_gaps(segments, line.length),
    segments,
  }
}

///|
pub fn ProfileSegment::to_json(self : ProfileSegment) -> Json {
  {
    "surface_number": self.surface_number.to_json(),
    "surface_name": self.surface_name.to_json(),
    "face_number": self.face_number.to_json(),
    "start_distance": self.start_distance.to_json(),
    "end_distance": self.end_distance.to_json(),
    "start_elevation": self.start_elevation.to_json(),
    "end_elevation": self.end_elevation.to_json(),
  }
}

///|
pub fn ProfileRange::to_json(self : ProfileRange) -> Json {
  {
    "start_distance": self.start_distance.to_json(),
    "end_distance": self.end_distance.to_json(),
  }
}

///|
pub fn ElevationProfile::to_json(self : ElevationProfile) -> Json {
  {
    "schema_version": 1,
    "length": self.length.to_json(),
    "linear_unit": match self.linear_unit {
      Some(unit) => unit.to_json()
      None => Json::null()
    },
    "segments": self.segments.map(fn(segment) { segment.to_json() }).to_json(),
    "gaps": self.gaps.map(fn(gap) { gap.to_json() }).to_json(),
  }
}
