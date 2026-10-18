///|
async fn send(nu : @program.Program, text : String) -> @program.Reply {
  let parts = []
  let session : @program.Session = {
    unseen: [],
    programs: [],
    emit: p => parts.push(p),
    run: (_, _) => abort("nu runs nothing"),
  }
  let error = try (nu.send)({ text, attachments: [], }, session) catch {
    @program.Failure(msg) => Some(msg)
    e => Some(e.to_string())
  } noraise {
    _ => None
  }
  { parts, error, }
}

///|
async fn with_nu(f : async (@program.Program) -> Unit) -> Unit {
  @async.with_task_group(group => f(@nushell.nushell(group)))
}

///|
async test "a session keeps variables and the working directory" {
  with_nu(nu => {
    send(nu, "let x = 2; cd /tmp") |> ignore
    assert_eq(send(nu, "$x + 1"), { parts: [Data(3)], error: None, })
    assert_eq(send(nu, "pwd"), { parts: [Text("/tmp")], error: None, })
  })
}

///|
async test "structured output is data and failures are errors" {
  with_nu(nu => {
    assert_eq(send(nu, "[[a]; [1] [2]]"), {
      parts: [Data([{ "a": 1 }, { "a": 2 }])],
      error: None,
    })
    assert_eq(send(nu, "error make {msg: boom}"), {
      parts: [],
      error: Some("boom"),
    })
  })
}

///|
async test "what external commands print before the result is text" {
  with_nu(nu => {
    assert_eq(send(nu, "^echo hi; 1"), {
      parts: [Text("hi"), Data(1)],
      error: None,
    })
  })
}

///|
async test "a one-row table arrives as its row, as nu's MCP server unwraps it" {
  with_nu(nu => {
    assert_eq(send(nu, "[[a]; [1]]"), {
      parts: [Data({ "a": 1 })],
      error: None,
    })
  })
}

///|
async test "a cancelled input does not disturb the next one" {
  with_nu(nu => {
    @async.with_timeout_opt(200, () => send(nu, "sleep 2sec; 1")) |> ignore
    assert_eq(send(nu, "2"), { parts: [Data(2)], error: None, })
  })
}
