///|
async fn random_token() -> String {
  let file = @fs.open("/dev/urandom", mode=ReadOnly)
  defer file.close()
  let digits = "0123456789abcdef"
  let token = StringBuilder()
  for b in file.read_exactly(16) {
    token.write_char(digits.get_char(b.to_int() / 16).unwrap())
    token.write_char(digits.get_char(b.to_int() % 16).unwrap())
  }
  token.to_string()
}

///|
/// Why not stdio: the agent would start the server as a process of its own,
/// apart from the window that draws what it runs. Why not leave the port
/// open to any request: any local process could then run code as the user.
async fn serve(
  group : @async.TaskGroup[Unit],
  token : String,
  handle : async (Json) -> Json?,
) -> Int32 {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  group.spawn_bg(no_wait=true, () => {
    server.run_forever(allow_failure=true, (request, body, conn) => {
      guard request.meth is Post else {
        conn.send_response(405, "Method Not Allowed")
        return
      }
      guard request.headers.get("authorization") is Some(auth) &&
        auth == "Bearer \{token}" else {
        conn.send_response(401, "Unauthorized")
        return
      }
      let message = @json.parse(body.read_all().text()) catch {
        _ => {
          conn.send_response(400, "Bad Request")
          return
        }
      }
      match handle(message) {
        Some(reply) => {
          conn.send_response(200, "OK", extra_headers={
            "content-type": "application/json",
          })
          conn.write(reply.stringify())
        }
        None => conn.send_response(202, "Accepted")
      }
    })
  })
  server.addr.port()
}

///|
fn run_tool(programs : Array[(String, @program.Kind)]) -> Json {
  let names = programs.map(p => {
    match p.1 {
      Interpreter(language~) => "\{p.0} (\{language})"
      Agent => p.0
    }
  })
  {
    "name": "run",
    "description": Json(
      "Run code in an interpreter the user also works in. It shares the user's session (variables, working directory), and the user sees its output. Interpreters: \{names.join(", ")}.",
    ),
    "inputSchema": {
      "type": "object",
      "properties": {
        "program": {
          "type": "string",
          "enum": Json(programs.map(p => Json(p.0))),
        },
        "code": { "type": "string" },
      },
      "required": ["program", "code"],
    },
  }
}

///|
fn tool_result(text : String, error~ : Bool) -> Json {
  {
    "content": [{ "type": "text", "text": Json(text) }],
    "isError": Json(error),
  }
}

///|
async fn call_tool(params : Json, turn : Turn?) -> Json {
  guard params
    is {
      "name": "run",
      "arguments": { "program": String(program), "code": String(code), .. },
      ..
    } else {
    return tool_result("expected `program` and `code`", error=true)
  }
  guard turn is Some(turn) else {
    return tool_result("the user is not waiting on a turn", error=true)
  }
  turn.flush()
  let reply = (turn.session.run)(program, { text: code, attachments: [], })
  match reply.error {
    Some(msg) => tool_result(msg, error=true)
    None => tool_result(reply_json(reply).stringify(), error=false)
  }
}

///|
/// Why not answer only the latest protocol version: agents ship MCP clients
/// of different ages, and each asks for the version it speaks.
async fn mcp(
  message : Json,
  programs : Array[(String, @program.Kind)],
  turn : Turn?,
) -> Json? {
  guard message is { "id": id, "method": String(name), .. } else { return None }
  let params = match message {
    { "params": params, .. } => params
    _ => {}
  }
  let result : Json = match name {
    "initialize" =>
      {
        "protocolVersion": match params {
          { "protocolVersion": v, .. } => v
          _ => "2025-06-18"
        },
        "capabilities": { "tools": {} },
        "serverInfo": { "name": "patchbay", "version": "0.1.0" },
      }
    "ping" => {}
    "tools/list" => { "tools": [run_tool(programs)] }
    "tools/call" => call_tool(params, turn)
    _ =>
      return Some({
        "jsonrpc": "2.0",
        "id": id,
        "error": { "code": -32601, "message": Json("unknown method: \{name}") },
      })
  }
  Some({ "jsonrpc": "2.0", "id": id, "result": result })
}
