///|
pub fn Rule::code(self : Rule) -> String {
  match self {
    DuplicatePoint => "duplicate_point"
    MissingPoint => "missing_point"
    AmbiguousPoint => "ambiguous_point"
    NonFinitePoint => "non_finite_point"
    RepeatedVertex => "repeated_vertex"
    DegenerateFace => "degenerate_face"
    NonFiniteArea => "non_finite_area"
    DuplicateFace => "duplicate_face"
    NonManifoldEdge => "non_manifold_edge"
    SharedEdgeDirection => "shared_edge_direction"
  }
}

///|
pub fn Diagnostic::to_json(self : Diagnostic) -> Json {
  {
    "code": self.rule.code().to_json(),
    "severity": "error".to_json(),
    "surface_number": self.surface_number.to_json(),
    "surface_name": self.surface_name.to_json(),
    "face_number": match self.face_number {
      Some(number) => number.to_json()
      None => Json::null()
    },
    "point_ids": self.point_ids.to_json(),
    "related_faces": self.related_faces
    .map(fn(face) { face.to_json() })
    .to_json(),
    "location": match self.location {
      Some(location) => location.to_json()
      None => Json::null()
    },
  }
}

///|
pub struct SourceLocation {
  line : Int
  column : Int
}

///|
pub fn SourceLocation::to_json(self : SourceLocation) -> Json {
  { "line": self.line.to_json(), "column": self.column.to_json() }
}

///|
priv struct SurfaceLocations {
  points : Array[SourceLocation]
  faces : Map[Int, SourceLocation]
}

///|
pub struct FaceReference {
  number : Int
  location : SourceLocation?
}

///|
pub fn FaceReference::to_json(self : FaceReference) -> Json {
  {
    "number": self.number.to_json(),
    "location": match self.location {
      Some(location) => location.to_json()
      None => Json::null()
    },
  }
}
