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
    BranchingBoundary => "branching_boundary"
    SharedEdgeDirection => "shared_edge_direction"
  }
}

///|
pub fn Diagnostic::to_json(self : Diagnostic) -> Json {
  {
    "code": ToJson::to_json(self.rule.code()),
    "severity": ToJson::to_json("error"),
    "surface_number": ToJson::to_json(self.surface_number),
    "surface_name": ToJson::to_json(self.surface_name),
    "face_number": match self.face_number {
      Some(number) => ToJson::to_json(number)
      None => Json::null()
    },
    "point_ids": ToJson::to_json(self.point_ids),
    "related_faces": ToJson::to_json(
      self.related_faces.map(fn(face) { face.to_json() }),
    ),
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
  { "line": ToJson::to_json(self.line), "column": ToJson::to_json(self.column) }
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
    "number": ToJson::to_json(self.number),
    "location": match self.location {
      Some(location) => location.to_json()
      None => Json::null()
    },
  }
}
