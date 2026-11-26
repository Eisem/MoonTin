///|
/// The first node is at (northing, easting). Positive steps increase the
/// corresponding coordinate as rows and columns advance.
pub(all) struct ElevationGridSpec {
  northing : Double
  easting : Double
  rows : Int
  columns : Int
  north_step : Double
  east_step : Double
}

///|
pub struct ElevationGridCell {
  row : Int
  column : Int
  northing : Double
  easting : Double
  hit_count : Int
  min_elevation : Double?
  max_elevation : Double?
}

///|
pub struct ElevationGrid {
  spec : ElevationGridSpec
  linear_unit : String?
  covered_cells : Int
  uncovered_cells : Int
  overlapping_cells : Int
  cells : Array[ElevationGridCell]
}

///|
fn check_grid_spec(spec : ElevationGridSpec) -> Unit raise SamplingError {
  if spec.rows < 1 || spec.columns < 1 || spec.rows > 100000 / spec.columns {
    raise InvalidSample(
      "grid dimensions must define between 1 and 100000 nodes",
    )
  }
  if !finite_sample_value(spec.northing) ||
    !finite_sample_value(spec.easting) ||
    !finite_sample_value(spec.north_step) ||
    !finite_sample_value(spec.east_step) ||
    spec.north_step <= 0.0 ||
    spec.east_step <= 0.0 {
    raise InvalidSample(
      "grid origin must be finite and spacing must be finite and positive",
    )
  }
  let last_north = spec.northing + (spec.rows - 1).to_double() * spec.north_step
  let last_east = spec.easting + (spec.columns - 1).to_double() * spec.east_step
  if !finite_sample_value(last_north) || !finite_sample_value(last_east) {
    raise InvalidSample("grid coordinates exceed numeric range")
  }
}

///|
fn ElevationGridSpec::visit_nodes(
  self : ElevationGridSpec,
  visit : (Int, Int, Double, Double) -> Unit raise SamplingError,
) -> Unit raise SamplingError {
  for row in 0..<self.rows {
    let northing = self.northing + row.to_double() * self.north_step
    for column in 0..<self.columns {
      let easting = self.easting + column.to_double() * self.east_step
      visit(row, column, northing, easting)
    }
  }
}

///|
fn ElevationIndex::sample_grid_cell(
  self : ElevationIndex,
  row : Int,
  column : Int,
  northing : Double,
  easting : Double,
) -> ElevationGridCell {
  let mut hit_count = 0
  let mut minimum = 0.0
  let mut maximum = 0.0
  if self.root is Some(root) {
    root.visit_hits(northing, easting, fn(_, elevation) {
      if hit_count == 0 {
        minimum = elevation
        maximum = elevation
      } else {
        minimum = minimum.min(elevation)
        maximum = maximum.max(elevation)
      }
      hit_count += 1
    })
  }
  {
    row,
    column,
    northing,
    easting,
    hit_count,
    min_elevation: if hit_count == 0 {
      None
    } else {
      Some(minimum)
    },
    max_elevation: if hit_count == 0 {
      None
    } else {
      Some(maximum)
    },
  }
}

///|
/// Samples grid nodes in row-major order. When multiple faces cover a node,
/// the result retains the elevation range and the full number of hits.
pub fn ElevationIndex::sample_grid(
  self : ElevationIndex,
  spec : ElevationGridSpec,
) -> ElevationGrid raise SamplingError {
  check_grid_spec(spec)
  let cells = Array(capacity=spec.rows * spec.columns)
  let mut covered_cells = 0
  let mut overlapping_cells = 0
  spec.visit_nodes(fn(row, column, northing, easting) {
    let cell = self.sample_grid_cell(row, column, northing, easting)
    if cell.hit_count > 0 {
      covered_cells += 1
      if cell.hit_count > 1 {
        overlapping_cells += 1
      }
    }
    cells.push(cell)
  })
  {
    spec,
    linear_unit: self.linear_unit,
    covered_cells,
    uncovered_cells: cells.length() - covered_cells,
    overlapping_cells,
    cells,
  }
}

///|
pub fn ElevationGridSpec::to_json(self : ElevationGridSpec) -> Json {
  {
    "northing": ToJson::to_json(self.northing),
    "easting": ToJson::to_json(self.easting),
    "rows": ToJson::to_json(self.rows),
    "columns": ToJson::to_json(self.columns),
    "north_step": ToJson::to_json(self.north_step),
    "east_step": ToJson::to_json(self.east_step),
  }
}

///|
pub fn ElevationGridCell::to_json(self : ElevationGridCell) -> Json {
  {
    "row": ToJson::to_json(self.row),
    "column": ToJson::to_json(self.column),
    "northing": ToJson::to_json(self.northing),
    "easting": ToJson::to_json(self.easting),
    "hit_count": ToJson::to_json(self.hit_count),
    "min_elevation": metric_json(self.min_elevation),
    "max_elevation": metric_json(self.max_elevation),
  }
}

///|
pub fn ElevationGrid::to_json(self : ElevationGrid) -> Json {
  {
    "schema_version": 1,
    "grid": self.spec.to_json(),
    "linear_unit": match self.linear_unit {
      Some(unit) => ToJson::to_json(unit)
      None => Json::null()
    },
    "covered_cells": ToJson::to_json(self.covered_cells),
    "uncovered_cells": ToJson::to_json(self.uncovered_cells),
    "overlapping_cells": ToJson::to_json(self.overlapping_cells),
    "cells": ToJson::to_json(self.cells.map(fn(cell) { cell.to_json() })),
  }
}
