///|
pub(all) enum GridChange {
  Raised
  Lowered
  WithinTolerance
  Ambiguous
  CoverageAdded
  CoverageLost
  NoCoverage
}

///|
pub struct ElevationGridDeltaCell {
  before : ElevationGridCell
  after : ElevationGridCell
  change : GridChange
  min_delta : Double?
  max_delta : Double?
}

///|
pub struct GridChangeCounts {
  raised : Int32
  lowered : Int32
  within_tolerance : Int32
  ambiguous : Int32
  coverage_added : Int32
  coverage_lost : Int32
  no_coverage : Int32
}

///|
pub struct ElevationGridDelta {
  spec : ElevationGridSpec
  linear_unit : String?
  tolerance : Double
  counts : GridChangeCounts
  cells : Array[ElevationGridDeltaCell]
}

///|
fn compare_grid_cell(
  before : ElevationGridCell,
  after : ElevationGridCell,
  tolerance : Double,
) -> ElevationGridDeltaCell raise SamplingError {
  match
    (
      before.min_elevation,
      before.max_elevation,
      after.min_elevation,
      after.max_elevation,
    ) {
    (Some(old_low), Some(old_high), Some(new_low), Some(new_high)) => {
      let minimum = new_low - old_high
      let maximum = new_high - old_low
      if !finite_sample_value(minimum) || !finite_sample_value(maximum) {
        raise InvalidSample(
          "grid elevation change exceeds numeric range at row \{before.row}, column \{before.column}",
        )
      }
      let change = if minimum > tolerance {
        Raised
      } else if maximum < -tolerance {
        Lowered
      } else if minimum >= -tolerance && maximum <= tolerance {
        WithinTolerance
      } else {
        Ambiguous
      }
      {
        before,
        after,
        change,
        min_delta: Some(minimum),
        max_delta: Some(maximum),
      }
    }
    (old_min, _, new_min, _) => {
      let change = match (old_min, new_min) {
        (None, Some(_)) => CoverageAdded
        (Some(_), None) => CoverageLost
        _ => NoCoverage
      }
      { before, after, change, min_delta: None, max_delta: None, }
    }
  }
}

///|
fn visit_grid_changes(
  before : ElevationIndex,
  after : ElevationIndex,
  spec : ElevationGridSpec,
  tolerance : Double,
  visit : (ElevationGridDeltaCell) -> Unit,
) -> GridChangeCounts raise SamplingError {
  let mut raised = 0
  let mut lowered = 0
  let mut within_tolerance = 0
  let mut ambiguous = 0
  let mut coverage_added = 0
  let mut coverage_lost = 0
  let mut no_coverage = 0
  spec.visit_nodes(fn(
    row,
    column,
    northing,
    easting,
  ) -> Unit raise SamplingError {
    let old_cell = before.sample_grid_cell(row, column, northing, easting)
    let new_cell = after.sample_grid_cell(row, column, northing, easting)
    let cell = compare_grid_cell(old_cell, new_cell, tolerance)
    visit(cell)
    match cell.change {
      Raised => raised += 1
      Lowered => lowered += 1
      WithinTolerance => within_tolerance += 1
      Ambiguous => ambiguous += 1
      CoverageAdded => coverage_added += 1
      CoverageLost => coverage_lost += 1
      NoCoverage => no_coverage += 1
    }
  })
  {
    raised,
    lowered,
    within_tolerance,
    ambiguous,
    coverage_added,
    coverage_lost,
    no_coverage,
  }
}

///|
/// Compares elevations on an identical grid in two index snapshots.
/// Deltas are after minus before. At a multiply covered node the reported
/// interval includes all pairwise differences between the two versions.
pub fn compare_elevation_grids(
  before : ElevationIndex,
  after : ElevationIndex,
  spec : ElevationGridSpec,
  tolerance~ : Double = 0.0,
) -> ElevationGridDelta raise SamplingError {
  validate_grid_comparison(before, after, spec, tolerance)
  let cells = Array(capacity=spec.rows * spec.columns)
  let counts = visit_grid_changes(before, after, spec, tolerance, fn(cell) {
    cells.push(cell)
  })
  { spec, linear_unit: before.linear_unit, tolerance, counts, cells, }
}

///|
/// Compares grid coverage and elevation without retaining per-node details.
pub fn summarize_elevation_grid_delta(
  before : ElevationIndex,
  after : ElevationIndex,
  spec : ElevationGridSpec,
  tolerance~ : Double = 0.0,
) -> GridChangeCounts raise SamplingError {
  validate_grid_comparison(before, after, spec, tolerance)
  visit_grid_changes(before, after, spec, tolerance, fn(_) { () })
}

///|
/// Visits compared nodes in row-major order without retaining the complete
/// report. An error can occur after earlier nodes have been delivered.
pub fn visit_elevation_grid_delta(
  before : ElevationIndex,
  after : ElevationIndex,
  spec : ElevationGridSpec,
  on_cell : (ElevationGridDeltaCell) -> Unit,
  tolerance~ : Double = 0.0,
) -> GridChangeCounts raise SamplingError {
  validate_grid_comparison(before, after, spec, tolerance)
  visit_grid_changes(before, after, spec, tolerance, on_cell)
}

///|
fn validate_grid_comparison(
  before : ElevationIndex,
  after : ElevationIndex,
  spec : ElevationGridSpec,
  tolerance : Double,
) -> Unit raise SamplingError {
  if before.linear_unit != after.linear_unit {
    raise InvalidSample(
      "grid comparison requires the same linear unit in both revisions",
    )
  }
  if !finite_sample_value(tolerance) || tolerance < 0.0 {
    raise InvalidSample(
      "grid comparison tolerance must be finite and nonnegative",
    )
  }
  check_grid_spec(spec)
}

///|
pub fn GridChange::label(self : GridChange) -> String {
  match self {
    Raised => "raised"
    Lowered => "lowered"
    WithinTolerance => "within_tolerance"
    Ambiguous => "ambiguous"
    CoverageAdded => "coverage_added"
    CoverageLost => "coverage_lost"
    NoCoverage => "no_coverage"
  }
}

///|
/// Reports differences that merit review, including unresolved overlaps.
pub fn ElevationGridDelta::needs_review(self : ElevationGridDelta) -> Bool {
  self.counts.needs_review()
}

///|
pub fn GridChangeCounts::needs_review(self : GridChangeCounts) -> Bool {
  let counts = self
  counts.raised +
  counts.lowered +
  counts.ambiguous +
  counts.coverage_added +
  counts.coverage_lost >
  0
}

///|
pub fn GridChangeCounts::to_json(self : GridChangeCounts) -> Json {
  {
    "raised": ToJson::to_json(self.raised),
    "lowered": ToJson::to_json(self.lowered),
    "within_tolerance": ToJson::to_json(self.within_tolerance),
    "ambiguous": ToJson::to_json(self.ambiguous),
    "coverage_added": ToJson::to_json(self.coverage_added),
    "coverage_lost": ToJson::to_json(self.coverage_lost),
    "no_coverage": ToJson::to_json(self.no_coverage),
  }
}

///|
pub fn ElevationGridDeltaCell::to_json(self : ElevationGridDeltaCell) -> Json {
  {
    "row": ToJson::to_json(self.before.row),
    "column": ToJson::to_json(self.before.column),
    "northing": ToJson::to_json(self.before.northing),
    "easting": ToJson::to_json(self.before.easting),
    "change": ToJson::to_json(self.change.label()),
    "before_hits": ToJson::to_json(self.before.hit_count),
    "after_hits": ToJson::to_json(self.after.hit_count),
    "before_min_elevation": metric_json(self.before.min_elevation),
    "before_max_elevation": metric_json(self.before.max_elevation),
    "after_min_elevation": metric_json(self.after.min_elevation),
    "after_max_elevation": metric_json(self.after.max_elevation),
    "min_delta": metric_json(self.min_delta),
    "max_delta": metric_json(self.max_delta),
  }
}

///|
pub fn ElevationGridDelta::to_json(self : ElevationGridDelta) -> Json {
  {
    "schema_version": 1,
    "grid": self.spec.to_json(),
    "linear_unit": match self.linear_unit {
      Some(unit) => ToJson::to_json(unit)
      None => Json::null()
    },
    "tolerance": ToJson::to_json(self.tolerance),
    "needs_review": ToJson::to_json(self.needs_review()),
    "counts": self.counts.to_json(),
    "cells": ToJson::to_json(self.cells.map(fn(cell) { cell.to_json() })),
  }
}
