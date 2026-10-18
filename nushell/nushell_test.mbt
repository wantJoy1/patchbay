///|
fn send(nu : @program.Program, text : String) -> @program.Reply {
  (nu.send)({ text, attachments: [], }, {
    unseen: [],
    programs: [],
    run: (_, _) => abort("nu runs nothing"),
  })
}

///|
test "a session keeps variables and the working directory" {
  let nu = @nushell.nushell()
  send(nu, "let x = 2; cd /tmp") |> ignore
  assert_eq(send(nu, "$x + 1"), { parts: [Data(3)], error: None, })
  assert_eq(send(nu, "pwd"), { parts: [Text("/tmp")], error: None, })
}

///|
test "structured output is data and failures are errors" {
  let nu = @nushell.nushell()
  assert_eq(send(nu, "[[a]; [1] [2]]"), {
    parts: [Data([{ "a": 1 }, { "a": 2 }])],
    error: None,
  })
  assert_eq(send(nu, "error make {msg: boom}"), {
    parts: [],
    error: Some("boom"),
  })
}

///|
test "what external commands print before the result is text" {
  let nu = @nushell.nushell()
  assert_eq(send(nu, "^echo hi; 1"), {
    parts: [Text("hi"), Data(1)],
    error: None,
  })
}

///|
test "a one-row table arrives as its row, as nu's MCP server unwraps it" {
  let nu = @nushell.nushell()
  assert_eq(send(nu, "[[a]; [1]]"), { parts: [Data({ "a": 1 })], error: None, })
}
