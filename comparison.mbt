///|
pub suberror ComparisonError {
  InvalidComparison(String)
}

///|
pub struct PointChange {
  id : String
  before : Point
  after : Point
}

///|
pub struct FaceChange {
  vertices : Array[String]
  before_number : Int
  after_number : Int
  winding_changed : Bool
  visibility_changed : Bool
}

///|
pub struct SurfaceComparison {
  name : String
  status : String
  added_point_count : Int
  removed_point_count : Int
  moved_point_count : Int
  added_face_count : Int
  removed_face_count : Int
  changed_face_count : Int
  added_points : Array[String]
  removed_points : Array[String]
  moved_points : Array[PointChange]
  added_faces : Array[Array[String]]
  removed_faces : Array[Array[String]]
  changed_faces : Array[FaceChange]
  truncated : Bool
}

///|
pub struct TerrainComparison {
  linear_unit : String?
  coordinate_tolerance : Double
  surfaces : Array[SurfaceComparison]
}

///|
priv struct IndexedFace {
  number : Int
  forward : Bool
  visible : Bool
}

///|
fn compare_surface_index(
  terrain : Terrain,
  input : String,
) -> Map[String, Surface] raise ComparisonError {
  let result = Map([])
  for surface in terrain.surfaces {
    if result.contains(surface.name) {
      raise InvalidComparison(
        "\{input}: duplicate surface name '\{surface.name}'",
      )
    }
    result[surface.name] = surface
  }
  result
}

///|
fn compare_points(
  surface : Surface,
) -> Map[String, Point] raise ComparisonError {
  let points = Map([])
  for point in surface.points {
    if points.contains(point.id) || !point_is_finite(point) {
      raise InvalidComparison(
        "surface '\{surface.name}': duplicate or invalid point '\{point.id}'",
      )
    }
    points[point.id] = point
  }
  points
}

///|
fn compare_faces(
  surface : Surface,
  points : Map[String, Point],
) -> Map[(String, String, String), IndexedFace] raise ComparisonError {
  let faces = Map([])
  for index, face in surface.faces {
    let (a, b, c) = face.vertices
    for id in [a, b, c] {
      if !points.contains(id) {
        raise InvalidComparison(
          "surface '\{surface.name}': face #\{index + 1} references missing point '\{id}'",
        )
      }
    }
    let sorted = [a, b, c]
    sorted.sort()
    let key = (sorted[0], sorted[1], sorted[2])
    if a == b || b == c || a == c || faces.contains(key) {
      raise InvalidComparison(
        "surface '\{surface.name}': repeated vertices or duplicate face at #\{index + 1}",
      )
    }
    // The parity of the three IDs distinguishes winding from a cyclic rotation.
    let forward = (a < b && b < c) || (b < c && c < a) || (c < a && a < b)
    faces[key] = { number: index + 1, forward, visible: face.visible, }
  }
  faces
}

///|
priv struct ChangeBudget {
  mut remaining : Int
  mut truncated : Bool
}

///|
fn ChangeBudget::keep(self : ChangeBudget) -> Bool {
  if self.remaining == 0 {
    self.truncated = true
    return false
  }
  self.remaining -= 1
  true
}

///|
fn compare_surface(
  name : String,
  before : Surface?,
  after : Surface?,
  tolerance : Double,
  limit : Int,
) -> SurfaceComparison raise ComparisonError {
  let old_points = match before {
    Some(surface) => compare_points(surface)
    None => Map([])
  }
  let new_points = match after {
    Some(surface) => compare_points(surface)
    None => Map([])
  }
  let old_faces = match before {
    Some(surface) => compare_faces(surface, old_points)
    None => Map([])
  }
  let new_faces = match after {
    Some(surface) => compare_faces(surface, new_points)
    None => Map([])
  }
  let budget = ChangeBudget::{ remaining: limit, truncated: false, }
  let added_points = []
  let removed_points = []
  let moved_points = []
  let added_faces = []
  let removed_faces = []
  let changed_faces = []
  let mut added_point_count = 0
  let mut removed_point_count = 0
  let mut moved_point_count = 0
  let mut added_face_count = 0
  let mut removed_face_count = 0
  let mut changed_face_count = 0
  for id in sorted_keys(old_points, new_points) {
    match (old_points.get(id), new_points.get(id)) {
      (None, Some(_)) => {
        added_point_count += 1
        if budget.keep() {
          added_points.push(id)
        }
      }
      (Some(_), None) => {
        removed_point_count += 1
        if budget.keep() {
          removed_points.push(id)
        }
      }
      (Some(old), Some(new)) =>
        if (old.northing - new.northing).abs() > tolerance ||
          (old.easting - new.easting).abs() > tolerance ||
          (old.elevation - new.elevation).abs() > tolerance {
          moved_point_count += 1
          if budget.keep() {
            moved_points.push({ id, before: old, after: new, })
          }
        }
      (None, None) => ()
    }
  }
  for key in sorted_keys(old_faces, new_faces) {
    let (a, b, c) = key
    match (old_faces.get(key), new_faces.get(key)) {
      (None, Some(_)) => {
        added_face_count += 1
        if budget.keep() {
          added_faces.push([a, b, c])
        }
      }
      (Some(_), None) => {
        removed_face_count += 1
        if budget.keep() {
          removed_faces.push([a, b, c])
        }
      }
      (Some(old), Some(new)) => {
        let winding_changed = old.forward != new.forward
        let visibility_changed = old.visible != new.visible
        if winding_changed || visibility_changed {
          changed_face_count += 1
          if budget.keep() {
            changed_faces.push({
              vertices: [a, b, c],
              before_number: old.number,
              after_number: new.number,
              winding_changed,
              visibility_changed,
            })
          }
        }
      }
      (None, None) => ()
    }
  }
  let status = match (before, after) {
    (None, _) => "added"
    (_, None) => "removed"
    _ =>
      if added_point_count +
        removed_point_count +
        moved_point_count +
        added_face_count +
        removed_face_count +
        changed_face_count >
        0 {
        "changed"
      } else {
        "unchanged"
      }
  }
  {
    name,
    status,
    added_point_count,
    removed_point_count,
    moved_point_count,
    added_face_count,
    removed_face_count,
    changed_face_count,
    added_points,
    removed_points,
    moved_points,
    added_faces,
    removed_faces,
    changed_faces,
    truncated: budget.truncated,
  }
}

///|
fn[K : Compare + Hash + Eq, V] sorted_keys(
  before : Map[K, V],
  after : Map[K, V],
) -> Array[K] {
  let keys = []
  before.each(fn(key, _) { keys.push(key) })
  after.each(fn(key, _) { if !before.contains(key) { keys.push(key) } })
  keys.sort()
  keys
}

///|
/// Compares named TIN surfaces using their authored point IDs.
/// Coordinate tolerance applies independently on each axis in the file unit.
/// The detail limit applies per surface and full counts remain available.
pub fn compare_terrain(
  before : Terrain,
  after : Terrain,
  coordinate_tolerance? : Double = 0.0,
  max_details? : Int = 1000,
) -> TerrainComparison raise ComparisonError {
  if coordinate_tolerance < 0.0 ||
    coordinate_tolerance.is_nan() ||
    coordinate_tolerance.is_inf() {
    raise InvalidComparison(
      "coordinate tolerance must be finite and nonnegative",
    )
  }
  if max_details < 0 {
    raise InvalidComparison("comparison detail limit must be nonnegative")
  }
  if before.linear_unit != after.linear_unit {
    raise InvalidComparison("the two files use different linear units")
  }
  let old_surfaces = compare_surface_index(before, "before")
  let new_surfaces = compare_surface_index(after, "after")
  let surfaces = []
  for name in sorted_keys(old_surfaces, new_surfaces) {
    surfaces.push(
      compare_surface(
        name,
        old_surfaces.get(name),
        new_surfaces.get(name),
        coordinate_tolerance,
        max_details,
      ),
    )
  }
  { linear_unit: before.linear_unit, coordinate_tolerance, surfaces, }
}

///|
pub fn TerrainComparison::changed(self : TerrainComparison) -> Bool {
  self.surfaces.any(fn(surface) { surface.status != "unchanged" })
}

///|
fn coordinates_json(point : Point) -> Json {
  {
    "northing": point.northing.to_json(),
    "easting": point.easting.to_json(),
    "elevation": point.elevation.to_json(),
  }
}

///|
pub fn PointChange::to_json(self : PointChange) -> Json {
  {
    "id": self.id.to_json(),
    "before": coordinates_json(self.before),
    "after": coordinates_json(self.after),
  }
}

///|
pub fn FaceChange::to_json(self : FaceChange) -> Json {
  {
    "vertices": self.vertices.to_json(),
    "before_number": self.before_number.to_json(),
    "after_number": self.after_number.to_json(),
    "winding_changed": self.winding_changed.to_json(),
    "visibility_changed": self.visibility_changed.to_json(),
  }
}

///|
pub fn SurfaceComparison::to_json(self : SurfaceComparison) -> Json {
  {
    "name": self.name.to_json(),
    "status": self.status.to_json(),
    "added_point_count": self.added_point_count.to_json(),
    "removed_point_count": self.removed_point_count.to_json(),
    "moved_point_count": self.moved_point_count.to_json(),
    "added_face_count": self.added_face_count.to_json(),
    "removed_face_count": self.removed_face_count.to_json(),
    "changed_face_count": self.changed_face_count.to_json(),
    "added_points": self.added_points.to_json(),
    "removed_points": self.removed_points.to_json(),
    "moved_points": self.moved_points
    .map(fn(point) { point.to_json() })
    .to_json(),
    "added_faces": self.added_faces.to_json(),
    "removed_faces": self.removed_faces.to_json(),
    "changed_faces": self.changed_faces
    .map(fn(face) { face.to_json() })
    .to_json(),
    "truncated": self.truncated.to_json(),
  }
}

///|
pub fn TerrainComparison::to_json(self : TerrainComparison) -> Json {
  {
    "schema_version": 1,
    "changed": self.changed().to_json(),
    "linear_unit": match self.linear_unit {
      Some(unit) => unit.to_json()
      None => Json::null()
    },
    "coordinate_tolerance": self.coordinate_tolerance.to_json(),
    "surfaces": self.surfaces.map(fn(surface) { surface.to_json() }).to_json(),
  }
}
