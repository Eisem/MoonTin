///|
async fn check_file(path : String, options : CheckOptions) -> Int {
  let report = @moontin.check(
    read_input(path, options.max_input_bytes),
    area_tolerance=options.area_tolerance,
    strict=options.strict,
    max_diagnostics=options.max_diagnostics,
    max_records=options.max_records,
  )
  let passed = report.passed()
  if options.json {
    println(report.to_json().stringify())
  } else {
    for issue in report.record_issues {
      println(
        "\{path}:\{issue.location.line}:\{issue.location.column}: \{issue.severity.label()} \{issue.code}: \{issue.message}",
      )
    }
    for diagnostic in report.diagnostics {
      let face = match diagnostic.face_number {
        Some(number) => ", face #\{number}"
        None => ""
      }
      let ids = diagnostic.point_ids.join(", ")
      let rule = diagnostic.rule.code()
      let surface = diagnostic.surface_name
      let location = match diagnostic.location {
        Some(position) => "\{path}:\{position.line}:\{position.column}: "
        None => ""
      }
      let related = if diagnostic.related_faces.is_empty() {
        ""
      } else {
        let numbers = diagnostic.related_faces
          .map(fn(reference) { reference.number.to_string() })
          .join(", ")
        " (related faces: \{numbers})"
      }
      println(
        "\{location}\{rule}: surface \{surface}\{face} [\{ids}]\{related}",
      )
    }
    for surface in report.surfaces {
      println(
        "\{surface.name}: \{surface.indexed_faces} indexed face(s), \{surface.skipped_visible_faces} skipped visible face(s), \{surface.invisible_faces} invisible face(s), \{surface.boundary_edges} boundary edge(s), \{surface.connected_components} connected component(s).",
      )
    }
    let surfaces = report.surfaces.length()
    println(
      "Checked \{surfaces} TIN surface(s), \{report.error_count} error(s), \{report.warning_count} warning(s).",
    )
    if report.truncated {
      println("Diagnostic output truncated.")
    }
  }
  if passed {
    0
  } else {
    1
  }
}

///|
priv struct CheckOptions {
  json : Bool
  strict : Bool
  max_diagnostics : Int
  max_input_bytes : Int
  max_records : Int
  area_tolerance : Double
}

///|
priv suberror UsageError {
  InvalidOption(String)
}

///|
fn parse_options(args : ArrayView[String]) -> CheckOptions raise {
  let mut json = false
  let mut strict = false
  let mut max_diagnostics = 1000
  let mut max_input_bytes = 16 * 1024 * 1024
  let mut max_records = 500000
  let mut area_tolerance = 0.0
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
      ["--strict", .. tail] => {
        strict = true
        continue tail
      }
      ["--max-records", value, .. tail] => {
        let limit = @string.parse_int(value[:]) catch {
          _ => raise InvalidOption("invalid --max-records: \{value}")
        }
        if limit <= 0 {
          raise InvalidOption("--max-records must be positive")
        }
        max_records = limit
        continue tail
      }
      ["--max-input-bytes", value, .. tail] => {
        let limit = @string.parse_int(value[:]) catch {
          _ => raise InvalidOption("invalid --max-input-bytes: \{value}")
        }
        if limit <= 0 {
          raise InvalidOption("--max-input-bytes must be positive")
        }
        max_input_bytes = limit
        continue tail
      }
      ["--max-diagnostics", value, .. tail] => {
        let limit = @string.parse_int(value[:]) catch {
          _ => raise InvalidOption("invalid --max-diagnostics: \{value}")
        }
        if limit < 0 {
          raise InvalidOption("--max-diagnostics must be nonnegative")
        }
        max_diagnostics = limit
        continue tail
      }
      ["--area-tolerance", value, .. tail] => {
        let tolerance = @string.parse_double(value[:]) catch {
          _ => raise InvalidOption("invalid --area-tolerance: \{value}")
        }
        if tolerance < 0.0 || tolerance.is_nan() || tolerance.is_inf() {
          raise InvalidOption("--area-tolerance must be finite and nonnegative")
        }
        area_tolerance = tolerance
        continue tail
      }
      [option, ..] => raise InvalidOption("invalid option: \{option}")
    }
  }
  {
    json,
    strict,
    max_diagnostics,
    max_input_bytes,
    max_records,
    area_tolerance,
  }
}

///|
async fn main {
  let status = try {
    match @env.args() {
      [_, "contour", path, level, .. options] =>
        contour_file(path, parse_contour_options(level, options))
      [_, "survey", terrain, points, tolerance, .. options] =>
        survey_file(terrain, points, tolerance, parse_sample_options(options))
      [_, "export", path, .. options] =>
        export_mesh(path, parse_mesh_options(options))
      [_, "check", path, .. options] => check_file(path, parse_options(options))
      [
        _,
        "profile",
        path,
        start_north,
        start_east,
        end_north,
        end_east,
        .. options,
      ] =>
        profile_file(
          path,
          start_north,
          start_east,
          end_north,
          end_east,
          parse_sample_options(options),
        )
      [_, "sample", path, north, east, .. options] =>
        sample_file(path, north, east, parse_sample_options(options))
      [_, "diff", before, after, .. options] =>
        diff_files(before, after, parse_diff_options(options))
      _ => {
        eprintln(
          "Usage: moontin check <terrain.xml> [--format text|json] [--area-tolerance N] [--strict] [--max-diagnostics N] [--max-input-bytes N] [--max-records N]",
        )
        eprintln(
          "       moontin contour <terrain.xml> <level> [--level N] [--surface NAME] [--format text|json]",
        )
        eprintln(
          "       moontin survey <terrain.xml> <points.json> <tolerance> [--surface NAME] [--format text|json]",
        )
        eprintln(
          "       moontin export <terrain.xml> [--surface NAME] [--format obj|ply] [--local-origin]",
        )
        eprintln(
          "       moontin profile <terrain.xml> <start-north> <start-east> <end-north> <end-east> [--surface NAME] [--format text|json]",
        )
        eprintln(
          "       moontin sample <terrain.xml> <northing> <easting> [--surface NAME] [--format text|json]",
        )
        eprintln(
          "       moontin diff <before.xml> <after.xml> [--format text|json] [--coordinate-tolerance N] [--max-details N] [--max-input-bytes N]",
        )
        2
      }
    }
  } catch {
    @moontin.InvalidSample(message) => {
      eprintln("moontin: \{message}")
      2
    }
    @moontin.InvalidLandXml(message)
    | @moontin.InvalidComparison(message)
    | InvalidOption(message) => {
      eprintln("moontin: \{message}")
      2
    }
    InputTooLarge(limit) => {
      eprintln("moontin: input file exceeds \{limit} bytes")
      2
    }
    InputChanged => {
      eprintln("moontin: input file grew during reading")
      2
    }
    InvalidUtf8 => {
      eprintln("moontin: input file is not valid UTF-8")
      2
    }
    error => {
      eprintln("moontin: \{error}")
      2
    }
  }
  @sys.exit(status)
}
