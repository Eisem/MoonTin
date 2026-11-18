///|
priv struct MeshOptions {
  surface : String?
  format : @moontin.MeshFormat
  local_origin : Bool
}

///|
fn parse_mesh_options(args : ArrayView[String]) -> MeshOptions raise {
  let mut surface = None
  let mut format : @moontin.MeshFormat = Obj
  let mut local_origin = false
  for rest = args {
    match rest {
      [] => break
      ["--surface", name, .. tail] => {
        surface = Some(name)
        continue tail
      }
      ["--format", "obj", .. tail] => {
        format = Obj
        continue tail
      }
      ["--format", "ply", .. tail] => {
        format = Ply
        continue tail
      }
      ["--local-origin", .. tail] => {
        local_origin = true
        continue tail
      }
      [option, ..] => raise InvalidOption("invalid export option: \{option}")
    }
  }
  { surface, format, local_origin, }
}

///|
async fn export_mesh(path : String, options : MeshOptions) -> Int {
  let terrain = @moontin.parse(read_input(path, 16 * 1024 * 1024))
  let mesh = @moontin.build_mesh(
    terrain,
    surface_name?=options.surface,
    local_origin=options.local_origin,
  )
  println(mesh.encode(options.format).trim_end().to_owned())
  0
}
