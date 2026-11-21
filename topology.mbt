///|
priv struct EdgeUse {
  face_number : Int
  forward : Bool
}

///|
priv struct SurfaceTopology {
  faces : Map[(String, String, String), Int]
  edges : Map[(String, String), Array[EdgeUse]]
}

///|
fn SurfaceTopology::new() -> SurfaceTopology {
  { faces: Map([]), edges: Map([]), }
}

///|
fn SurfaceTopology::add_face(
  self : SurfaceTopology,
  vertices : (String, String, String),
  face_number : Int,
  emit : (Rule, Int?, Array[String], Array[Int]) -> Unit,
) -> Bool {
  let (a, b, c) = vertices
  let ids = [a, b, c]
  ids.sort()
  let key = (ids[0], ids[1], ids[2])
  if self.faces.get(key) is Some(first) {
    emit(DuplicateFace, Some(face_number), ids, [first])
    return false
  }
  self.faces[key] = face_number
  self.add_edge(a, b, face_number)
  self.add_edge(b, c, face_number)
  self.add_edge(c, a, face_number)
  true
}

///|
fn SurfaceTopology::add_edge(
  self : SurfaceTopology,
  start : String,
  end : String,
  face_number : Int,
) -> Unit {
  let forward = start < end
  let key = if forward { (start, end) } else { (end, start) }
  let usage = EdgeUse::{ face_number, forward, }
  match self.edges.get(key) {
    Some(uses) => uses.push(usage)
    None => self.edges[key] = [usage]
  }
}

///|
fn SurfaceTopology::check_edges(
  self : SurfaceTopology,
  emit : (Rule, Int?, Array[String], Array[Int]) -> Unit,
) -> Unit {
  self.edges.each(fn(edge, uses) {
    let (a, b) = edge
    if uses.length() > 2 {
      emit(
        NonManifoldEdge,
        Some(uses[2].face_number),
        [a, b],
        uses.filter_map(fn(usage) {
          if usage.face_number == uses[2].face_number {
            None
          } else {
            Some(usage.face_number)
          }
        }),
      )
    } else if uses.length() == 2 && uses[0].forward == uses[1].forward {
      emit(SharedEdgeDirection, Some(uses[1].face_number), [a, b], [
        uses[0].face_number,
      ])
    }
  })
}

///|
fn SurfaceTopology::summarize(self : SurfaceTopology) -> (Int, Int) {
  let mut highest_face = 0
  self.faces.each(fn(_, number) { highest_face = highest_face.max(number) })
  // A negative entry identifies a root and stores the negated set size.
  let parents = FixedArray::make(highest_face + 1, -1)
  let mut boundary = 0
  let mut components = self.faces.length()
  self.edges.each(fn(_, uses) {
    if uses.length() == 1 {
      boundary += 1
    } else {
      let mut first = component_root(parents, uses[0].face_number)
      for index = 1; index < uses.length(); index = index + 1 {
        let other = component_root(parents, uses[index].face_number)
        if first != other {
          first = merge_components(parents, first, other)
          components -= 1
        }
      }
    }
  })
  (boundary, components)
}

///|
fn component_root(parents : FixedArray[Int], face : Int) -> Int {
  let mut root = face
  while parents[root] >= 0 {
    root = parents[root]
  }
  let mut child = face
  while child != root {
    let parent = parents[child]
    parents[child] = root
    child = parent
  }
  root
}

///|
fn merge_components(
  parents : FixedArray[Int],
  first : Int,
  second : Int,
) -> Int {
  let (large, small) = if parents[first] <= parents[second] {
    (first, second)
  } else {
    (second, first)
  }
  parents[large] += parents[small]
  parents[small] = large
  large
}
