///|
async fn ask(
  agent : @program.Program,
  text : String,
  unseen~ : Array[@program.Exchange] = [],
  programs~ : Array[(String, @program.Kind)] = [],
  run~ : async (String, @program.Input) -> @program.Reply = (_, _) => {
    abort("no programs")
  },
) -> Array[@program.Part] {
  let parts = []
  (agent.send)({ text, attachments: [], }, {
    unseen,
    programs,
    emit: p => parts.push(p),
    run,
  })
  parts
}

///|
async test "the agent mock answers in the kinds asked for and counts turns" {
  let agent = @mock.agent()
  assert_true(
    ask(agent, "表と図と画像") is [Markdown(_), Markdown(_), Image(_)],
  )
  assert_true(
    ask(agent, "こんにちは") is [Markdown(help)] &&
    help.contains("2 回目"),
  )
  assert_true(
    ask(agent, "html 音 ファイル") is [Html(_), Audio(_), File(_, ..)],
  )
}

///|
async test "the agent mock reports what it has not seen" {
  let unseen : Array[@program.Exchange] = [
    {
      program: "nu",
      input: { text: "ls", attachments: [], },
      reply: { parts: [Data([1, 2])], error: None, },
    },
  ]
  let parts = ask(@mock.agent(), "", unseen~)
  assert_true(parts is [Markdown(md)] && md.contains("| nu | `ls` | 2 行 |"))
}

///|
async test "the agent mock runs code spans on an interpreter" {
  let ran = []
  let parts = ask(
    @mock.agent(),
    "`ls` と `pwd` を見て",
    programs=[("nu", Interpreter(language="nu"))],
    run=(name, input) => {
      ran.push((name, input.text))
      { parts: [Text("ok")], error: None, }
    },
  )
  assert_eq(ran, [("nu", "ls"), ("nu", "pwd")])
  assert_eq(parts.length(), 2)
}
