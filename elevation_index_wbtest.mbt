///|
test "hierarchical elevation queries match the scan across leaves and shared edges" {
  let points : Array[Point] = []
  let faces : Array[Face] = []
  for strip in 0..<20 {
    let east = strip.to_double()
    points.push({
      id: "a\{strip}",
      northing: 0.0,
      easting: east,
      elevation: east,
    })
    points.push({
      id: "b\{strip}",
      northing: 1.0,
      easting: east,
      elevation: east + 2.0,
    })
    points.push({
      id: "c\{strip}",
      northing: 0.0,
      easting: east + 1.0,
      elevation: east + 1.0,
    })
    faces.push({
      vertices: ("a\{strip}", "b\{strip}", "c\{strip}"),
      visible: strip != 6,
    })
  }
  let surface : Surface = { name: "Ground", points, faces, }
  let terrain : Terrain = {
    linear_unit: Some("meter"),
    surfaces: [surface, { ..surface, name: "Overlay", }],
  }
  let indexed = build_elevation_index(terrain)
  assert_eq(indexed.triangle_count, 38)
  for strip in -1..<21 {
    let east = strip.to_double()
    for offset in [0.0, 0.25, 0.75] {
      let expected = sample_elevation(terrain, 0.25, east + offset)
      let actual = indexed.sample(0.25, east + offset)
      assert_eq(actual.to_json().stringify(), expected.to_json().stringify())
    }
  }
  assert_eq(
    build_elevation_index(terrain, surface_name="Overlay").sample(0.25, 1.25).hits[0].surface_number,
    2,
  )
}
