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
