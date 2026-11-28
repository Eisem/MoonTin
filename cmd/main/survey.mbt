///|
fn decode_survey_points(source : String) -> Array[@moontin.SurveyPoint] raise {
  let json = @json.parse(source[:]) catch {
    error => raise InvalidOption("invalid survey points JSON: \{error}")
  }
  guard json is Array(rows) else {
    raise InvalidOption("survey points JSON must be an array")
  }
  if rows.length() > 100000 {
    raise InvalidOption("survey file contains more than 100000 points")
  }
  let points : Array[@moontin.SurveyPoint] = []
  for index, row in rows {
    guard row is Object(fields) else {
      raise InvalidOption("survey point #\{index + 1} must be an object")
    }
    guard (
        fields.get("id"),
        fields.get("northing"),
        fields.get("easting"),
        fields.get("elevation"),
      )
      is (
        Some(String(id)),
        Some(Number(northing, ..)),
        Some(Number(easting, ..)),
        Some(Number(elevation, ..)),
      ) else {
      raise InvalidOption(
        "survey point #\{index + 1} requires a string id and numeric northing, easting and elevation",
      )
    }
    points.push({ id, northing, easting, elevation, })
  }
  points
}

///|
async fn survey_file(
  terrain_path : String,
  survey_path : String,
  tolerance_text : String,
  options : SampleOptions,
) -> Int32 {
  let tolerance = query_coordinate("tolerance", tolerance_text)
  let points = decode_survey_points(read_input(survey_path, 16 * 1024 * 1024))
  let terrain = @moontin.parse(read_input(terrain_path, 16 * 1024 * 1024))
  let report = @moontin.check_survey_points(
    terrain,
    points[:],
    tolerance,
    surface_name?=options.surface,
  )
  if options.json {
    println(report.to_json().stringify())
  } else {
    for result in report.results {
      let status = result.status.label()
      match result.max_absolute_error {
        Some(error) =>
          println(
            "\{result.point.id}: \{status}, maximum error \{error}, \{result.hit_count} hit(s)",
          )
        None =>
          println("\{result.point.id}: \{status}, \{result.hit_count} hit(s)")
      }
    }
    println(
      "Survey: \{report.passed_count} passed, \{report.outside_tolerance_count} outside tolerance, \{report.uncovered_count} uncovered.",
    )
  }
  if report.passed() {
    0
  } else {
    1
  }
}
