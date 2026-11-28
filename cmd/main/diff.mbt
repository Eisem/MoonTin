///|
priv struct DiffOptions {
  json : Bool
  coordinate_tolerance : Double
  max_details : Int32
  max_input_bytes : Int32
}

///|
fn parse_diff_options(args : ArrayView[String]) -> DiffOptions raise {
  let mut json = false
  let mut coordinate_tolerance = 0.0
  let mut max_details = 1000
  let mut max_input_bytes = 16 * 1024 * 1024
  for rest = args {
    match rest {
      [] => break
      ["--format", "text", .. tail] => {
        json = false
        continue tail
      }
      ["--format", "json", .. tail] => {
        json = true
        continue tail
      }
      ["--coordinate-tolerance", value, .. tail] => {
        coordinate_tolerance = @string.parse_double(value[:]) catch {
          _ => raise InvalidOption("invalid --coordinate-tolerance: \{value}")
        }
        continue tail
      }
      ["--max-details", value, .. tail] => {
        max_details = @string.parse_int(value[:]) catch {
          _ => raise InvalidOption("invalid --max-details: \{value}")
        }
        continue tail
      }
      ["--max-input-bytes", value, .. tail] => {
        max_input_bytes = @string.parse_int(value[:]) catch {
          _ => raise InvalidOption("invalid --max-input-bytes: \{value}")
        }
        if max_input_bytes <= 0 {
          raise InvalidOption("--max-input-bytes must be positive")
        }
        continue tail
      }
      [option, ..] => raise InvalidOption("invalid diff option: \{option}")
    }
  }
  { json, coordinate_tolerance, max_details, max_input_bytes, }
}

///|
async fn diff_files(
  before_path : String,
  after_path : String,
  options : DiffOptions,
) -> Int32 {
  let before = @moontin.parse(read_input(before_path, options.max_input_bytes))
  let after = @moontin.parse(read_input(after_path, options.max_input_bytes))
  let comparison = @moontin.compare_terrain(
    before,
    after,
    coordinate_tolerance=options.coordinate_tolerance,
    max_details=options.max_details,
  )
  if options.json {
    println(comparison.to_json().stringify())
  } else {
    for surface in comparison.surfaces {
      println("\{surface.name} [\{surface.status}]")
      println(
        "  Points: +\{surface.added_point_count} -\{surface.removed_point_count}, \{surface.moved_point_count} moved",
      )
      println(
        "  Faces: +\{surface.added_face_count} -\{surface.removed_face_count}, \{surface.changed_face_count} winding/visibility change(s)",
      )
    }
  }
  if comparison.changed() {
    1
  } else {
    0
  }
}
