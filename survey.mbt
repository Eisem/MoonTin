///|
pub(all) struct SurveyPoint {
  id : String
  northing : Double
  easting : Double
  elevation : Double
}

///|
pub(all) enum SurveyStatus {
  Passed
  OutsideTolerance
  Uncovered
}

///|
pub struct SurveyResult {
  point : SurveyPoint
  status : SurveyStatus
  hit_count : Int
  min_elevation : Double?
  max_elevation : Double?
  worst_hit : ElevationHit?
  max_absolute_error : Double?
}

///|
pub struct SurveyReport {
  linear_unit : String?
  tolerance : Double
  passed_count : Int
  outside_tolerance_count : Int
  uncovered_count : Int
  results : Array[SurveyResult]
}

///|
priv struct SurveyHitAccumulator {
  mut count : Int
  mut min_elevation : Double
  mut max_elevation : Double
  mut worst_error : Double
  mut worst_hit : ElevationHit?
}

///|
fn SurveyHitAccumulator::new() -> SurveyHitAccumulator {
  {
    count: 0,
    min_elevation: 0.0,
    max_elevation: 0.0,
    worst_error: 0.0,
    worst_hit: None,
  }
}

///|
fn SurveyHitAccumulator::observe(
  self : SurveyHitAccumulator,
  point : SurveyPoint,
  triangle : SamplingTriangle,
  elevation : Double,
) -> Unit {
  let absolute_error = (elevation - point.elevation).abs()
  if self.count == 0 {
    self.min_elevation = elevation
    self.max_elevation = elevation
  } else {
    self.min_elevation = self.min_elevation.min(elevation)
    self.max_elevation = self.max_elevation.max(elevation)
  }
  if self.count == 0 || absolute_error > self.worst_error {
    self.worst_error = absolute_error
    self.worst_hit = Some({
      surface_number: triangle.surface_number,
      surface_name: triangle.surface_name,
      face_number: triangle.face_number,
      elevation,
      point_ids: [triangle.a.id, triangle.b.id, triangle.c.id],
    })
  }
  self.count += 1
}

///|
fn SurveyHitAccumulator::result(
  self : SurveyHitAccumulator,
  point : SurveyPoint,
  tolerance : Double,
) -> SurveyResult {
  let status = if self.count == 0 {
    Uncovered
  } else if self.worst_error > tolerance {
    OutsideTolerance
  } else {
    Passed
  }
  {
    point,
    status,
    hit_count: self.count,
    min_elevation: if self.count == 0 {
      None
    } else {
      Some(self.min_elevation)
    },
    max_elevation: if self.count == 0 {
      None
    } else {
      Some(self.max_elevation)
    },
    worst_hit: self.worst_hit,
    max_absolute_error: if self.count > 0 &&
      finite_sample_value(self.worst_error) {
      Some(self.worst_error)
    } else {
      None
    },
  }
}

///|
priv struct SurveyIndexEntry {
  coordinate : Double
  point_index : Int
}

///|
fn compare_survey_entry(a : SurveyIndexEntry, b : SurveyIndexEntry) -> Int {
  let coordinate_order = a.coordinate.compare(b.coordinate)
  if coordinate_order == 0 {
    a.point_index.compare(b.point_index)
  } else {
    coordinate_order
  }
}

///|
fn survey_index_bound(
  entries : Array[SurveyIndexEntry],
  coordinate : Double,
  inclusive_upper : Bool,
) -> Int {
  let mut low = 0
  let mut high = entries.length()
  while low < high {
    let middle = low + (high - low) / 2
    let value = entries[middle].coordinate
    if value < coordinate || (inclusive_upper && value == coordinate) {
      low = middle + 1
    } else {
      high = middle
    }
  }
  low
}

///|
fn survey_candidate_points(
  triangle : SamplingTriangle,
  northing_index : Array[SurveyIndexEntry],
  easting_index : Array[SurveyIndexEntry],
) -> ArrayView[SurveyIndexEntry] {
  let a = triangle.a
  let b = triangle.b
  let c = triangle.c
  let north_start = survey_index_bound(
    northing_index,
    a.northing.min(b.northing).min(c.northing),
    false,
  )
  let north_end = survey_index_bound(
    northing_index,
    a.northing.max(b.northing).max(c.northing),
    true,
  )
  let east_start = survey_index_bound(
    easting_index,
    a.easting.min(b.easting).min(c.easting),
    false,
  )
  let east_end = survey_index_bound(
    easting_index,
    a.easting.max(b.easting).max(c.easting),
    true,
  )
  if north_end - north_start <= east_end - east_start {
    northing_index[north_start:north_end]
  } else {
    easting_index[east_start:east_end]
  }
}

///|
/// Checks measured elevations against every covering visible triangle.
/// A point passes if all hits are within the absolute elevation tolerance.
pub fn check_survey_points(
  terrain : Terrain,
  points : ArrayView[SurveyPoint],
  tolerance : Double,
  surface_name? : String,
) -> SurveyReport raise SamplingError {
  if tolerance < 0.0 || !finite_sample_value(tolerance) {
    raise InvalidSample("survey tolerance must be finite and nonnegative")
  }
  if points.is_empty() {
    raise InvalidSample("at least one survey point is required")
  }
  let ids = Map([])
  let northing_index : Array[SurveyIndexEntry] = []
  let easting_index : Array[SurveyIndexEntry] = []
  let hits = []
  for index, point in points {
    if point.id.trim().is_empty() || ids.contains(point.id) {
      raise InvalidSample(
        "survey point #\{index + 1}: ID is blank or duplicated",
      )
    }
    if !finite_sample_value(point.northing) ||
      !finite_sample_value(point.easting) ||
      !finite_sample_value(point.elevation) {
      raise InvalidSample(
        "survey point '\{point.id}': coordinates must be finite",
      )
    }
    ids[point.id] = true
    northing_index.push({ coordinate: point.northing, point_index: index, })
    easting_index.push({ coordinate: point.easting, point_index: index, })
    hits.push(SurveyHitAccumulator::new())
  }
  northing_index.sort_by(compare_survey_entry)
  easting_index.sort_by(compare_survey_entry)
  each_visible_triangle(terrain, surface_name, fn(triangle) {
    for
      candidate in survey_candidate_points(
        triangle, northing_index, easting_index,
      ) {
      let index = candidate.point_index
      let point = points[index]
      if barycentric_elevation(
          triangle.a,
          triangle.b,
          triangle.c,
          point.northing,
          point.easting,
        )
        is Some(elevation) {
        hits[index].observe(point, triangle, elevation)
      }
    }
  })
  let mut passed_count = 0
  let mut outside_tolerance_count = 0
  let mut uncovered_count = 0
  let results = []
  for index, point in points {
    let result = hits[index].result(point, tolerance)
    match result.status {
      Passed => passed_count += 1
      OutsideTolerance => outside_tolerance_count += 1
      Uncovered => uncovered_count += 1
    }
    results.push(result)
  }
  {
    linear_unit: terrain.linear_unit,
    tolerance,
    passed_count,
    outside_tolerance_count,
    uncovered_count,
    results,
  }
}

///|
pub fn SurveyStatus::label(self : SurveyStatus) -> String {
  match self {
    Passed => "passed"
    OutsideTolerance => "outside_tolerance"
    Uncovered => "uncovered"
  }
}

///|
pub fn SurveyReport::passed(self : SurveyReport) -> Bool {
  self.outside_tolerance_count == 0 && self.uncovered_count == 0
}

///|
pub fn SurveyResult::to_json(self : SurveyResult) -> Json {
  {
    "id": self.point.id.to_json(),
    "northing": self.point.northing.to_json(),
    "easting": self.point.easting.to_json(),
    "measured_elevation": self.point.elevation.to_json(),
    "status": self.status.label().to_json(),
    "hit_count": self.hit_count.to_json(),
    "min_elevation": metric_json(self.min_elevation),
    "max_elevation": metric_json(self.max_elevation),
    "max_absolute_error": metric_json(self.max_absolute_error),
    "worst_hit": match self.worst_hit {
      Some(hit) => hit.to_json()
      None => Json::null()
    },
  }
}

///|
pub fn SurveyReport::to_json(self : SurveyReport) -> Json {
  {
    "schema_version": 1,
    "passed": self.passed().to_json(),
    "linear_unit": match self.linear_unit {
      Some(unit) => unit.to_json()
      None => Json::null()
    },
    "tolerance": self.tolerance.to_json(),
    "passed_count": self.passed_count.to_json(),
    "outside_tolerance_count": self.outside_tolerance_count.to_json(),
    "uncovered_count": self.uncovered_count.to_json(),
    "results": self.results.map(fn(result) { result.to_json() }).to_json(),
  }
}
