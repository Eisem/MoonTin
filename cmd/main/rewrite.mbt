///|
priv struct RewriteOptions {
  surface : String?
  visible_only : Bool
  renumber_points : Bool
  metadata : @moontin.LandXmlMetadata
}

///|
fn parse_rewrite_options(args : ArrayView[String]) -> RewriteOptions raise {
  let mut surface = None
  let mut visible_only = false
  let mut renumber_points = false
  let mut date = None
  let mut time = None
  let mut project = None
  let mut description = None
  for rest = args {
    match rest {
      [] => break
      ["--surface", name, .. tail] => {
        surface = Some(name)
        continue tail
      }
      ["--visible-only", .. tail] => {
        visible_only = true
        continue tail
      }
      ["--renumber-points", .. tail] => {
        renumber_points = true
        continue tail
      }
      ["--timestamp", written_date, written_time, .. tail] => {
        date = Some(written_date)
        time = Some(written_time)
        continue tail
      }
      ["--project", name, .. tail] => {
        project = Some(name)
        continue tail
      }
      ["--description", text, .. tail] => {
        description = Some(text)
        continue tail
      }
      [option, ..] => raise InvalidOption("invalid rewrite option: \{option}")
    }
  }
  {
    surface,
    visible_only,
    renumber_points,
    metadata: { date, time, project, description, },
  }
}

///|
async fn rewrite_file(path : String, options : RewriteOptions) -> Int32 {
  let terrain = @moontin.parse(read_input(path, 16 * 1024 * 1024))
  let source = @moontin.write_landxml(
    terrain,
    surface_name?=options.surface,
    visible_only=options.visible_only,
    renumber_points=options.renumber_points,
    metadata=options.metadata,
  )
  println(source.trim_end().to_owned())
  0
}
