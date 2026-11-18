///|
async fn profile_file(
  path : String,
  start_north : String,
  start_east : String,
  end_north : String,
  end_east : String,
  options : SampleOptions,
) -> Int {
  let start = (
    query_coordinate("start northing", start_north),
    query_coordinate("start easting", start_east),
  )
  let end = (
    query_coordinate("end northing", end_north),
    query_coordinate("end easting", end_east),
  )
  let terrain = @moontin.parse(read_input(path, 16 * 1024 * 1024))
  let profile = @moontin.elevation_profile(
    terrain,
    start,
    end,
    surface_name?=options.surface,
  )
  if options.json {
    println(profile.to_json().stringify())
  } else {
    println("Profile length: \{profile.length}")
    for segment in profile.segments {
      println(
        "\{segment.surface_name}, face #\{segment.face_number}: \{segment.start_distance} to \{segment.end_distance}, elevation \{segment.start_elevation} to \{segment.end_elevation}",
      )
    }
    for gap in profile.gaps {
      println("Uncovered: \{gap.start_distance} to \{gap.end_distance}")
    }
  }
  if profile.segments.is_empty() {
    1
  } else {
    0
  }
}
