///|
pub struct Bounds {
  min_northing : Double
  max_northing : Double
  min_easting : Double
  max_easting : Double
  min_elevation : Double
  max_elevation : Double
} derive(ToJson)

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
  }
}

///|
pub fn SurfaceSummary::to_json(self : SurfaceSummary) -> Json {
  {
    "surface_number": self.surface_number.to_json(),
    "name": self.name.to_json(),
    "decoded_points": self.decoded_points.to_json(),
    "decoded_faces": self.decoded_faces.to_json(),
    "invisible_faces": self.invisible_faces.to_json(),
    "indexed_faces": self.indexed_faces.to_json(),
    "skipped_visible_faces": self.skipped_visible_faces.to_json(),
    "usable_points": self.usable_points.to_json(),
    "boundary_edges": self.boundary_edges.to_json(),
    "boundary_loops": self.boundary_loops.to_json(),
    "branched_boundaries": self.branched_boundaries.to_json(),
    "connected_components": self.connected_components.to_json(),
    "bounds": match self.bounds {
      Some(bounds) => bounds.to_json()
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
    "surface_number": self.surface_number.to_json(),
    "surface_name": self.surface_name.to_json(),
    "code": self.code.to_json(),
    "record_kind": self.record_kind.to_json(),
    "record_number": self.record_number.to_json(),
    "message": self.message.to_json(),
    "severity": self.severity.label().to_json(),
    "location": self.location.to_json(),
  }
}

///|
pub fn CheckReport::to_json(self : CheckReport) -> Json {
  {
    "schema_version": 1,
    "status": (if self.passed() { "passed" } else { "failed" }).to_json(),
    "linear_unit": match self.linear_unit {
      Some(unit) => unit.to_json()
      None => Json::null()
    },
    "area_tolerance": self.area_tolerance.to_json(),
    "strict": self.strict.to_json(),
    "error_count": self.error_count.to_json(),
    "warning_count": self.warning_count.to_json(),
    "truncated": self.truncated.to_json(),
    "surface_count": self.surfaces.length().to_json(),
    "surfaces": self.surfaces.map(fn(item) { item.to_json() }).to_json(),
    "record_issues": self.record_issues
    .map(fn(item) { item.to_json() })
    .to_json(),
    "diagnostics": self.diagnostics.map(fn(item) { item.to_json() }).to_json(),
  }
}
