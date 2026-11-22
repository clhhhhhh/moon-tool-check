///|
test "fractional multiples use exact decimal arithmetic" {
  let schema = parse_json("{\"type\":\"number\",\"multipleOf\":0.1}")
  assert_eq(validate_instance(schema, parse_json("0.3")), Some(true))
  assert_eq(
    validate_instance(schema, parse_json("0.30000000000000001")),
    Some(false),
  )
  assert_eq(validate_instance(schema, parse_json("-0.3")), Some(true))
}

///|
test "integers include mathematically integral exponent notation" {
  let schema = parse_json("{\"type\":\"integer\"}")
  assert_eq(validate_instance(schema, parse_json("1.00e2")), Some(true))
  assert_eq(validate_instance(schema, parse_json("1.01e-2")), Some(false))
}

///|
test "large nearby integers do not collapse into the same constant" {
  let schema = parse_json("{\"const\":9007199254740992}")
  assert_eq(
    validate_instance(schema, parse_json("9007199254740993")),
    Some(false),
  )
}

///|
test "stronger open interval implies weaker closed interval" {
  let source = parse_json("{\"type\":\"number\",\"exclusiveMinimum\":0.1}")
  let target = parse_json("{\"type\":\"number\",\"minimum\":0.1}")
  assert_true(compare_schemas(source, target) is Compatible)
}

///|
test "exclusive union rejects an overlapping match even for strings" {
  let schema = parse_json(
    "{\"oneOf\":[{\"type\":\"string\"},{\"const\":\"x\"}]}",
  )
  assert_eq(validate_instance(schema, Json::string("x")), Some(false))
  assert_eq(validate_instance(schema, Json::string("y")), Some(true))
}

///|
test "conditional and dependent object constraints locate missing keys" {
  let conditional = parse_json(
    (
      #| {"if":{"required":["a"]},"then":{"required":["b"]}}
    ),
  )
  let dependent = parse_json(
    (
      #| {"dependentSchemas":{"a":{"required":["b"]}}}
    ),
  )
  let value = parse_json("{\"a\":true}")
  for schema in [conditional, dependent] {
    let issue = field_at(explain_instance(schema, value), "violation").unwrap_or(
      Json::null(),
    )
    assert_eq(field_at(issue, "pointer"), Some(Json::string("/b")))
  }
}

///|
test "tuple items differ from homogeneous array tails" {
  let tuple = parse_json(
    (
      #| {"type":"array","minItems":2,"prefixItems":[{"type":"string"},{"type":"boolean"}],"items":false}
    ),
  )
  assert_eq(validate_instance(tuple, parse_json("[\"yes\",true]")), Some(true))
  assert_eq(validate_instance(tuple, parse_json("[true,\"yes\"]")), Some(false))
  assert_eq(
    validate_instance(tuple, parse_json("[\"yes\",true,0]")),
    Some(false),
  )
}

///|
test "finite sources retain correlation through repeated bindings" {
  let catalog = parse_json(
    (
      #| {"s":{"tools":[
      #| {"name":"sink","inputSchema":{"type":"object","enum":[{"a":true,"b":true},{"a":false,"b":false}]}}
      #| ]}}
    ),
  )
  let plan = parse_json(
    (
      #| {"inputs":{"type":"boolean"},"steps":[
      #| {"id":"sink","server":"s","tool":"sink","args":{"a":{"input":""},"b":{"input":""}}}
      #| ]}
    ),
  )
  assert_true(
    check_workflow(catalog, plan) is Array([Object(result)]) &&
    result.get("status") == Some(Json::string("compatible")),
  )
}

///|
test "RFC 6901 array path and workflow inputs produce replayable evidence" {
  let catalog = parse_json(
    (
      #| {"s":{"tools":[{"name":"sink","inputSchema":{"type":"object","properties":{"id":{"type":"string"}},"required":["id"]}}]}}
    ),
  )
  let plan = parse_json(
    (
      #| {"inputs":{"const":{"rows":[null]}},"steps":[
      #| {"id":"sink","server":"s","tool":"sink","args":{"id":{"input":"/rows/0"}}}
      #| ]}
    ),
  )
  let bundle = export_witnesses(catalog, plan)
  let checked = verify_witnesses(catalog, plan, bundle)
  assert_eq(field_at(checked, "verified"), Some(Json::number(1.0)))
}

///|
test "removed tools surface as a verified structural regression" {
  let catalog = parse_json(
    (
      #| {"s":{"tools":[{"name":"sink","inputSchema":{"type":"object"}}]}}
    ),
  )
  let without_tool = parse_json("{\"s\":{\"tools\":[]}}")
  let plan = parse_json(
    (
      #| {"steps":[{"id":"sink","server":"s","tool":"sink","args":{}}]}
    ),
  )
  let report = compare_workflow(catalog, without_tool, plan)
  assert_eq(report_exit_status(report, Upgrade, Default), 1)
  let checked = verify_upgrade_witnesses(without_tool, plan, report)
  assert_eq(field_at(checked, "verified"), Some(Json::number(1.0)))
}

///|
test "trace validation rejects a fabricated downstream argument" {
  let catalog = parse_json(
    (
      #| {"s":{"tools":[{"name":"sink","inputSchema":{"type":"object"}}]}}
    ),
  )
  let plan = parse_json(
    (
      #| {"inputs":{"type":"string"},"steps":[{"id":"sink","server":"s","tool":"sink","args":{"id":{"input":""}}}]}
    ),
  )
  let trace = parse_json(
    (
      #| {"inputs":"expected","calls":[{"step":"sink","arguments":{"id":"different"}}]}
    ),
  )
  let result = check_trace(catalog, plan, trace)
  assert_eq(field_at(result, "status"), Some(Json::string("invalid")))
}

///|
test "catalog import includes all pages without dropping cursor state silently" {
  let pages = parse_json(
    (
      #| {"s":[{"result":{"tools":[{"name":"one","inputSchema":true}],"nextCursor":"more"}},
      #| {"result":{"tools":[{"name":"two","inputSchema":true}]}}]}
    ),
  )
  assert_eq(catalog_tools(pages).length(), 2)
  assert_eq(catalog_tools(normalize_catalog(pages)).length(), 2)
}
