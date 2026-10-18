///|
fn turn(
  parts : Array[@program.Part],
  ran : Array[(String, String)],
  reply~ : @program.Reply = { parts: [Data(19)], error: None, },
) -> Turn {
  {
    session: {
      unseen: [],
      programs: [],
      emit: p => parts.push(p),
      run: (name, input) => {
        ran.push((name, input.text))
        reply
      },
    },
    text: StringBuilder(),
  }
}

///|
let programs : Array[(String, @program.Kind)] = [
  ("Nushell", Interpreter(language="nu")),
]

///|
test "a permission request is refused with the agent's own reject option" {
  assert_eq(
    refusal({
      "options": [
        { "kind": "allow_once", "optionId": "a" },
        { "kind": "reject_once", "optionId": "r" },
      ],
    }),
    { "outcome": "selected", "optionId": "r" },
  )
  assert_eq(refusal({ "options": [] }), { "outcome": "cancelled" })
}

///|
test "the first prompt names the tool, then what the user ran, then the input" {
  let unseen : Array[@program.Exchange] = [
    {
      program: "Nushell",
      input: { text: "ls | length", attachments: [], },
      reply: { parts: [Data(3)], error: None, },
    },
  ]
  let input : @program.Input = {
    text: "why?",
    attachments: [
      { name: "a.txt", media_type: "text/plain", data: "hi", },
      {
        name: "b.png",
        media_type: "image/png",
        data: "data:image/png;base64,AAAA",
      },
    ],
  }
  guard prompt(input, unseen, first=true) is Array(blocks) else { fail("") }
  assert_eq(blocks.length(), 5)
  assert_true(
    blocks[0] is { "text": String(t), .. } && t.contains("`patchbay`"),
  )
  assert_true(
    blocks[1] is { "text": String(t), .. } &&
    t.contains(
      "{\"program\":\"Nushell\",\"input\":\"ls | length\",\"output\":3}",
    ),
  )
  assert_eq(blocks[2], {
    "type": "resource",
    "resource": {
      "uri": "file:///a.txt",
      "mimeType": "text/plain",
      "text": "hi",
    },
  })
  assert_eq(blocks[3], {
    "type": "image",
    "mimeType": "image/png",
    "data": "AAAA",
  })
  assert_eq(blocks[4], { "type": "text", "text": "why?" })
  assert_eq(prompt({ text: "go", attachments: [], }, [], first=false), [
    { "type": "text", "text": "go" },
  ])
}

///|
test "message chunks become one Markdown part, split where a tool is called" {
  let parts = []
  let t = turn(parts, [])
  let chunk = (s : String) => {
    t.update({
      "sessionUpdate": "agent_message_chunk",
      "content": { "type": "text", "text": Json(s) },
    })
  }
  chunk("| a |\n")
  chunk("| - |\n")
  t.update({ "sessionUpdate": "tool_call", "toolCallId": "1" })
  chunk("done")
  chunk("\n")
  t.flush()
  t.flush()
  assert_eq(parts, [Markdown("| a |\n| - |\n"), Markdown("done\n")])
}

///|
async test "the run tool runs code in the user's interpreter and returns data" {
  let parts = []
  let ran = []
  let t = turn(parts, ran)
  t.text.write_string("Counting.")
  let call : Json = {
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/call",
    "params": {
      "name": "run",
      "arguments": { "program": "Nushell", "code": "ls | length" },
    },
  }
  assert_eq(
    mcp(call, programs, Some(t)),
    Some({
      "jsonrpc": "2.0",
      "id": 2,
      "result": {
        "content": [{ "type": "text", "text": "19" }],
        "isError": false,
      },
    }),
  )
  assert_eq(ran, [("Nushell", "ls | length")])
  assert_eq(parts, [Markdown("Counting.")])
  let failing = turn([], [], reply={ parts: [], error: Some("boom"), })
  assert_true(
    mcp(call, programs, Some(failing))
    is Some(
      {
        "result": { "isError": true, "content": [{ "text": "boom", .. }], .. },
        ..
      }
    ),
  )
  assert_true(
    mcp(call, programs, None) is Some({ "result": { "isError": true, .. }, .. }),
  )
}

///|
async test "the server answers the handshake and lists one tool over the interpreters" {
  assert_true(
    mcp(
      {
        "jsonrpc": "2.0",
        "id": 0,
        "method": "initialize",
        "params": { "protocolVersion": "2025-11-25" },
      },
      programs,
      None,
    )
    is Some({ "result": { "protocolVersion": "2025-11-25", .. }, .. }),
  )
  assert_eq(
    mcp(
      { "jsonrpc": "2.0", "method": "notifications/initialized" },
      programs,
      None,
    ),
    None,
  )
  guard mcp(
      { "jsonrpc": "2.0", "id": 1, "method": "tools/list" },
      programs,
      None,
    )
    is Some({ "result": { "tools": [tool], .. }, .. }) else {
    fail("")
  }
  assert_true(
    tool
    is {
      "name": "run",
      "inputSchema": {
        "properties": { "program": { "enum": ["Nushell"], .. }, .. },
        ..
      },
      ..
    },
  )
  assert_true(
    mcp(
      { "jsonrpc": "2.0", "id": 3, "method": "resources/list" },
      programs,
      None,
    )
    is Some({ "error": { "code": -32601, .. }, .. }),
  )
}

///|
test "select options become settings, flattening groups and leaving booleans" {
  assert_eq(
    settings([
      {
        "id": "model",
        "name": "Model",
        "type": "select",
        "currentValue": "a/x",
        "options": [
          { "value": "a/x", "name": "X" },
          {
            "group": "b",
            "name": "B",
            "options": [{ "value": "b/y", "name": "Y" }],
          },
        ],
      },
      { "id": "fast", "name": "Fast", "type": "boolean", "currentValue": true },
    ]),
    [
      {
        id: "model",
        name: "Model",
        value: "a/x",
        choices: [{ value: "a/x", name: "X", }, { value: "b/y", name: "Y", }],
      },
    ],
  )
}
