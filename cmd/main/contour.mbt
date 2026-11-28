///|
priv struct ContourOptions {
  levels : Array[Double]
  surface : String?
  json : Bool
}

///|
fn parse_contour_options(
  level : String,
  args : ArrayView[String],
) -> ContourOptions raise {
  let levels = [query_coordinate("contour elevation", level)]
  let mut surface = None
  let mut json = false
  for rest = args {
    match rest {
      [] => break
      ["--level", value, .. tail] => {
        levels.push(query_coordinate("contour elevation", value))
        continue tail
      }
      ["--surface", name, .. tail] => {
        surface = Some(name)
        continue tail
      }
      ["--format", "json", .. tail] => {
        json = true
        continue tail
      }
      ["--format", "text", .. tail] => {
        json = false
        continue tail
      }
      [option, ..] => raise InvalidOption("invalid contour option: \{option}")
    }
  }
  { levels, surface, json, }
}

///|
async fn contour_file(path : String, options : ContourOptions) -> Int32 {
  let terrain = @moontin.parse(read_input(path, 16 * 1024 * 1024))
  let report = @moontin.extract_contours(
    terrain,
    options.levels[:],
    surface_name?=options.surface,
  )
  if options.json {
    println(report.to_json().stringify())
  } else {
    for line in report.paths {
      println(
        "\{line.surface_name}: elevation \{line.elevation}, \{line.points.length()} points, closed=\{line.closed}",
      )
    }
    println(
      "Contours: \{report.paths.length()} path(s), \{report.skipped_flat_faces} coincident flat face(s).",
    )
  }
  if report.paths.is_empty() {
    1
  } else {
    0
  }
}
