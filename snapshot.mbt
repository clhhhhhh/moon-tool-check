///|
fn unwrap_page(page : Json) -> Json raise CheckError {
  ignore(object_value(page))
  if field_at(page, "error") is Some(_) {
    raise Invalid("MCP snapshot contains a JSON-RPC error")
  }
  if field_at(page, "jsonrpc") is Some(version) &&
    version != Json::string("2.0") {
    raise Invalid("Unsupported JSON-RPC version in snapshot")
  }
  let payload = field_at(page, "result").unwrap_or(page)
  ignore(object_value(payload))
  payload
}

///|
fn catalog_pages(snapshot : Json) -> Array[Json] raise CheckError {
  let pages = match snapshot {
    Array(values) => values
    Object(_) => [snapshot]
    _ =>
      raise Invalid(
        "Catalog must contain a tools/list response or a list of pages",
      )
  }
  if pages.length() == 0 || pages.length() > 256 {
    raise Invalid("Catalog must contain between 1 and 256 pages")
  }
  let result : Array[Json] = []
  let cursors : Map[String, Bool] = Map([])
  for i, page in pages {
    let payload = unwrap_page(page)
    let cursor = field_at(payload, "nextCursor")
    match cursor {
      Some(String(token)) => {
        if token == "" || cursors.contains(token) {
          raise Invalid("Invalid or repeated nextCursor in snapshot")
        }
        if i + 1 == pages.length() {
          raise Invalid("Incomplete snapshot: remaining MCP tools/list page")
        }
        cursors.set(token, true)
      }
      None if i + 1 == pages.length() => ()
      None => raise Invalid("Unexpected MCP page after the final page")
      _ => raise Invalid("nextCursor must be a string")
    }
    result.append(array_value(required_member(payload, "tools")))
  }
  result
}

///|
fn catalog_tools(catalog : Json) -> Map[String, Json] raise CheckError {
  let tools : Map[String, Json] = Map([])
  for server, snapshot in object_value(catalog) {
    if server == "" {
      raise Invalid("Server name must not be empty")
    }
    for tool in catalog_pages(snapshot) {
      let name = string_value(required_member(tool, "name"))
      if name == "" {
        raise Invalid("Tool name must not be empty")
      }
      let key = tool_key(server, name)
      if tools.contains(key) {
        raise Invalid("Duplicate tool: " + key)
      }
      ignore(required_member(tool, "inputSchema"))
      tools.set(key, tool)
    }
  }
  tools
}

///|
fn tool_key(server : String, name : String) -> String {
  Json::array([Json::string(server), Json::string(name)]).stringify()
}

///|
pub fn normalize_catalog(catalog : Json) -> Json raise CheckError {
  ignore(catalog_tools(catalog))
  let output : Map[String, Json] = Map([])
  for server, snapshot in object_value(catalog) {
    output.set(
      server,
      Json::object(Map([("tools", Json::array(catalog_pages(snapshot)))])),
    )
  }
  Json::object(output)
}
