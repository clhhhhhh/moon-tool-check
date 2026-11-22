///|
test "public API finds and verifies upgrade failure" {
  let catalogue = @moon-tool-check.parse_json(
    (
      #| {"s":{"tools":[
      #| {"name":"read","inputSchema":{"type":"object"},"outputSchema":{"type":"object","properties":{"id":{"type":["string","null"]}},"required":["id"]}},
      #| {"name":"consume","inputSchema":{"type":"object","properties":{"id":{"type":"string"}},"required":["id"]}}
      #| ]}}
    ),
  )
  let workflow = @moon-tool-check.parse_json(
    (
      #| {"steps":[
      #| {"id":"b","server":"s","tool":"consume","args":{"id":{"from":"a","pointer":"/id"}}},
      #| {"id":"a","server":"s","tool":"read","args":{}}
      #| ]}
    ),
  )
  let result = @moon-tool-check.check_workflow(catalogue, workflow)
  guard result is Array([_, Object(fields)]) &&
    fields.get("witness") is Some(witness) else {
    fail("missing verified counterexample")
  }
  assert_true(
    @moon-tool-check.verify_witness(catalogue, workflow, "b", witness),
  )
  let tampered = @moon-tool-check.parse_json(
    (
      #| {"outputs":{"a":{"id":null}},"request":{"id":"changed"}}
    ),
  )
  assert_false(
    @moon-tool-check.verify_witness(catalogue, workflow, "b", tampered),
  )
}
