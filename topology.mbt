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
  let neighbors : Map[Int, Array[Int]] = Map([])
  self.faces.each(fn(_, number) { neighbors[number] = [] })
  let mut boundary = 0
  self.edges.each(fn(_, uses) {
    if uses.length() == 1 {
      boundary += 1
    } else {
      let first = uses[0].face_number
      for index = 1; index < uses.length(); index = index + 1 {
        let next = uses[index].face_number
        neighbors[first].push(next)
        neighbors[next].push(first)
      }
    }
  })
  let visited : Map[Int, Bool] = Map([])
  let mut components = 0
  neighbors.each(fn(start, _) {
    if !visited.contains(start) {
      components += 1
      let pending = [start]
      visited[start] = true
      while pending.pop() is Some(face) {
        for next in neighbors[face] {
          if !visited.contains(next) {
            visited[next] = true
            pending.push(next)
          }
        }
      }
    }
  })
  (boundary, components)
}
