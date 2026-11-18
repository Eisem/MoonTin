///|
pub(all) enum MeshFormat {
  Obj
  Ply
}

///|
pub struct MeshVertex {
  easting : Double
  northing : Double
  elevation : Double
}

///|
pub struct MeshFace {
  surface_number : Int
  face_number : Int
  vertices : (Int, Int, Int)
}

///|
pub struct TerrainMesh {
  vertices : Array[MeshVertex]
  faces : Array[MeshFace]
  linear_unit : String?
  origin : MeshVertex
}

///|
priv struct MeshBuilder {
  vertices : Array[MeshVertex]
  faces : Array[MeshFace]
  point_indexes : Map[(Int, String), Int]
  face_keys : Map[(Int, Int, Int), Bool]
  origin : MeshVertex
}

///|
fn MeshBuilder::index(
  self : MeshBuilder,
  surface_number : Int,
  point : Point,
) -> Int {
  let key = (surface_number, point.id)
  if self.point_indexes.get(key) is Some(index) {
    return index
  }
  let index = self.vertices.length()
  self.vertices.push({
    easting: point.easting - self.origin.easting,
    northing: point.northing - self.origin.northing,
    elevation: point.elevation - self.origin.elevation,
  })
  self.point_indexes[key] = index
  index
}

///|
/// Builds a visible mesh in X=easting, Y=northing, Z=elevation order.
/// Local origin uses the first vertex of the first visible face.
pub fn build_mesh(
  terrain : Terrain,
  surface_name? : String,
  local_origin? : Bool = false,
) -> TerrainMesh raise SamplingError {
  let mut state : MeshBuilder? = None
  let mut problem = None
  each_visible_triangle(terrain, surface_name, fn(triangle) {
    if problem is Some(_) {
      return
    }
    let builder = match state {
      Some(builder) => builder
      None => {
        let origin = if local_origin {
          MeshVertex::{
            easting: triangle.a.easting,
            northing: triangle.a.northing,
            elevation: triangle.a.elevation,
          }
        } else {
          { easting: 0.0, northing: 0.0, elevation: 0.0, }
        }
        let builder = MeshBuilder::{
          vertices: [],
          faces: [],
          point_indexes: Map([]),
          face_keys: Map([]),
          origin,
        }
        state = Some(builder)
        builder
      }
    }
    let area = projected_area(triangle.a, triangle.b, triangle.c)
    if area <= 0.0 || !finite_sample_value(area) {
      problem = Some(
        "surface '\{triangle.surface_name}': invalid projected area at face #\{triangle.face_number}",
      )
      return
    }
    let surface = triangle.surface_number
    let a = builder.index(surface, triangle.a)
    let b = builder.index(surface, triangle.b)
    let c = builder.index(surface, triangle.c)
    let sorted = [a, b, c]
    sorted.sort()
    let key = (sorted[0], sorted[1], sorted[2])
    if builder.face_keys.contains(key) {
      problem = Some(
        "surface '\{triangle.surface_name}': duplicate face #\{triangle.face_number}",
      )
      return
    }
    builder.face_keys[key] = true
    builder.faces.push({
      surface_number: surface,
      face_number: triangle.face_number,
      vertices: (a, b, c),
    })
  })
  if problem is Some(message) {
    raise InvalidSample(message)
  }
  guard state is Some(builder) else {
    raise InvalidSample("no visible faces to export")
  }
  if builder.vertices.any(fn(vertex) {
      !finite_sample_value(vertex.easting) ||
      !finite_sample_value(vertex.northing) ||
      !finite_sample_value(vertex.elevation)
    }) {
    raise InvalidSample(
      "mesh coordinates exceed the numeric range after origin shift",
    )
  }
  {
    vertices: builder.vertices,
    faces: builder.faces,
    linear_unit: terrain.linear_unit,
    origin: builder.origin,
  }
}

///|
fn TerrainMesh::write_metadata(
  self : TerrainMesh,
  output : StringBuilder,
  prefix : String,
) -> Unit {
  output.write_string("\{prefix} axes easting northing elevation\n")
  output.write_string(
    "\{prefix} origin \{self.origin.easting} \{self.origin.northing} \{self.origin.elevation}\n",
  )
  if self.linear_unit is Some(unit) {
    let safe = StringBuilder()
    for ch in unit {
      if ch >= ' ' && ch != '\u007F' {
        safe.write_char(ch)
      }
    }
    output.write_string("\{prefix} linear_unit \{safe.to_string()}\n")
  }
}

///|
fn TerrainMesh::write_obj(self : TerrainMesh, output : StringBuilder) -> Unit {
  output.write_string("# MoonTIN mesh\n")
  self.write_metadata(output, "#")
  for vertex in self.vertices {
    output.write_string(
      "v \{vertex.easting} \{vertex.northing} \{vertex.elevation}\n",
    )
  }
  let mut group = 0
  for face in self.faces {
    if group != face.surface_number {
      group = face.surface_number
      output.write_string("g surface_\{group}\n")
    }
    let (a, b, c) = face.vertices
    output.write_string("f \{a + 1} \{b + 1} \{c + 1}\n")
  }
}

///|
fn TerrainMesh::write_ply(self : TerrainMesh, output : StringBuilder) -> Unit {
  output.write_string("ply\nformat ascii 1.0\n")
  self.write_metadata(output, "comment")
  output.write_string("element vertex \{self.vertices.length()}\n")
  output.write_string(
    "property double x\nproperty double y\nproperty double z\n",
  )
  output.write_string("element face \{self.faces.length()}\n")
  output.write_string("property list uchar int vertex_indices\n")
  output.write_string(
    "property int surface_number\nproperty int landxml_face_number\nend_header\n",
  )
  for vertex in self.vertices {
    output.write_string(
      "\{vertex.easting} \{vertex.northing} \{vertex.elevation}\n",
    )
  }
  for face in self.faces {
    let (a, b, c) = face.vertices
    output.write_string(
      "3 \{a} \{b} \{c} \{face.surface_number} \{face.face_number}\n",
    )
  }
}

///|
pub fn TerrainMesh::encode(self : TerrainMesh, format : MeshFormat) -> String {
  let output = StringBuilder()
  match format {
    Obj => self.write_obj(output)
    Ply => self.write_ply(output)
  }
  output.to_string()
}
