///|
priv struct SampleOptions {
  surface : String?
  json : Bool
}

///|
fn parse_sample_options(args : ArrayView[String]) -> SampleOptions raise {
  let mut surface = None
  let mut json = false
  for rest = args {
    match rest {
      [] => break
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
      [option, ..] => raise InvalidOption("invalid sample option: \{option}")
    }
  }
  { surface, json, }
}

///|
fn query_coordinate(axis : String, value : String) -> Double raise {
  @string.parse_double(value[:]) catch {
    _ => raise InvalidOption("invalid \{axis} coordinate: \{value}")
  }
}

///|
async fn sample_file(
  path : String,
  north : String,
  east : String,
  options : SampleOptions,
) -> Int {
  let northing = query_coordinate("northing", north)
  let easting = query_coordinate("easting", east)
  let terrain = @moontin.parse(read_input(path, 16 * 1024 * 1024))
  let sample = @moontin.sample_elevation(
    terrain,
    northing,
    easting,
    surface_name?=options.surface,
  )
  if options.json {
    println(sample.to_json().stringify())
  } else if sample.hits.is_empty() {
    println(
      "No visible TIN face covers northing \{northing}, easting \{easting}.",
    )
  } else {
    for hit in sample.hits {
      println(
        "\{hit.surface_name}, face #\{hit.face_number}: elevation \{hit.elevation}",
      )
    }
  }
  if sample.hits.is_empty() {
    1
  } else {
    0
  }
}
