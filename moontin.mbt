///|
pub(all) struct Point {
  id : String
  northing : Double
  easting : Double
  elevation : Double
}

///|
pub(all) struct Face {
  vertices : (String, String, String)
  visible : Bool
}

///|
pub(all) struct Surface {
  name : String
  points : Array[Point]
  faces : Array[Face]
}

///|
pub(all) struct Terrain {
  linear_unit : String?
  surfaces : Array[Surface]
}

///|
pub(all) enum Rule {
  DuplicatePoint
  MissingPoint
  AmbiguousPoint
  NonFinitePoint
  RepeatedVertex
  DegenerateFace
  NonFiniteArea
  DuplicateFace
  NonManifoldEdge
  SharedEdgeDirection
  BranchingBoundary
}

///|
pub(all) struct Diagnostic {
  rule : Rule
  surface_number : Int32
  surface_name : String
  face_number : Int32?
  point_ids : Array[String]
  location : SourceLocation?
  related_faces : Array[FaceReference]
}

///|
pub fn validate(
  terrain : Terrain,
  area_tolerance~ : Double = 0.0,
) -> Array[Diagnostic] {
  let diagnostics = []
  terrain.surfaces.eachi(fn(index, surface) {
    ignore(
      validate_surface(
        surface,
        index + 1,
        area_tolerance,
        fn(item) { diagnostics.push(item) },
        None,
        None,
      ),
    )
  })
  diagnostics
}

///|
fn validate_surface(
  surface : Surface,
  surface_number : Int32,
  area_tolerance : Double,
  emit : (Diagnostic) -> Unit,
  face_numbers : Array[Int32]?,
  locations : SurfaceLocations?,
) -> SurfaceSummary {
  let points : Map[String, Point] = Map([])
  let ambiguous : Map[String, Bool] = Map([])
  let topology = SurfaceTopology::new()
  let geometry = GeometryAccumulator::new()
  let emit_face = fn(rule, face_number, point_ids, related : Array[Int32]) {
    let location = match (locations, face_number) {
      (Some(source), Some(number)) => source.faces.get(number)
      _ => None
    }
    emit({
      rule,
      surface_number,
      surface_name: surface.name,
      face_number,
      point_ids,
      location,
      related_faces: related.map(fn(number) {
        {
          number,
          location: match locations {
            Some(source) => source.faces.get(number)
            None => None
          },
        }
      }),
    })
  }
  let add = fn(rule, face_number, point_ids) {
    emit_face(rule, face_number, point_ids, [])
  }
  for index, point in surface.points {
    let location = locations.map(fn(source) { source.points[index] })
    let add_point = fn(rule) {
      emit({
        rule,
        surface_number,
        surface_name: surface.name,
        face_number: None,
        point_ids: [point.id],
        location,
        related_faces: [],
      })
    }
    if points.contains(point.id) {
      ambiguous[point.id] = true
      add_point(DuplicatePoint)
    } else {
      points[point.id] = point
    }
    if !point_is_finite(point) {
      add_point(NonFinitePoint)
    }
  }
  let mut visible_face_count = 0
  for index, face in surface.faces {
    if face.visible {
      visible_face_count += 1
    }
    let face_number = match face_numbers {
      Some(numbers) => numbers[index]
      None => index + 1
    }
    let number = Some(face_number)
    let (a, b, c) = face.vertices
    let ids = [a, b, c]
    let mut valid = true
    for id in ids {
      if ambiguous.contains(id) {
        add(AmbiguousPoint, number, [id])
        valid = false
      } else if !points.contains(id) {
        add(MissingPoint, number, [id])
        valid = false
      }
    }
    if a == b || b == c || a == c {
      add(RepeatedVertex, number, ids)
      continue
    }
    if valid && face.visible {
      match (points.get(a), points.get(b), points.get(c)) {
        (Some(first), Some(second), Some(third)) =>
          if point_is_finite(first) &&
            point_is_finite(second) &&
            point_is_finite(third) {
            let area = projected_area(first, second, third)
            if area.is_nan() || area.is_inf() {
              add(NonFiniteArea, number, ids)
            } else if area <= area_tolerance {
              add(DegenerateFace, number, ids)
            } else if topology.add_face(face.vertices, face_number, emit_face) {
              geometry.add_face(first, second, third, area)
            }
          }
        _ => ()
      }
    }
  }
  topology.check_edges(emit_face)
  let boundary = topology.check_boundary(emit_face)
  summarize_surface(
    surface,
    surface_number,
    points,
    ambiguous,
    topology,
    visible_face_count,
    boundary,
    geometry.summarize(),
  )
}

///|
fn point_is_finite(point : Point) -> Bool {
  let finite = fn(value : Double) { !value.is_nan() && !value.is_inf() }
  finite(point.northing) && finite(point.easting) && finite(point.elevation)
}

///|
fn projected_area(a : Point, b : Point, c : Point) -> Double {
  let ab_east = b.easting - a.easting
  let ab_north = b.northing - a.northing
  let ac_east = c.easting - a.easting
  let ac_north = c.northing - a.northing
  (ab_east * ac_north - ab_north * ac_east).abs() / 2.0
}
