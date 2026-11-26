///|
fn grid_dimension(axis : String, value : String) -> Int raise {
  @string.parse_int(value[:]) catch {
    _ => raise InvalidOption("invalid grid \{axis}: \{value}")
  }
}

///|
fn parse_grid_spec(
  north : String,
  east : String,
  rows : String,
  columns : String,
  north_step : String,
  east_step : String,
) -> @moontin.ElevationGridSpec raise {
  {
    northing: query_coordinate("grid northing", north),
    easting: query_coordinate("grid easting", east),
    rows: grid_dimension("row count", rows),
    columns: grid_dimension("column count", columns),
    north_step: query_coordinate("northing spacing", north_step),
    east_step: query_coordinate("easting spacing", east_step),
  }
}

///|
async fn grid_file(
  path : String,
  spec : @moontin.ElevationGridSpec,
  options : SampleOptions,
) -> Int {
  let terrain = @moontin.parse(read_input(path, 16 * 1024 * 1024))
  let index = @moontin.build_elevation_index(
    terrain,
    surface_name?=options.surface,
  )
  let grid = index.sample_grid(spec)
  if options.json {
    println(grid.to_json().stringify())
  } else {
    println(
      "Grid: \{grid.covered_cells} covered, \{grid.uncovered_cells} uncovered, \{grid.overlapping_cells} with multiple triangle hits.",
    )
  }
  if grid.covered_cells == 0 {
    1
  } else {
    0
  }
}

///|
async fn grid_diff_files(
  before_path : String,
  after_path : String,
  spec : @moontin.ElevationGridSpec,
  tolerance : Double,
  options : SampleOptions,
) -> Int {
  let before = @moontin.parse(read_input(before_path, 16 * 1024 * 1024))
  let after = @moontin.parse(read_input(after_path, 16 * 1024 * 1024))
  let before_index = @moontin.build_elevation_index(
    before,
    surface_name?=options.surface,
  )
  let after_index = @moontin.build_elevation_index(
    after,
    surface_name?=options.surface,
  )
  let review = if options.json {
    let report = @moontin.compare_elevation_grids(
      before_index,
      after_index,
      spec,
      tolerance~,
    )
    println(report.to_json().stringify())
    report.needs_review()
  } else {
    let counts = @moontin.summarize_elevation_grid_delta(
      before_index,
      after_index,
      spec,
      tolerance~,
    )
    println(
      "Elevations: \{counts.raised} raised, \{counts.lowered} lowered, \{counts.within_tolerance} within tolerance, \{counts.ambiguous} ambiguous.",
    )
    println(
      "Coverage: \{counts.coverage_added} added, \{counts.coverage_lost} lost, \{counts.no_coverage} uncovered in both revisions.",
    )
    counts.needs_review()
  }
  if review {
    1
  } else {
    0
  }
}
