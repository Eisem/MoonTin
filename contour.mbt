///|
pub struct ContourPoint {
  northing : Double
  easting : Double
}

///|
pub struct ContourPath {
  surface_number : Int
  surface_name : String
  elevation : Double
  closed : Bool
  points : Array[ContourPoint]
}

///|
pub struct ContourReport {
  linear_unit : String?
  levels : Array[Double]
  paths : Array[ContourPath]
  skipped_flat_faces : Int
}

///|
priv struct ContourEndpoint {
  key : (String, String)
  position : ContourPoint
}

///|
priv struct ContourEdge {
  first : Int
  second : Int
}

///|
priv struct ContourGraph {
  surface_number : Int
  surface_name : String
  elevation : Double
  index : Map[(String, String), Int]
  points : Array[ContourPoint]
  adjacency : Array[Array[Int]]
  edges : Array[ContourEdge]
  edge_keys : Map[(Int, Int), Bool]
}

///|
fn ContourGraph::new(
  triangle : SamplingTriangle,
  elevation : Double,
) -> ContourGraph {
  {
    surface_number: triangle.surface_number,
    surface_name: triangle.surface_name,
    elevation,
    index: Map([]),
    points: [],
    adjacency: [],
    edges: [],
    edge_keys: Map([]),
  }
}

///|
fn contour_vertex(point : Point) -> ContourEndpoint {
  {
    key: (point.id, point.id),
    position: { northing: point.northing, easting: point.easting, },
  }
}

///|
fn contour_intersection(
  a : Point,
  b : Point,
  level : Double,
) -> ContourEndpoint? {
  if a.elevation == level {
    return Some(contour_vertex(a))
  }
  if b.elevation == level {
    return Some(contour_vertex(b))
  }
  if (a.elevation < level) == (b.elevation < level) {
    return None
  }
  let (first, second) = if a.id < b.id { (a, b) } else { (b, a) }
  let fraction = (level - first.elevation) /
    (second.elevation - first.elevation)
  Some({
    key: (first.id, second.id),
    position: {
      northing: (1.0 - fraction) * first.northing + fraction * second.northing,
      easting: (1.0 - fraction) * first.easting + fraction * second.easting,
    },
  })
}

///|
fn triangle_contour(
  triangle : SamplingTriangle,
  level : Double,
) -> Array[ContourEndpoint] {
  let a = triangle.a
  let b = triangle.b
  let c = triangle.c
  let vertices = [a, b, c]
  let on_level = vertices.filter(fn(point) { point.elevation == level })
  if on_level.length() == 2 {
    return on_level.map(contour_vertex)
  }
  let result = []
  for edge in [(a, b), (b, c), (c, a)] {
    let (first, second) = edge
    if contour_intersection(first, second, level) is Some(endpoint) &&
      !result.any(fn(previous : ContourEndpoint) {
        previous.key == endpoint.key
      }) {
      result.push(endpoint)
    }
  }
  result
}

///|
fn ContourGraph::vertex(self : ContourGraph, endpoint : ContourEndpoint) -> Int {
  if self.index.get(endpoint.key) is Some(index) {
    return index
  }
  let index = self.points.length()
  self.index[endpoint.key] = index
  self.points.push(endpoint.position)
  self.adjacency.push([])
  index
}

///|
fn ContourGraph::add(
  self : ContourGraph,
  first : ContourEndpoint,
  second : ContourEndpoint,
) -> Unit {
  let a = self.vertex(first)
  let b = self.vertex(second)
  let key = (a.min(b), a.max(b))
  if !self.edge_keys.contains(key) {
    self.edge_keys[key] = true
    let edge = self.edges.length()
    self.edges.push({ first: a, second: b, })
    self.adjacency[a].push(edge)
    self.adjacency[b].push(edge)
  }
}

///|
fn ContourGraph::trace(
  self : ContourGraph,
  start : Int,
  first_edge : Int,
  visited : FixedArray[Bool],
) -> ContourPath {
  let points = [self.points[start]]
  let mut at = start
  let mut edge_index = first_edge
  let mut closed = false
  while !visited[edge_index] {
    visited[edge_index] = true
    let edge = self.edges[edge_index]
    let next = if edge.first == at { edge.second } else { edge.first }
    points.push(self.points[next])
    if next == start {
      closed = true
      break
    }
    let attached = self.adjacency[next]
    if attached.length() != 2 {
      break
    }
    at = next
    edge_index = if attached[0] == edge_index {
      attached[1]
    } else {
      attached[0]
    }
  }
  {
    surface_number: self.surface_number,
    surface_name: self.surface_name,
    elevation: self.elevation,
    closed,
    points,
  }
}

///|
fn ContourGraph::paths(self : ContourGraph) -> Array[ContourPath] {
  let visited = FixedArray::make(self.edges.length(), false)
  let result = []
  for vertex, attached in self.adjacency {
    if attached.length() == 2 {
      continue
    }
    for edge in attached {
      if !visited[edge] {
        result.push(self.trace(vertex, edge, visited))
      }
    }
  }
  for index, edge in self.edges {
    if !visited[index] {
      result.push(self.trace(edge.first, index, visited))
    }
  }
  result
}

///|
fn first_contour_level(levels : Array[Double], elevation : Double) -> Int {
  let mut low = 0
  let mut high = levels.length()
  while low < high {
    let middle = low + (high - low) / 2
    if levels[middle] < elevation {
      low = middle + 1
    } else {
      high = middle
    }
  }
  low
}

///|
/// Traces contour segments through matching TIN edges. Flat faces coincident
/// with a level are counted separately because they cover an area.
pub fn extract_contours(
  terrain : Terrain,
  requested_levels : ArrayView[Double],
  surface_name? : String,
  max_segments? : Int = 500000,
) -> ContourReport raise SamplingError {
  if requested_levels.is_empty() || max_segments < 1 {
    raise InvalidSample("contours require levels and a positive segment budget")
  }
  let levels = requested_levels.to_owned()
  if levels.any(fn(level) { !finite_sample_value(level) }) {
    raise InvalidSample("contour levels must be finite")
  }
  levels.sort()
  for index = 1; index < levels.length(); index = index + 1 {
    if levels[index - 1] == levels[index] {
      raise InvalidSample("contour levels must be distinct")
    }
  }
  let graphs : Map[(Int, Int), ContourGraph] = Map([])
  let mut skipped_flat_faces = 0
  let mut emitted = 0
  let mut problem = None
  each_visible_triangle(terrain, surface_name, fn(triangle) {
    if problem is Some(_) {
      return
    }
    let a = triangle.a.elevation
    let b = triangle.b.elevation
    let c = triangle.c.elevation
    let highest = a.max(b).max(c)
    let lowest = a.min(b).min(c)
    let range = highest - lowest
    if !finite_sample_value(range) {
      problem = Some("contour elevation range exceeds the numeric range")
      return
    }
    let area = projected_area(triangle.a, triangle.b, triangle.c)
    if !finite_sample_value(area) || area <= 0.0 {
      problem = Some(
        "surface '\{triangle.surface_name}': invalid projected area at face #\{triangle.face_number}",
      )
      return
    }
    for index = first_contour_level(levels, lowest)
        index < levels.length()
        index = index + 1 {
      let level = levels[index]
      if level > highest {
        break
      }
      if lowest == highest {
        skipped_flat_faces += 1
      } else if triangle_contour(triangle, level) is [first, second] {
        if emitted == max_segments {
          problem = Some("contour segment budget exceeded")
          break
        }
        let key = (triangle.surface_number, index)
        let graph = match graphs.get(key) {
          Some(graph) => graph
          None => {
            let graph = ContourGraph::new(triangle, level)
            graphs[key] = graph
            graph
          }
        }
        graph.add(first, second)
        emitted += 1
      }
    }
  })
  if problem is Some(message) {
    raise InvalidSample(message)
  }
  let keys = []
  graphs.each(fn(key, _) { keys.push(key) })
  keys.sort()
  let paths = []
  for key in keys {
    for path in graphs[key].paths() {
      paths.push(path)
    }
  }
  { linear_unit: terrain.linear_unit, levels, paths, skipped_flat_faces, }
}

///|
pub fn ContourPoint::to_json(self : ContourPoint) -> Json {
  {
    "northing": ToJson::to_json(self.northing),
    "easting": ToJson::to_json(self.easting),
  }
}

///|
pub fn ContourPath::to_json(self : ContourPath) -> Json {
  {
    "surface_number": ToJson::to_json(self.surface_number),
    "surface_name": ToJson::to_json(self.surface_name),
    "elevation": ToJson::to_json(self.elevation),
    "closed": ToJson::to_json(self.closed),
    "points": ToJson::to_json(self.points.map(fn(point) { point.to_json() })),
  }
}

///|
pub fn ContourReport::to_json(self : ContourReport) -> Json {
  {
    "schema_version": 1,
    "linear_unit": match self.linear_unit {
      Some(unit) => ToJson::to_json(unit)
      None => Json::null()
    },
    "levels": ToJson::to_json(self.levels),
    "paths": ToJson::to_json(self.paths.map(fn(path) { path.to_json() })),
    "skipped_flat_faces": ToJson::to_json(self.skipped_flat_faces),
  }
}
