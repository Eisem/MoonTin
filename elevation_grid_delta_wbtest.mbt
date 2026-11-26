///|
fn delta_fixture(origin : Double, heights : Array[Double]) -> Terrain {
  let surfaces : Array[Surface] = []
  for number, height in heights {
    surfaces.push({
      name: "Surface \{number + 1}",
      points: [
        { id: "a", northing: origin, easting: 0.0, elevation: height, },
        { id: "b", northing: origin, easting: 1.0, elevation: height, },
        { id: "c", northing: origin + 1.0, easting: 0.0, elevation: height, },
      ],
      faces: [{ vertices: ("a", "b", "c"), visible: true, }],
    })
  }
  { linear_unit: Some("meter"), surfaces, }
}

///|
fn delta_test_grid() -> ElevationGridSpec {
  {
    northing: 0.25,
    easting: 0.25,
    rows: 3,
    columns: 1,
    north_step: 1.0,
    east_step: 1.0,
  }
}

///|
test "overlapping faces produce a delta interval with unresolved direction" {
  let before = build_elevation_index(delta_fixture(0.0, [1.0, 3.0]))
  let after = build_elevation_index(delta_fixture(0.0, [2.0]))
  let report = compare_elevation_grids(
    before,
    after,
    delta_test_grid(),
    tolerance=0.5,
  )
  assert_eq(report.counts.ambiguous, 1)
  assert_eq(report.counts.no_coverage, 2)
  assert_eq(report.cells[0].min_delta, Some(-1.0))
  assert_eq(report.cells[0].max_delta, Some(1.0))
  assert_true(report.needs_review())
  assert_false(
    compare_elevation_grids(before, after, delta_test_grid(), tolerance=1.0).needs_review(),
  )
}

///|
test "coverage added and lost are distinct from zero elevation difference" {
  let before = build_elevation_index(delta_fixture(0.0, [0.0]))
  let after = build_elevation_index(delta_fixture(1.0, [0.0]))
  let report = compare_elevation_grids(before, after, delta_test_grid())
  let summary = summarize_elevation_grid_delta(before, after, delta_test_grid())
  assert_eq(summary.to_json().stringify(), report.counts.to_json().stringify())
  assert_true(summary.needs_review())
  assert_eq(report.counts.coverage_lost, 1)
  assert_eq(report.counts.coverage_added, 1)
  assert_eq(report.counts.no_coverage, 1)
  assert_eq(report.cells[0].min_delta, None)
  assert_eq(report.cells[1].max_delta, None)
}
