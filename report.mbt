///|
pub struct Bounds {
  min_northing : Double
  max_northing : Double
  min_easting : Double
  max_easting : Double
  min_elevation : Double
  max_elevation : Double
}

///|
pub impl ToJson for Bounds with fn to_json(self) {
  {
    "min_northing": ToJson::to_json(self.min_northing),
    "max_northing": ToJson::to_json(self.max_northing),
    "min_easting": ToJson::to_json(self.min_easting),
    "max_easting": ToJson::to_json(self.max_easting),
    "min_elevation": ToJson::to_json(self.min_elevation),
    "max_elevation": ToJson::to_json(self.max_elevation),
  }
}

///|
pub extend Bounds with ToJson::{to_json}

///|
pub struct SurfaceSummary {
  surface_number : Int
  name : String
  decoded_points : Int
  decoded_faces : Int
  invisible_faces : Int
  indexed_faces : Int
  skipped_visible_faces : Int
  usable_points : Int
  boundary_edges : Int
  boundary_loops : Int
  branched_boundaries : Int
  connected_components : Int
  bounds : Bounds?
  geometry : FaceGeometry
}

///|
fn summarize_surface(
  surface : Surface,
  surface_number : Int,
  points : Map[String, Point],
  ambiguous : Map[String, Bool],
  topology : SurfaceTopology,
  visible_face_count : Int,
  boundary : BoundarySummary,
  geometry : FaceGeometry,
) -> SurfaceSummary {
  let mut bounds : Bounds? = None
  let mut usable_points = 0
  points.each(fn(id, point) {
    if !ambiguous.contains(id) && point_is_finite(point) {
      usable_points += 1
      bounds = Some(
        match bounds {
          None =>
            {
              min_northing: point.northing,
              max_northing: point.northing,
              min_easting: point.easting,
              max_easting: point.easting,
              min_elevation: point.elevation,
              max_elevation: point.elevation,
            }
          Some(previous) =>
            {
              min_northing: previous.min_northing.min(point.northing),
              max_northing: previous.max_northing.max(point.northing),
              min_easting: previous.min_easting.min(point.easting),
              max_easting: previous.max_easting.max(point.easting),
              min_elevation: previous.min_elevation.min(point.elevation),
              max_elevation: previous.max_elevation.max(point.elevation),
            }
        },
      )
    }
  })
  let (boundary_edges, connected_components) = topology.summarize()
  {
    surface_number,
    name: surface.name,
    decoded_points: surface.points.length(),
    decoded_faces: surface.faces.length(),
    invisible_faces: surface.faces.length() - visible_face_count,
    indexed_faces: topology.faces.length(),
    skipped_visible_faces: visible_face_count - topology.faces.length(),
    usable_points,
    boundary_edges,
    boundary_loops: boundary.closed_loops,
    branched_boundaries: boundary.branched_components,
    connected_components,
    bounds,
    geometry,
  }
}

///|
pub fn SurfaceSummary::to_json(self : SurfaceSummary) -> Json {
  {
    "surface_number": ToJson::to_json(self.surface_number),
    "name": ToJson::to_json(self.name),
    "decoded_points": ToJson::to_json(self.decoded_points),
    "decoded_faces": ToJson::to_json(self.decoded_faces),
    "invisible_faces": ToJson::to_json(self.invisible_faces),
    "indexed_faces": ToJson::to_json(self.indexed_faces),
    "skipped_visible_faces": ToJson::to_json(self.skipped_visible_faces),
    "usable_points": ToJson::to_json(self.usable_points),
    "boundary_edges": ToJson::to_json(self.boundary_edges),
    "boundary_loops": ToJson::to_json(self.boundary_loops),
    "branched_boundaries": ToJson::to_json(self.branched_boundaries),
    "connected_components": ToJson::to_json(self.connected_components),
    "geometry": self.geometry.to_json(),
    "bounds": match self.bounds {
      Some(bounds) => ToJson::to_json(bounds)
      None => Json::null()
    },
  }
}

///|
pub(all) enum Severity {
  Error
  Warning
}

///|
pub struct CheckReport {
  surfaces : Array[SurfaceSummary]
  linear_unit : String?
  area_tolerance : Double
  strict : Bool
  error_count : Int
  warning_count : Int
  truncated : Bool
  record_issues : Array[RecordIssue]
  diagnostics : Array[Diagnostic]
}

///|
pub fn check(
  source : String,
  area_tolerance? : Double = 0.0,
  strict? : Bool = false,
  max_diagnostics? : Int = 1000,
  max_records? : Int = 500000,
) -> CheckReport raise {
  if max_records <= 0 {
    raise InvalidLandXml("record limit must be positive")
  }
  if max_diagnostics < 0 {
    raise InvalidLandXml("diagnostic limit must be nonnegative")
  }
  if area_tolerance < 0.0 || area_tolerance.is_nan() || area_tolerance.is_inf() {
    raise InvalidLandXml("area tolerance must be finite and nonnegative")
  }
  let record_issues = []
  let diagnostics = []
  let mut error_count = 0
  let mut warning_count = 0
  let (terrain, face_numbers, surface_numbers, locations) = decode_records(
    source,
    max_records,
    fn(issue) {
      match issue.severity {
        Error => error_count += 1
        Warning => warning_count += 1
      }
      if record_issues.length() < max_diagnostics {
        record_issues.push(issue)
      }
    },
  )
  let surfaces = []
  terrain.surfaces.eachi(fn(index, surface) {
    surfaces.push(
      validate_surface(
        surface,
        surface_numbers[index],
        area_tolerance,
        fn(issue) {
          error_count += 1
          if record_issues.length() + diagnostics.length() < max_diagnostics {
            diagnostics.push(issue)
          }
        },
        Some(face_numbers[index]),
        Some(locations[index]),
      ),
    )
  })
  {
    surfaces,
    linear_unit: terrain.linear_unit,
    area_tolerance,
    strict,
    error_count,
    warning_count,
    truncated: error_count + warning_count >
    record_issues.length() + diagnostics.length(),
    record_issues,
    diagnostics,
  }
}

///|
pub fn CheckReport::passed(self : CheckReport) -> Bool {
  self.error_count == 0 && (!self.strict || self.warning_count == 0)
}

///|
pub fn Severity::label(self : Severity) -> String {
  match self {
    Error => "error"
    Warning => "warning"
  }
}

///|
pub fn RecordIssue::to_json(self : RecordIssue) -> Json {
  {
    "surface_number": ToJson::to_json(self.surface_number),
    "surface_name": ToJson::to_json(self.surface_name),
    "code": ToJson::to_json(self.code),
    "record_kind": ToJson::to_json(self.record_kind),
    "record_number": ToJson::to_json(self.record_number),
    "message": ToJson::to_json(self.message),
    "severity": ToJson::to_json(self.severity.label()),
    "location": self.location.to_json(),
  }
}

///|
pub fn CheckReport::to_json(self : CheckReport) -> Json {
  {
    "schema_version": 1,
    "status": ToJson::to_json(if self.passed() { "passed" } else { "failed" }),
    "linear_unit": match self.linear_unit {
      Some(unit) => ToJson::to_json(unit)
      None => Json::null()
    },
    "area_tolerance": ToJson::to_json(self.area_tolerance),
    "strict": ToJson::to_json(self.strict),
    "error_count": ToJson::to_json(self.error_count),
    "warning_count": ToJson::to_json(self.warning_count),
    "truncated": ToJson::to_json(self.truncated),
    "surface_count": ToJson::to_json(self.surfaces.length()),
    "surfaces": ToJson::to_json(self.surfaces.map(fn(item) { item.to_json() })),
    "record_issues": ToJson::to_json(
      self.record_issues.map(fn(item) { item.to_json() }),
    ),
    "diagnostics": ToJson::to_json(
      self.diagnostics.map(fn(item) { item.to_json() }),
    ),
  }
}
