// Use the public validation entry point to exercise exact numeric parsing.

///|
test "uniqueItems uses JSON equality recursively" {
  let schema = parse_json("{\"uniqueItems\":true}")
  let duplicate = parse_json(
    (
      #| [{"a":[1.000e0,-0],"b":"n1:1e0;"},{"b":"n1:1e0;","a":[1,0]}]
    ),
  )
  let distinct = parse_json(
    (
      #| [9007199254740992,9007199254740993,[1,2],[2,1],{"x":2},{"x":3}]
    ),
  )
  assert_eq(validate_instance(schema, duplicate), Some(false))
  assert_eq(validate_instance(schema, distinct), Some(true))
  let result = explain_instance(schema, duplicate)
  let problem = required_member(result, "violation")
  assert_eq(field_at(problem, "pointer"), Some(Json::string("/1")))
}

///|
test "workflow rejects ambiguous and misspelled bindings" {
  let catalog = parse_json(
    (
      #| {"s":{"tools":[{"name":"t","inputSchema":true}]}}
    ),
  )
  for
    binding in [
      (
        #| {"literal":1,"inpt":"/id"}
      ),
      (
        #| {"from":"$inputs","pointer":"/id"}
      ),
      (
        #| {"literal":1,"pointer":""}
      ),
    ] {
    let head =
      #| {"inputs":true,"steps":[{"id":"t","server":"s","tool":"t","args":{"a":
    let plan = parse_json(head + binding + "}}]}")
    let rejected = try {
      ignore(check_workflow(catalog, plan))
      false
    } catch {
      Invalid(_) => true
    }
    assert_true(rejected)
  }
}

///|
test "batch replay verifies repeated sources and reports tampering per entry" {
  let catalog = parse_json(
    (
      #| {"s":{"tools":[{"name":"t","inputSchema":{"properties":{"a":{"type":"boolean"}}}}]}}
    ),
  )
  let plan = parse_json(
    (
      #| {"inputs":{"const":"wrong"},"steps":[
      #| {"id":"a","server":"s","tool":"t","args":{"a":{"input":""},"b":{"input":""}}},
      #| {"id":"b","server":"s","tool":"t","args":{"a":{"input":""}}}
      #| ]}
    ),
  )
  let bundle = export_witnesses(catalog, plan)
  assert_eq(
    field_at(verify_witnesses(catalog, plan, bundle), "verified"),
    Some(Json::number(2.0)),
  )
  let corrupted = parse_json(
    (
      #| {"version":1,"entries":[
      #| {"step":"a","witness":{"request":{"a":"wrong","b":"wrong"},"outputs":{"$inputs":"wrong"}}},
      #| {"step":"b","witness":{"request":{"a":"changed"},"outputs":{"$inputs":"wrong"}}}
      #| ]}
    ),
  )
  let replay = verify_witnesses(catalog, plan, corrupted)
  assert_eq(field_at(replay, "verified"), Some(Json::number(1.0)))
  assert_eq(field_at(replay, "invalid"), Some(Json::number(1.0)))
}
