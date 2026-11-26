///|
priv struct SampleBounds {
  min_north : Double
  max_north : Double
  min_east : Double
  max_east : Double
}

///|
fn SampleBounds::of_triangle(triangle : SamplingTriangle) -> SampleBounds {
  let a = triangle.a
  let b = triangle.b
  let c = triangle.c
  {
    min_north: a.northing.min(b.northing).min(c.northing),
    max_north: a.northing.max(b.northing).max(c.northing),
    min_east: a.easting.min(b.easting).min(c.easting),
    max_east: a.easting.max(b.easting).max(c.easting),
  }
}

///|
fn SampleBounds::union(
  self : SampleBounds,
  other : SampleBounds,
) -> SampleBounds {
  {
    min_north: self.min_north.min(other.min_north),
    max_north: self.max_north.max(other.max_north),
    min_east: self.min_east.min(other.min_east),
    max_east: self.max_east.max(other.max_east),
  }
}

///|
fn SampleBounds::contains(
  self : SampleBounds,
  north : Double,
  east : Double,
) -> Bool {
  north >= self.min_north &&
  north <= self.max_north &&
  east >= self.min_east &&
  east <= self.max_east
}

///|
priv struct IndexTriangle {
  bounds : SampleBounds
  triangle : SamplingTriangle
}

///|
priv enum SampleTree {
  Leaf(SampleBounds, Array[IndexTriangle])
  Branch(SampleBounds, SampleTree, SampleTree)
}

///|
fn SampleTree::build(entries : Array[IndexTriangle]) -> SampleTree {
  let mut bounds = entries[0].bounds
  for entry in entries[1:] {
    bounds = bounds.union(entry.bounds)
  }
  if entries.length() <= 12 {
    return Leaf(bounds, entries)
  }
  let split_north = bounds.max_north - bounds.min_north >=
    bounds.max_east - bounds.min_east
  entries.sort_by(fn(a, b) {
    let left = a.bounds
    let right = b.bounds
    if split_north {
      (left.min_north / 2.0 + left.max_north / 2.0).compare(
        right.min_north / 2.0 + right.max_north / 2.0,
      )
    } else {
      (left.min_east / 2.0 + left.max_east / 2.0).compare(
        right.min_east / 2.0 + right.max_east / 2.0,
      )
    }
  })
  let middle = entries.length() / 2
  Branch(
    bounds,
    SampleTree::build(entries[:middle].to_owned()),
    SampleTree::build(entries[middle:].to_owned()),
  )
}

///|
fn SampleTree::visit_hits(
  self : SampleTree,
  north : Double,
  east : Double,
  visit : (SamplingTriangle, Double) -> Unit,
) -> Unit {
  match self {
    Leaf(bounds, entries) =>
      if bounds.contains(north, east) {
        for entry in entries {
          if entry.bounds.contains(north, east) {
            let triangle = entry.triangle
            if barycentric_elevation(
                triangle.a,
                triangle.b,
                triangle.c,
                north,
                east,
              )
              is Some(elevation) {
              visit(triangle, elevation)
            }
          }
        }
      }
    Branch(bounds, left, right) =>
      if bounds.contains(north, east) {
        left.visit_hits(north, east, visit)
        right.visit_hits(north, east, visit)
      }
  }
}

///|
/// A snapshot of visible TIN triangles for repeated elevation queries.
pub struct ElevationIndex {
  triangle_count : Int
  linear_unit : String?
  priv root : SampleTree?
}

///|
/// Builds a bounding-volume hierarchy for one surface or all surfaces.
pub fn build_elevation_index(
  terrain : Terrain,
  surface_name? : String,
) -> ElevationIndex raise SamplingError {
  let entries = []
  each_visible_triangle(terrain, surface_name, fn(triangle) {
    entries.push({ bounds: SampleBounds::of_triangle(triangle), triangle, })
  })
  {
    triangle_count: entries.length(),
    linear_unit: terrain.linear_unit,
    root: if entries.is_empty() {
      None
    } else {
      Some(SampleTree::build(entries))
    },
  }
}

///|
/// Returns the same ordered hits as a direct scan of the TIN.
pub fn ElevationIndex::sample(
  self : ElevationIndex,
  northing : Double,
  easting : Double,
) -> ElevationSample raise SamplingError {
  if !finite_sample_value(northing) || !finite_sample_value(easting) {
    raise InvalidSample("query coordinates must be finite")
  }
  let hits = []
  if self.root is Some(root) {
    root.visit_hits(northing, easting, fn(triangle, elevation) {
      hits.push(triangle_hit(triangle, elevation))
    })
    hits.sort_by(fn(a, b) {
      let surface = a.surface_number.compare(b.surface_number)
      if surface == 0 {
        a.face_number.compare(b.face_number)
      } else {
        surface
      }
    })
  }
  { northing, easting, linear_unit: self.linear_unit, hits, }
}
