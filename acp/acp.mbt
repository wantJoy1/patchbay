///|
priv struct Turn {
  session : @program.Session
  text : StringBuilder
}

///|
/// Why not emit each chunk as it comes: a chunk is a fragment of Markdown,
/// and a part is drawn as a whole document.
fn Turn::flush(self : Turn) -> Unit {
  let text = self.text.to_string()
  self.text.reset()
  if text.trim() != "" {
    (self.session.emit)(Markdown(text))
  }
}

///|
fn Turn::update(self : Turn, update : Json) -> Unit {
  match update {
    {
      "sessionUpdate": "agent_message_chunk",
      "content": { "type": "text", "text": String(t), .. },
      ..
    } => self.text.write_string(t)
    { "sessionUpdate": "tool_call", .. } => self.flush()
    _ => ()
  }
}

///|
priv struct Agent {
  to_agent : @process.WriteToProcess
  responses : @aqueue.Queue[Json]
  mut id : Int32
  mut turn : Turn?
  mut options : Array[@program.Setting]
}

///|
async fn Agent::write(self : Agent, message : Json) -> Unit {
  self.to_agent.write(message.stringify() + "\n")
}

///|
/// Why not match responses to requests in a table: requests go one at a
/// time, and a response left from a cancelled prompt is skipped by its id.
async fn Agent::call(self : Agent, name : String, params : Json) -> Json {
  self.id += 1
  let id = self.id.to_double()
  self.write({
    "jsonrpc": "2.0",
    "id": Json(self.id),
    "method": Json(name),
    "params": params,
  })
  for ;; {
    match self.responses.get() {
      { "id": Number(n, ..), "result": result, .. } if n == id => return result
      { "id": Number(n, ..), "error": { "message": String(msg), .. }, .. } if n ==
        id => raise @program.Failure(msg)
      _ => continue
    }
  }
}

///|
async fn Agent::read(
  self : Agent,
  from_agent : @process.ReadFromProcess,
) -> Unit {
  while from_agent.read_until("\n") is Some(line) {
    let message = @json.parse(line) catch { _ => continue }
    match message {
      {
        "method": "session/update",
        "params": {
          "update": {
            "sessionUpdate": "config_option_update",
            "configOptions": options,
            ..
          },
          ..
        },
        ..
      } => self.options = settings(options)
      { "method": "session/update", "params": { "update": update, .. }, .. } =>
        if self.turn is Some(turn) {
          turn.update(update)
        }
      { "method": "session/request_permission", "id": id, "params": params, .. } =>
        self.write({
          "jsonrpc": "2.0",
          "id": id,
          "result": { "outcome": refusal(params) },
        })
      { "method": String(_), "id": id, .. } =>
        self.write({
          "jsonrpc": "2.0",
          "id": id,
          "error": { "code": -32601, "message": "patchbay does not offer this" },
        })
      { "method": String(_), .. } => ()
      _ => self.responses.put(message)
    }
  }
  self.responses.close(
    error=@program.Failure("エージェントが終了しました"),
  )
}

///|
/// Why not allow: whatever the agent should do goes through patchbay's tool,
/// so a request for anything else is refused.
fn refusal(params : Json) -> Json {
  if params is { "options": Array(options), .. } {
    for option in options {
      if option is { "kind": String(kind), "optionId": id, .. } &&
        kind.has_prefix("reject") {
        return { "outcome": "selected", "optionId": id }
      }
    }
  }
  { "outcome": "cancelled" }
}

///|
fn part_json(part : @program.Part) -> Json {
  match part {
    Data(v) => v
    Text(s) | Markdown(s) | Mermaid(s) => Json(s)
    Html(_) => "(HTML page)"
    Image(_) => "(image)"
    Audio(_) => "(audio)"
    File(a) => Json("(file \{a.name})")
  }
}

///|
/// Why not the parts as a list when there is one: most replies are a single
/// value, and wrapping it hides its shape.
fn reply_json(reply : @program.Reply) -> Json {
  match reply.parts {
    [part] => part_json(part)
    parts => Json(parts.map(part_json))
  }
}

///|
fn exchange_json(e : @program.Exchange) -> Json {
  let fields : Map[String, Json] = {
    "program": Json(e.program),
    "input": Json(e.input.text),
    "output": reply_json(e.reply),
  }
  if e.reply.error is Some(msg) {
    fields["error"] = Json(msg)
  }
  Json(fields)
}

///|
fn attachment(a : @program.Attachment) -> Json {
  if a.is_text() {
    return {
      "type": "resource",
      "resource": {
        "uri": Json("file:///\{a.name}"),
        "mimeType": Json(a.media_type),
        "text": Json(a.data),
      },
    }
  }
  let data = match a.data.find(",") {
    Some(i) => a.data.view(start_offset=i + 1).to_owned()
    None => a.data
  }
  if a.media_type.has_prefix("image/") {
    { "type": "image", "mimeType": Json(a.media_type), "data": Json(data) }
  } else {
    {
      "type": "resource",
      "resource": {
        "uri": Json("file:///\{a.name}"),
        "mimeType": Json(a.media_type),
        "blob": Json(data),
      },
    }
  }
}

///|
/// Why not leave the agent to find patchbay's tool: some agents reach tools
/// through a layer of their own and, not seeing it listed there, answer
/// without running anything.
fn prompt(
  input : @program.Input,
  unseen : Array[@program.Exchange],
  first~ : Bool,
) -> Json {
  let blocks : Array[Json] = []
  if first {
    blocks.push({
      "type": "text",
      "text": "To run code, call the `run` tool of the `patchbay` MCP server, even if it does not appear when you list your tools. It runs in the interpreters the user works in, and the user sees what it prints.",
    })
  }
  if !unseen.is_empty() {
    let exchanges = Json(unseen.map(exchange_json)).stringify()
    blocks.push({
      "type": "text",
      "text": Json(
        "Since your last turn, the user ran these in patchbay:\n\{exchanges}",
      ),
    })
  }
  blocks.append(input.attachments.map(attachment))
  if input.text != "" {
    blocks.push({ "type": "text", "text": Json(input.text) })
  }
  Json(blocks)
}

///|
fn choices(options : Json) -> Array[@program.Choice] {
  guard options is Array(options) else { return [] }
  let flat = []
  for option in options {
    match option {
      { "value": String(value), "name": String(name), .. } =>
        flat.push(@program.Choice::{ value, name, })
      { "options": inner, .. } => flat.append(choices(inner))
      _ => ()
    }
  }
  flat
}

///|
/// Why not booleans too: the agent sends them only to clients that say they
/// draw them, and patchbay does not.
fn settings(options : Json) -> Array[@program.Setting] {
  guard options is Array(options) else { return [] }
  options.filter_map(o => {
    match o {
      {
        "id": String(id),
        "name": String(name),
        "currentValue": String(value),
        "options": list,
        ..
      } => Some(@program.Setting::{ id, name, value, choices: choices(list), })
      _ => None
    }
  })
}

///|
/// Why not spawn the agent for each input: its session and the context it
/// has built would be lost. Why not start the session at the first input:
/// its settings, such as the model, are to be chosen before it.
pub async fn agent(
  group : @async.TaskGroup[Unit],
  name~ : String,
  command~ : String,
  args~ : Array[String],
  env~ : Map[String, String],
  interpreters~ : Array[(String, @program.Kind)],
) -> @program.Program {
  let (stdin, to_agent) = @process.write_to_process()
  let (from_agent, stdout) = @process.read_from_process()
  @process.spawn(
    group,
    command,
    args,
    extra_env=env,
    stdin~,
    stdout~,
    stderr=@process.redirect_to_file("/dev/null"),
    no_wait=true,
  )
  |> ignore
  let agent : Agent = {
    to_agent,
    responses: @aqueue.Queue(kind=Unbounded),
    id: 0,
    turn: None,
    options: [],
  }
  group.spawn_bg(no_wait=true, () => agent.read(from_agent))
  agent.call("initialize", {
    "protocolVersion": 1,
    "clientCapabilities": {
      "fs": { "readTextFile": false, "writeTextFile": false },
      "terminal": false,
    },
    "clientInfo": { "name": "patchbay", "version": "0.1.0" },
  })
  |> ignore
  let token = random_token()
  let port = serve(group, token, message => {
    mcp(message, interpreters, agent.turn)
  })
  let created = agent.call("session/new", {
    "cwd": Json(@fs.realpath(".")),
    "mcpServers": [
      {
        "type": "http",
        "name": "patchbay",
        "url": Json("http://127.0.0.1:\{port}/mcp"),
        "headers": [
          { "name": "Authorization", "value": Json("Bearer \{token}") },
        ],
      },
    ],
  })
  guard created is { "sessionId": String(id), .. } else {
    raise @program.Failure(
      "エージェントがセッションを作れません",
    )
  }
  if created is { "configOptions": options, .. } {
    agent.options = settings(options)
  }
  let lock = @async.Mutex()
  let mut first = true
  {
    name,
    kind: Agent,
    send: (input, session) => {
      lock.acquire()
      defer lock.release()
      let turn = { session, text: StringBuilder(), }
      agent.turn = Some(turn)
      defer {
        agent.turn = None
      }
      errdefer @async.protect_from_cancel(() => {
        agent.write({
          "jsonrpc": "2.0",
          "method": "session/cancel",
          "params": { "sessionId": Json(id) },
        })
      })
      agent.call("session/prompt", {
        "sessionId": Json(id),
        "prompt": prompt(input, session.unseen, first~),
      })
      |> ignore
      first = false
      turn.flush()
    },
    settings: Some({
      current: () => agent.options,
      change: (config, value) => {
        lock.acquire()
        defer lock.release()
        let changed = agent.call("session/set_config_option", {
          "sessionId": Json(id),
          "configId": Json(config),
          "value": Json(value),
        })
        if changed is { "configOptions": options, .. } {
          agent.options = settings(options)
        }
      },
    }),
  }
}
