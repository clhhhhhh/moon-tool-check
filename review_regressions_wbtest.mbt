///|
test "local references decode URI fragments before JSON Pointer escapes" {
  let schema = parse_json(
    (
      #| {"$defs":{"a b":{"type":"integer"},"a%20b":{"type":"string"}},"$ref":"#/$defs/a%20b"}
    ),
  )
  assert_eq(validate_instance(schema, Json::string("text")), Some(false))
  assert_eq(validate_instance(schema, Json::number(12.0)), Some(true))
  let unicode = parse_json(
    (
      #| {"$defs":{"\u4e2d/word":false},"$ref":"#%2F$defs%2F%E4%B8%AD~1word"}
    ),
  )
  assert_eq(validate_instance(unicode, Json::null()), Some(false))
}

///|
test "malformed reference fragments remain unknown" {
  let schema = parse_json(
    (
      #| {"$defs":{"bad%FF":false},"$ref":"#/$defs/bad%FF"}
    ),
  )
  assert_eq(validate_instance(schema, Json::null()), None)
  let incomplete = parse_json(
    (
      #| {"$defs":{"bad%2":false},"$ref":"#/$defs/bad%2"}
    ),
  )
  assert_eq(validate_instance(incomplete, Json::null()), None)
}

///|
test "workflow cannot prove compatibility against incorrectly encoded reference name" {
  let catalog = parse_json(
    (
      #| {"s":{"tools":[
      #| {"name":"source","inputSchema":true,"outputSchema":{
      #| "$defs":{"a b":{"type":"integer"},"a%20b":{"type":"string"}},
      #| "$ref":"#/$defs/a%20b"}},
      #| {"name":"sink","inputSchema":{"required":["x"],"properties":{"x":{"type":"string"}}}}
      #| ]}}
    ),
  )
  let plan = parse_json(
    (
      #| {"steps":[{"id":"source","server":"s","tool":"source","args":{}},
      #| {"id":"sink","server":"s","tool":"sink","args":{"x":{"from":"source","pointer":""}}}]}
    ),
  )
  let result = check_workflow(catalog, plan)
  assert_eq(
    field_at(array_value(result)[1], "status"),
    Some(Json::string("incompatible")),
  )
}

///|
test "strict upgrade explanation rejects an existing unknown" {
  let catalog = parse_json(
    (
      #| {"s":{"tools":[{"name":"tool","inputSchema":true}]}}
    ),
  )
  let plan = parse_json(
    (
      #| {"steps":[{"id":"a","server":"s","tool":"tool","args":{}},
      #| {"id":"b","server":"s","tool":"tool","args":{"x":{"from":"a","pointer":""}}}]}
    ),
  )
  let comparison = compare_workflow(catalog, catalog, plan)
  let explanation = explain_upgrade(catalog, catalog, plan)
  assert_eq(status_of(explanation), "unknown")
  assert_eq(field_at(explanation, "lostProofs"), Some(Json::number(0.0)))
  assert_eq(report_exit_status(comparison, Upgrade, Strict), 1)
  assert_eq(report_exit_status(explanation, Instance, Strict), 1)
  assert_eq(report_exit_status(explanation, Instance, Default), 0)
}

///|
test "identical trace with two upstream failures has no changes" {
  let catalog = parse_json(
    (
      #| {"s":{"tools":[{"name":"tool","inputSchema":true}]}}
    ),
  )
  let plan = parse_json(
    (
      #| {"steps":[{"id":"a","server":"s","tool":"tool","args":{}},
      #| {"id":"b","server":"s","tool":"tool","args":{}},
      #| {"id":"c","server":"s","tool":"tool","args":{
      #| "x":{"from":"a","pointer":""},"y":{"from":"b","pointer":""}}}]}
    ),
  )
  let trace = parse_json(
    (
      #| {"calls":[{"step":"a","arguments":{},"isError":true},
      #| {"step":"b","arguments":{},"isError":true},{"step":"c","arguments":{}}]}
    ),
  )
  let result = compare_trace(catalog, catalog, plan, trace)
  assert_eq(array_value(required_member(result, "changes")).length(), 0)
}
