///|
#borrow(args)
extern "C" fn spawn(args : Bytes) -> Int = "patchbay_spawn"

///|
#borrow(line)
extern "C" fn write_line(process : Int, line : Bytes) -> Unit = "patchbay_write_line"

///|
extern "C" fn read_line(process : Int) -> Bytes = "patchbay_read_line"

///|
extern "C" fn at_eof(process : Int) -> Bool = "patchbay_at_eof"

///|
/// Why not `nu -c` per input: each run would start from scratch, losing
/// variables and the working directory. The MCP server keeps one session.
pub fn nushell() -> @program.Program {
  let process = spawn(@utf8.encode("nu\u{0}--mcp"))
  let mut id = 0
  // Lines that are not the response are what external commands printed.
  let call = (name : String, params : Json) => {
    id += 1
    let request : Json = {
      "jsonrpc": "2.0",
      "id": id.to_json(),
      "method": name.to_json(),
      "params": params,
    }
    write_line(process, @utf8.encode(request.stringify()))
    let printed : Array[String] = []
    while true {
      let line = @utf8.decode_lossy(read_line(process))
      if at_eof(process) {
        break
      }
      match (@json.parse(line) catch { _ => null }) {
        { "id": Number(n, ..), "result": result, .. } if n == id.to_double() =>
          return (Some(result), printed)
        _ => printed.push(line)
      }
    }
    (None, printed)
  }
  let evaluate = (code : String) => {
    call("tools/call", {
      "name": "evaluate",
      "arguments": { "input": code.to_json() },
    })
  }
  if process >= 0 {
    call("initialize", {
      "protocolVersion": "2025-06-18",
      "capabilities": {},
      "clientInfo": { "name": "patchbay", "version": "0.1.0" },
    })
    |> ignore
    // Why not keep the default limit: larger outputs come back as a note
    // instead of data.
    evaluate("$env.NU_MCP_OUTPUT_LIMIT = 1gb") |> ignore
  }
  {
    name: "Nushell",
    kind: Interpreter(language="nu"),
    send: (input, _) => {
      if process < 0 {
        return { parts: [], error: Some("nu を起動できません"), }
      }
      if !input.attachments.is_empty() {
        return {
          parts: [],
          error: Some("Nushell には添付を渡せません"),
        }
      }
      let (result, printed) = evaluate(input.text)
      let parts : Array[@program.Part] = if printed.is_empty() {
        []
      } else {
        [Text(printed.join("\n"))]
      }
      match result {
        Some(
          {
            "isError": True,
            "structuredContent": { "msg": String(msg), .. },
            ..
          }
        ) => { parts, error: Some(msg), }
        Some({ "structuredContent": { "output": String(s), .. }, .. }) =>
          { parts: [..parts, Text(s)], error: None, }
        Some({ "structuredContent": { "output": v, .. }, .. }) =>
          { parts: [..parts, Data(v)], error: None, }
        Some({ "structuredContent": { "note": String(note), .. }, .. }) =>
          { parts, error: Some(note), }
        _ => { parts, error: Some("nu が応答しません"), }
      }
    },
  }
}
