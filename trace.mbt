///|
priv struct TraceCall {
  id : String
  position : Int32
  arguments : Json
  output : Json?
  failed : Bool
}

///|
fn read_trace(trace : Json) -> Array[TraceCall] raise CheckError {
  let events = array_value(required_member(trace, "calls"))
  let seen : Map[String, Bool] = Map([])
  let calls : Array[TraceCall] = []
  for position, event in events {
    let id = string_value(required_member(event, "step"))
    if seen.contains(id) {
      raise Invalid("Repeated trace step: " + id)
    }
    seen.set(id, true)
    let arguments = required_member(event, "arguments")
    ignore(object_value(arguments))
    let failed = match field_at(event, "isError") {
      Some(True) => true
      Some(False) | None => false
      _ => raise Invalid("isError must be a boolean")
    }
    calls.push({
      id,
      position,
      arguments,
      output: field_at(event, "structuredContent"),
      failed,
    })
  }
  calls
}

///|
fn trace_problem(step : String, kind : String, detail : Json) -> Json {
  Json::object(
    Map([
      ("step", Json::string(step)),
      ("kind", Json::string(kind)),
      ("detail", detail),
    ]),
  )
}

///|
fn note_contract(
  problems : Array[Json],
  id : String,
  category : String,
  schema : Json,
  value : Json,
) -> Unit {
  let checked = explain_instance(schema, value)
  if field_at(checked, "status") != Some(Json::string("valid")) {
    problems.push(trace_problem(id, category, checked))
  }
}

///|
fn inspect_trace_call(
  call : TraceCall,
  step : Step,
  calls : Map[String, TraceCall],
  input : Json?,
  problems : Array[Json],
) -> Unit {
  if !step.tool_available {
    problems.push(trace_problem(step.id, "missing_tool", Json::null()))
    return
  }
  note_contract(problems, step.id, "input_contract", step.input, call.arguments)
  if call.failed {
    problems.push(trace_problem(step.id, "tool_execution_error", Json::null()))
  } else if step.output is Some(schema) {
    match call.output {
      Some(output) =>
        note_contract(problems, step.id, "output_contract", schema, output)
      None =>
        problems.push(
          trace_problem(step.id, "missing_structured_output", Json::null()),
        )
    }
  }
  let (available, complete) = trace_sources(step, call, calls, input, problems)
  if complete {
    let expected = assembled(step, available)
    if !exact_equal(expected, call.arguments) {
      problems.push(
        trace_problem(
          step.id,
          "wrong_arguments",
          Json::object(
            Map([("expected", expected), ("actual", call.arguments)]),
          ),
        ),
      )
    }
  }
}

///|
fn trace_sources(
  step : Step,
  call : TraceCall,
  calls : Map[String, TraceCall],
  input : Json?,
  problems : Array[Json],
) -> (Map[String, Json], Bool) {
  let available : Map[String, Json] = Map([])
  let seen : Map[String, Bool] = Map([])
  let mut complete = true
  for binding in step.bindings {
    guard binding.source is Some(source) else { continue }
    if seen.contains(source) {
      continue
    }
    seen.set(source, true)
    if source == "$inputs" {
      match input {
        Some(value) => available.set(source, value)
        None => {
          problems.push(
            trace_problem(step.id, "missing_workflow_input", Json::null()),
          )
          complete = false
        }
      }
      continue
    }
    match calls.get(source) {
      Some(previous) if previous.position < call.position && !previous.failed =>
        match previous.output {
          Some(value) => available.set(source, value)
          None => {
            problems.push(
              trace_problem(step.id, "unavailable_output", Json::string(source)),
            )
            complete = false
          }
        }
      Some(previous) if previous.failed => {
        problems.push(
          trace_problem(step.id, "upstream_error", Json::string(source)),
        )
        complete = false
      }
      Some(_) => {
        problems.push(
          trace_problem(step.id, "out_of_order", Json::string(source)),
        )
        complete = false
      }
      None => {
        problems.push(
          trace_problem(step.id, "missing_upstream_call", Json::string(source)),
        )
        complete = false
      }
    }
  }
  (available, complete)
}

///|
pub fn check_trace(
  catalog : Json,
  plan : Json,
  trace : Json,
) -> Json raise CheckError {
  let ordered = order_steps(load_steps(catalog, plan))
  let events = read_trace(trace)
  let index : Map[String, Step] = Map([])
  let calls : Map[String, TraceCall] = Map([])
  for step in ordered {
    index.set(step.id, step)
  }
  for call in events {
    calls.set(call.id, call)
  }
  let problems : Array[Json] = []
  let input = field_at(trace, "inputs")
  if input is Some(value) && field_at(plan, "inputs") is Some(schema) {
    note_contract(problems, "$inputs", "workflow_input_contract", schema, value)
  }
  for call in events {
    match index.get(call.id) {
      Some(step) => inspect_trace_call(call, step, calls, input, problems)
      None =>
        problems.push(trace_problem(call.id, "unexpected_call", Json::null()))
    }
  }
  for step in ordered {
    if !calls.contains(step.id) {
      problems.push(trace_problem(step.id, "missing_call", Json::null()))
    }
  }
  let mut failures = 0
  let mut unknown = 0
  for problem in problems {
    let detail = field_at(problem, "detail").unwrap_or(Json::null())
    if field_at(detail, "status") == Some(Json::string("unknown")) {
      unknown += 1
    } else {
      failures += 1
    }
  }
  let status = if failures > 0 {
    "invalid"
  } else if unknown > 0 {
    "unknown"
  } else {
    "valid"
  }
  Json::object(
    Map([
      ("status", Json::string(status)),
      ("calls", Json::number(events.length().to_double())),
      ("failures", Json::number(failures.to_double())),
      ("unknown", Json::number(unknown.to_double())),
      ("problems", Json::array(problems)),
    ]),
  )
}
