///|
priv struct Nu {
  process : @process.Process
  to_nu : @process.WriteToProcess
  from_nu : @process.ReadFromProcess
  mut id : Int32
}

///|
async fn start(group : @async.TaskGroup[Unit]) -> Nu {
  let (stdin, to_nu) = @process.write_to_process()
  let (from_nu, stdout) = @process.read_from_process()
  let process = @process.spawn(
    group,
    "nu",
    ["--mcp"],
    stdin~,
    stdout~,
    stderr=@process.redirect_to_file("/dev/null"),
    no_wait=true,
  )
  let nu = { process, to_nu, from_nu, id: 0, }
  nu.call("initialize", {
    "protocolVersion": "2025-06-18",
    "capabilities": {},
    "clientInfo": { "name": "patchbay", "version": "0.1.0" },
  })
  |> ignore
  // Why not keep the default limit: larger outputs come back as a note
  // instead of data.
  nu.evaluate("$env.NU_MCP_OUTPUT_LIMIT = 1gb") |> ignore
  nu
}

///|
/// Why not drop lines that are not the response: they are what external
/// commands printed.
async fn Nu::call(
  self : Nu,
  name : String,
  params : Json,
) -> (Json, Array[String]) {
  self.id += 1
  let request : Json = {
    "jsonrpc": "2.0",
    "id": Json(self.id),
    "method": Json(name),
    "params": params,
  }
  self.to_nu.write(request.stringify() + "\n")
  let printed = []
  while self.from_nu.read_until("\n") is Some(line) {
    match (@json.parse(line) catch { _ => null }) {
      { "id": Number(n, ..), "result": result, .. } if n == self.id.to_double() =>
        return (result, printed)
      _ => printed.push(line)
    }
  }
  raise @program.Failure("nu が終了しました")
}

///|
async fn Nu::evaluate(self : Nu, code : String) -> (Json, Array[String]) {
  self.call("tools/call", {
    "name": "evaluate",
    "arguments": { "input": Json(code) },
  })
}

///|
/// Why not `nu -c` per input: each run would start from scratch, losing
/// variables and the working directory. The MCP server keeps one session.
pub async fn nushell(group : @async.TaskGroup[Unit]) -> @program.Program {
  let mut current = Some(start(group))
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
      let nu = match current {
        Some(nu) => nu
        None => {
          (session.emit)(
            Text(
              "前の入力を中断したため、新しいセッションで実行します",
            ),
          )
          let nu = start(group)
          current = Some(nu)
          nu
        }
      }
      // Why not let a cancelled input finish: nu would go on running it, side
      // effects included, and neither its cancel notice nor SIGINT stops an
      // evaluation without ending the session.
      let mut answered = false
      defer (if !answered {
        nu.process.cancel()
        current = None
      })
      let (result, printed) = nu.evaluate(input.text)
      answered = true
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
