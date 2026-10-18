///|
/// Why not `nu -c` per input: each run would start from scratch, losing
/// variables and the working directory. The MCP server keeps one session.
pub async fn nushell(group : @async.TaskGroup[Unit]) -> @program.Program {
  let (stdin, to_nu) = @process.write_to_process()
  let (from_nu, stdout) = @process.read_from_process()
  @process.spawn(
    group,
    "nu",
    ["--mcp"],
    stdin~,
    stdout~,
    stderr=@process.redirect_to_file("/dev/null"),
    no_wait=true,
  )
  |> ignore
  let mut id = 0
  // Why not drop lines that are not responses: they are what external
  // commands printed.
  async fn call(name : String, params : Json) -> (Json, Array[String]) {
    id += 1
    let request : Json = {
      "jsonrpc": "2.0",
      "id": Json(id),
      "method": Json(name),
      "params": params,
    }
    to_nu.write(request.stringify() + "\n")
    let printed = []
    while from_nu.read_until("\n") is Some(line) {
      match (@json.parse(line) catch { _ => null }) {
        { "id": Number(n, ..), "result": result, .. } if n == id.to_double() =>
          return (result, printed)
        // Why not treat every line as printed: a response to a cancelled
        // request may still arrive.
        { "jsonrpc": _, .. } => ()
        _ => printed.push(line)
      }
    }
    raise @program.Failure("nu が終了しました")
  }
  async fn evaluate(code : String) -> (Json, Array[String]) {
    let current = id + 1
    errdefer (if @async.is_being_cancelled() {
      @async.protect_from_cancel(() => {
        let notice : Json = {
          "jsonrpc": "2.0",
          "method": "notifications/cancelled",
          "params": { "requestId": Json(current) },
        }
        to_nu.write(notice.stringify() + "\n")
      })
    })
    call("tools/call", {
      "name": "evaluate",
      "arguments": { "input": Json(code) },
    })
  }

  call("initialize", {
    "protocolVersion": "2025-06-18",
    "capabilities": {},
    "clientInfo": { "name": "patchbay", "version": "0.1.0" },
  })
  |> ignore
  // Why not keep the default limit: larger outputs come back as a note
  // instead of data.
  evaluate("$env.NU_MCP_OUTPUT_LIMIT = 1gb") |> ignore
  let lock = @async.Mutex()
  {
    name: "Nushell",
    kind: Interpreter(language="nu"),
    send: (input, session) => {
      guard input.attachments.is_empty() else {
        raise @program.Failure("Nushell には添付を渡せません")
      }
      lock.acquire()
      defer lock.release()
      let (result, printed) = evaluate(input.text)
      if !printed.is_empty() {
        (session.emit)(Text(printed.join("\n")))
      }
      match result {
        { "isError": True, "structuredContent": { "msg": String(msg), .. }, .. } =>
          raise @program.Failure(msg)
        { "structuredContent": { "output": String(s), .. }, .. } =>
          (session.emit)(Text(s))
        { "structuredContent": { "output": v, .. }, .. } =>
          (session.emit)(Data(v))
        { "structuredContent": { "note": String(note), .. }, .. } =>
          raise @program.Failure(note)
        _ => raise @program.Failure("nu の応答を解釈できません")
      }
    },
  }
}
