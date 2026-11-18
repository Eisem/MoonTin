///|
fn comparison_terrain() -> Terrain {
  {
    linear_unit: Some("meter"),
    surfaces: [
      {
        name: "Ground",
        points: [
          { id: "1", northing: 0.0, easting: 0.0, elevation: 5.0, },
          { id: "2", northing: 0.0, easting: 1.0, elevation: 5.0, },
          { id: "3", northing: 1.0, easting: 0.0, elevation: 5.0, },
        ],
        faces: [{ vertices: ("1", "2", "3"), visible: true, }],
      },
    ],
  }
}

///|
test "comparison ignores record order and cyclic rotation" {
  let before = comparison_terrain()
  let after = comparison_terrain()
  let points = after.surfaces[0].points
  let first = points[0]
  points[0] = points[2]
  points[2] = first
  after.surfaces[0].faces[0] = { vertices: ("2", "3", "1"), visible: true, }
  assert_false(compare_terrain(before, after).changed())
}

///|
test "comparison retains counts when it truncates moved points and changed faces" {
  let before = comparison_terrain()
  let after = comparison_terrain()
  let point = after.surfaces[0].points[1]
  after.surfaces[0].points[1] = { ..point, elevation: 5.25, }
  after.surfaces[0].faces[0] = { vertices: ("1", "3", "2"), visible: false, }
  let full = compare_terrain(before, after).surfaces[0]
  assert_eq(full.moved_points[0].id, "2")
  assert_true(full.changed_faces[0].winding_changed)
  assert_true(full.changed_faces[0].visibility_changed)
  let limited = compare_terrain(before, after, max_details=0).surfaces[0]
  assert_eq(limited.moved_point_count, 1)
  assert_eq(limited.changed_face_count, 1)
  assert_true(limited.truncated)
  assert_true(limited.moved_points.is_empty())
  let tolerant = compare_terrain(before, after, coordinate_tolerance=0.25).surfaces[0]
  assert_eq(tolerant.moved_point_count, 0)
}
