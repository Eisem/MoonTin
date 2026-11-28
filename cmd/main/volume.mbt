///|
priv struct VolumeOptions {
  reference : @moontin.ReferencePlane
  surface : String?
  json : Bool
}

///|
fn parse_volume_options(
  height : String,
  args : ArrayView[String],
) -> VolumeOptions raise {
  let elevation = query_coordinate("reference elevation", height)
  let mut northing = 0.0
  let mut easting = 0.0
  let mut north_grade = 0.0
  let mut east_grade = 0.0
  let mut surface = None
  let mut json = false
  for rest = args {
    match rest {
      [] => break
      ["--anchor", north, east, .. tail] => {
        northing = query_coordinate("anchor northing", north)
        easting = query_coordinate("anchor easting", east)
        continue tail
      }
      ["--grade", north, east, .. tail] => {
        north_grade = query_coordinate("north grade", north)
        east_grade = query_coordinate("east grade", east)
        continue tail
      }
      ["--surface", name, .. tail] => {
        surface = Some(name)
        continue tail
      }
      ["--format", "text", .. tail] => {
        json = false
        continue tail
      }
      ["--format", "json", .. tail] => {
        json = true
        continue tail
      }
      [option, ..] => raise InvalidOption("invalid volume option: \{option}")
    }
  }
  {
    reference: { northing, easting, elevation, north_grade, east_grade, },
    surface,
    json,
  }
}

///|
async fn volume_file(path : String, options : VolumeOptions) -> Int32 {
  let terrain = @moontin.parse(read_input(path, 16 * 1024 * 1024))
  let report = @moontin.estimate_volume(
    terrain,
    options.reference,
    surface_name?=options.surface,
  )
  if options.json {
    println(report.to_json().stringify())
  } else {
    for surface in report.surfaces {
      println(
        "\{surface.name}: cut \{surface.cut}, fill \{surface.fill}, projected area \{surface.projected_area}",
      )
    }
    println(
      "Total: cut \{report.cut}, fill \{report.fill}, net cut \{report.cut - report.fill}",
    )
  }
  if report.surfaces.is_empty() {
    1
  } else {
    0
  }
}
