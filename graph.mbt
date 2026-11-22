///|
fn cycle_path(
  steps : Array[Step],
  index : Map[String, Int32],
  remaining : Array[Int32],
) -> String {
  let positions : Map[Int32, Int32] = Map([])
  let visited : Array[Int32] = []
  let mut current = 0
  for i, degree in remaining {
    if degree > 0 {
      current = i
      break
    }
  }
  while !positions.contains(current) {
    positions.set(current, visited.length())
    visited.push(current)
    let mut found = false
    for binding in steps[current].bindings {
      if binding.source is Some(parent) &&
        index.get(parent) is Some(i) &&
        remaining[i] > 0 {
        current = i
        found = true
        break
      }
    }
    if !found {
      return steps[current].id
    }
  }
  let start = positions[current]
  let path : Array[String] = [steps[current].id]
  let mut i = visited.length()
  while i > start {
    i -= 1
    path.push(steps[visited[i]].id)
  }
  path.join(" -> ")
}
