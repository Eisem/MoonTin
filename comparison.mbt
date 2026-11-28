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
  before_number : Int32
  after_number : Int32
  winding_changed : Bool
  visibility_changed : Bool
}

///|
pub struct SurfaceComparison {
  name : String
  status : String
  added_point_count : Int32
  removed_point_count : Int32
  moved_point_count : Int32
  added_face_count : Int32
  removed_face_count : Int32
  changed_face_count : Int32
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
  number : Int32
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
  mut remaining : Int32
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
  limit : Int32,
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
  coordinate_tolerance~ : Double = 0.0,
  max_details~ : Int32 = 1000,
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
    "northing": ToJson::to_json(point.northing),
    "easting": ToJson::to_json(point.easting),
    "elevation": ToJson::to_json(point.elevation),
  }
}

///|
pub fn PointChange::to_json(self : PointChange) -> Json {
  {
    "id": ToJson::to_json(self.id),
    "before": coordinates_json(self.before),
    "after": coordinates_json(self.after),
  }
}

///|
pub fn FaceChange::to_json(self : FaceChange) -> Json {
  {
    "vertices": ToJson::to_json(self.vertices),
    "before_number": ToJson::to_json(self.before_number),
    "after_number": ToJson::to_json(self.after_number),
    "winding_changed": ToJson::to_json(self.winding_changed),
    "visibility_changed": ToJson::to_json(self.visibility_changed),
  }
}

///|
pub fn SurfaceComparison::to_json(self : SurfaceComparison) -> Json {
  {
    "name": ToJson::to_json(self.name),
    "status": ToJson::to_json(self.status),
    "added_point_count": ToJson::to_json(self.added_point_count),
    "removed_point_count": ToJson::to_json(self.removed_point_count),
    "moved_point_count": ToJson::to_json(self.moved_point_count),
    "added_face_count": ToJson::to_json(self.added_face_count),
    "removed_face_count": ToJson::to_json(self.removed_face_count),
    "changed_face_count": ToJson::to_json(self.changed_face_count),
    "added_points": ToJson::to_json(self.added_points),
    "removed_points": ToJson::to_json(self.removed_points),
    "moved_points": ToJson::to_json(
      self.moved_points.map(fn(point) { point.to_json() }),
    ),
    "added_faces": ToJson::to_json(self.added_faces),
    "removed_faces": ToJson::to_json(self.removed_faces),
    "changed_faces": ToJson::to_json(
      self.changed_faces.map(fn(face) { face.to_json() }),
    ),
    "truncated": ToJson::to_json(self.truncated),
  }
}

///|
pub fn TerrainComparison::to_json(self : TerrainComparison) -> Json {
  {
    "schema_version": 1,
    "changed": ToJson::to_json(self.changed()),
    "linear_unit": match self.linear_unit {
      Some(unit) => ToJson::to_json(unit)
      None => Json::null()
    },
    "coordinate_tolerance": ToJson::to_json(self.coordinate_tolerance),
    "surfaces": ToJson::to_json(
      self.surfaces.map(fn(surface) { surface.to_json() }),
    ),
  }
}
