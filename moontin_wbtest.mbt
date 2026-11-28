///|
fn sample_terrain(
  vertices : (String, String, String),
  visible~ : Bool = true,
) -> Terrain {
  {
    linear_unit: Some("meter"),
    surfaces: [
      {
        name: "Existing Ground",
        points: [
          { id: "01", northing: 100.0, easting: 200.0, elevation: 10.0, },
          { id: "2", northing: 100.0, easting: 201.0, elevation: 11.0, },
          { id: "3", northing: 101.0, easting: 200.0, elevation: 12.0, },
        ],
        faces: [{ vertices, visible, }],
      },
    ],
  }
}

///|
test "accepts a valid surface and preserves leading zeroes" {
  assert_true(validate(sample_terrain(("01", "2", "3"))).is_empty())
}

///|
test "reports missing point with the surface and face number" {
  let diagnostics = validate(sample_terrain(("1", "2", "3")))
  assert_eq(diagnostics.length(), 1)
  assert_true(diagnostics[0].rule is MissingPoint)
  assert_eq(diagnostics[0].surface_name, "Existing Ground")
  assert_eq(diagnostics[0].face_number, Some(1))
  assert_eq(diagnostics[0].point_ids, ["1"])
}

///|
test "reports small projected areas only on visible faces" {
  let diagnostics = validate(
    sample_terrain(("01", "2", "3")),
    area_tolerance=0.5,
  )
  assert_eq(diagnostics.length(), 1)
  assert_true(diagnostics[0].rule is DegenerateFace)
  let hidden = sample_terrain(("01", "2", "3"), visible=false)
  assert_true(validate(hidden, area_tolerance=0.5).is_empty())
}

///|
test "reports duplicate faces irrespective of vertex order" {
  let terrain = sample_terrain(("01", "2", "3"))
  terrain.surfaces[0].faces.push({ vertices: ("3", "2", "01"), visible: true, })
  let diagnostics = validate(terrain)
  assert_eq(diagnostics.length(), 1)
  assert_true(diagnostics[0].rule is DuplicateFace)
  assert_eq(diagnostics[0].face_number, Some(2))
}

///|
test "reports inconsistent direction on a shared edge" {
  let terrain = sample_terrain(("01", "2", "3"))
  terrain.surfaces[0].points.push({
    id: "4",
    northing: 99.0,
    easting: 201.0,
    elevation: 12.0,
  })
  terrain.surfaces[0].faces.push({ vertices: ("01", "2", "4"), visible: true, })
  let diagnostics = validate(terrain)
  assert_eq(diagnostics.length(), 1)
  assert_true(diagnostics[0].rule is SharedEdgeDirection)
  assert_true(diagnostics[0].point_ids.contains("01"))
  assert_true(diagnostics[0].point_ids.contains("2"))
}

///|
test "nonmanifold edge lists other faces and duplicate identifies first face" {
  let terrain = sample_terrain(("01", "2", "3"))
  let surface = terrain.surfaces[0]
  surface.points.push({
    id: "4",
    northing: 99.0,
    easting: 201.0,
    elevation: 12.0,
  })
  surface.points.push({
    id: "5",
    northing: 102.0,
    easting: 200.0,
    elevation: 10.0,
  })
  surface.faces.push({ vertices: ("2", "01", "4"), visible: true, })
  surface.faces.push({ vertices: ("01", "2", "5"), visible: true, })
  surface.faces.push({ vertices: ("3", "01", "2"), visible: true, })
  let issues = validate(terrain)
  assert_eq(issues.length(), 2)
  assert_eq(issues[0].rule.code(), "duplicate_face")
  assert_eq(issues[0].related_faces[0].number, 1)
  assert_eq(issues[1].rule.code(), "non_manifold_edge")
  assert_eq(issues[1].face_number, Some(3))
  assert_eq(issues[1].related_faces.map(fn(reference) { reference.number }), [
    1, 2,
  ])
}
