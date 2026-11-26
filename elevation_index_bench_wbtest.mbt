///|
fn bench_grid_point_id(row : Int, column : Int) -> String {
  "\{row}/\{column}"
}

///|
fn bench_elevation_terrain(size : Int) -> Terrain {
  let points : Array[Point] = []
  let faces : Array[Face] = []
  for row in 0..<size {
    for column in 0..<size {
      points.push({
        id: bench_grid_point_id(row, column),
        northing: row.to_double(),
        easting: column.to_double(),
        elevation: (2 * row + column).to_double(),
      })
    }
  }
  for row in 0..<(size - 1) {
    for column in 0..<(size - 1) {
      let a = bench_grid_point_id(row, column)
      let b = bench_grid_point_id(row, column + 1)
      let c = bench_grid_point_id(row + 1, column)
      let d = bench_grid_point_id(row + 1, column + 1)
      faces.push({ vertices: (a, b, c), visible: true, })
      faces.push({ vertices: (c, b, d), visible: true, })
    }
  }
  {
    linear_unit: Some("meter"),
    surfaces: [{ name: "Synthetic grid", points, faces, }],
  }
}

///|
test "elevation index on a 100 by 100 TIN" (bench : @bench.T) {
  let terrain = bench_elevation_terrain(100)
  let index = build_elevation_index(terrain)
  let queries = Array::makei(100, fn(i) {
    ((37 * i % 99).to_double() + 0.25, (61 * i % 99).to_double() + 0.25)
  })
  bench.bench(name="Build index", fn() {
    let built = try! build_elevation_index(terrain)
    bench.keep(built)
  })
  bench.bench(name="100 direct queries", fn() {
    for query in queries {
      let (north, east) = query
      let result = try! sample_elevation(terrain, north, east)
      bench.keep(result)
    }
  })
  bench.bench(name="100 indexed queries", fn() {
    for query in queries {
      let (north, east) = query
      let result = try! index.sample(north, east)
      bench.keep(result)
    }
  })
}
