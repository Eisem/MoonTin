///|
priv struct BoundaryLink {
  neighbor : String
  face_number : Int32
}

///|
priv struct BoundarySummary {
  closed_loops : Int32
  branched_components : Int32
}

///|
fn SurfaceTopology::check_boundary(
  self : SurfaceTopology,
  emit : (Rule, Int32?, Array[String], Array[Int32]) -> Unit,
) -> BoundarySummary {
  let adjacency : Map[String, Array[BoundaryLink]] = Map([])
  let nonmanifold_vertices : Map[String, Bool] = Map([])
  self.edges.each(fn(edge, uses) {
    let (a, b) = edge
    if uses is [usage] {
      add_boundary_link(adjacency, a, b, usage.face_number)
      add_boundary_link(adjacency, b, a, usage.face_number)
    } else if uses.length() > 2 {
      nonmanifold_vertices[a] = true
      nonmanifold_vertices[b] = true
    }
  })
  let visited : Map[String, Bool] = Map([])
  let mut closed_loops = 0
  let mut branched_components = 0
  adjacency.each(fn(start, _) {
    if !visited.contains(start) {
      let pending = [start]
      visited[start] = true
      let mut closed = true
      while pending.pop() is Some(point) {
        let links = adjacency[point]
        if links.length() != 2 {
          closed = false
        }
        if links.length() != 2 && !nonmanifold_vertices.contains(point) {
          let faces = Map([])
          for link in links {
            faces[link.face_number] = true
          }
          let numbers = []
          faces.each(fn(number, _) { numbers.push(number) })
          numbers.sort()
          emit(
            BranchingBoundary,
            Some(numbers[0]),
            [point],
            numbers[1:].to_owned(),
          )
        }
        for link in links {
          if !visited.contains(link.neighbor) {
            visited[link.neighbor] = true
            pending.push(link.neighbor)
          }
        }
      }
      if closed {
        closed_loops += 1
      } else {
        branched_components += 1
      }
    }
  })
  { closed_loops, branched_components, }
}

///|
fn add_boundary_link(
  adjacency : Map[String, Array[BoundaryLink]],
  point : String,
  neighbor : String,
  face_number : Int32,
) -> Unit {
  let link = BoundaryLink::{ neighbor, face_number, }
  match adjacency.get(point) {
    Some(links) => links.push(link)
    None => adjacency[point] = [link]
  }
}
