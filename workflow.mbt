///|
priv struct Binding {
  parameter : String
  source : String?
  pointer : Array[String]
  literal : Json
}

///|
priv struct Step {
  id : String
  tool_available : Bool
  input : Json
  output : Json?
  bindings : Array[Binding]
}

///|
fn load_steps(catalog : Json, plan : Json) -> Array[Step] raise CheckError {
  let tools = catalog_tools(catalog)
  let inputs = field_at(plan, "inputs")
  let steps : Array[Step] = []
  let identifiers : Map[String, Bool] = Map([])
  for value in array_value(required_member(plan, "steps")) {
    let id = string_value(required_member(value, "id"))
    if id == "$inputs" || identifiers.contains(id) {
      raise Invalid("Duplicate step: " + id)
    }
    identifiers.set(id, true)
    let server = string_value(required_member(value, "server"))
    let name = string_value(required_member(value, "tool"))
    let key = tool_key(server, name)
    let tool = tools.get(key)
    let bindings : Array[Binding] = []
    for parameter, binding in object_value(required_member(value, "args")) {
      let fields = object_value(binding)
      if fields.get("input") is Some(String(path)) {
        if fields.length() != 1 {
          raise Invalid(
            "Unexpected fields in input binding for " +
            id +
            "/" +
            escaped(parameter),
          )
        }
        if inputs is None {
          raise Invalid("Input binding requires a workflow inputs schema")
        }
        bindings.push({
          parameter,
          source: Some("$inputs"),
          pointer: pointer_tokens(path),
          literal: Json::null(),
        })
        continue
      }
      match (fields.get("literal"), fields.get("from")) {
        (Some(literal), None) if fields.length() == 1 =>
          bindings.push({ parameter, source: None, pointer: [], literal, })
        (None, Some(String(source))) if source != "$inputs" &&
          fields.length() == 2 => {
          let pointer = pointer_tokens(
            string_value(required_member(binding, "pointer")),
          )
          bindings.push({
            parameter,
            source: Some(source),
            pointer,
            literal: Json::null(),
          })
        }
        _ =>
          raise Invalid("Invalid binding for " + id + "/" + escaped(parameter))
      }
    }
    steps.push({
      id,
      tool_available: tool is Some(_),
      input: match tool {
        Some(value) => expand_schema(required_member(value, "inputSchema"))
        None => Json::boolean(false)
      },
      output: tool.bind(value => {
        field_at(value, "outputSchema").map(expand_schema)
      }),
      bindings,
    })
  }
  steps
}

///|
fn order_steps(steps : Array[Step]) -> Array[Step] raise CheckError {
  let index : Map[String, Int32] = Map([])
  let successors : Array[Array[Int32]] = []
  let indegree = Array::make(steps.length(), 0)
  for i, step in steps {
    index.set(step.id, i)
    successors.push([])
  }
  for i, step in steps {
    for binding in step.bindings {
      if binding.source is Some(parent) && parent != "$inputs" {
        match index.get(parent) {
          None => raise Invalid("Missing upstream step: " + parent)
          Some(j) => {
            indegree[i] += 1
            successors[j].push(i)
          }
        }
      }
    }
  }
  let ready : Array[Int32] = []
  for i, degree in indegree {
    if degree == 0 {
      ready.push(i)
    }
  }
  let ordered : Array[Step] = []
  let mut cursor = 0
  while cursor < ready.length() {
    let i = ready[cursor]
    cursor += 1
    ordered.push(steps[i])
    for j in successors[i] {
      indegree[j] -= 1
      if indegree[j] == 0 {
        ready.push(j)
      }
    }
  }
  if ordered.length() != steps.length() {
    raise Invalid(
      "Cyclic workflow dependencies: " + cycle_path(steps, index, indegree),
    )
  }
  ordered
}

///|
fn assembled(step : Step, outputs : Map[String, Json]) -> Json {
  let arguments : Map[String, Json] = Map([])
  for binding in step.bindings {
    match binding.source {
      None => arguments.set(binding.parameter, binding.literal)
      Some(source) =>
        if outputs.get(source) is Some(output) &&
          resolve(output, binding.pointer) is Some(value) {
          arguments.set(binding.parameter, value)
        }
    }
  }
  Json::object(arguments)
}

///|
fn projection(step : Step, predecessors : Map[String, Json]) -> Json {
  let properties : Map[String, Json] = Map([])
  let required : Array[Json] = []
  for binding in step.bindings {
    let (schema, present) = match binding.source {
      None => (Json::object(Map([("const", binding.literal)])), true)
      Some(source) =>
        project(
          predecessors.get(source).unwrap_or(Json::boolean(true)),
          binding.pointer,
        )
    }
    properties.set(binding.parameter, schema)
    if present {
      required.push(Json::string(binding.parameter))
    }
  }
  Json::object(
    Map([
      ("type", Json::string("object")),
      ("properties", Json::object(properties)),
      ("required", Json::array(required)),
      ("additionalProperties", Json::boolean(false)),
    ]),
  )
}

///|
pub fn check_workflow(catalog : Json, plan : Json) -> Json raise CheckError {
  check_prepared_workflow(prepare_workflow(catalog, plan))
}

///|
priv struct PreparedWorkflow {
  ordered : Array[Step]
  index : Map[String, Step]
  inputs : Json?
}

///|
fn prepare_workflow(
  catalog : Json,
  plan : Json,
) -> PreparedWorkflow raise CheckError {
  let ordered = order_steps(load_steps(catalog, plan))
  let index : Map[String, Step] = Map([])
  for step in ordered {
    index.set(step.id, step)
  }
  { ordered, index, inputs: field_at(plan, "inputs").map(expand_schema), }
}

///|
fn prepared_source(workflow : PreparedWorkflow, name : String) -> Json? {
  if name == "$inputs" {
    workflow.inputs
  } else {
    workflow.index.get(name).bind(step => step.output)
  }
}

///|
fn check_prepared_workflow(workflow : PreparedWorkflow) -> Json {
  let results : Array[Json] = []
  for step in workflow.ordered {
    let predecessors : Map[String, Json] = Map([])
    let mut missing = false
    for binding in step.bindings {
      if binding.source is Some(parent) {
        match prepared_source(workflow, parent) {
          Some(schema) => predecessors.set(parent, schema)
          None => missing = true
        }
      }
    }
    let projected = projection(step, predecessors)
    let state = if !step.tool_available {
      Incompatible(Json::object(Map([("kind", Json::string("missing_tool"))])))
    } else if missing {
      Unknown("Missing outputSchema")
    } else if !supports(step.input, 0) || !supports(projected, 0) {
      Unknown("Unsupported input or argument schema")
    } else {
      let mut supported = true
      for _, schema in predecessors {
        supported = supported && supports(schema, 0)
      }
      if !supported {
        Unknown("Unsupported upstream schema")
      } else {
        analyze_bindings(step, predecessors, projected)
      }
    }
    results.push(render_step(step.id, state))
  }
  Json::array(results)
}

///|
fn render_step(id : String, result : Compatibility) -> Json {
  let fields = Map([("step", Json::string(id))])
  let status = match result {
    Compatible => "compatible"
    Incompatible(witness) => {
      fields.set("witness", witness)
      "incompatible"
    }
    Unknown(reason) => {
      fields.set("reason", Json::string(reason))
      "unknown"
    }
  }
  fields.set("status", Json::string(status))
  Json::object(fields)
}
