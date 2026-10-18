///|
fn new_app() -> App {
  let reply = (part : @program.Part) => @program.Reply::{
    parts: [part],
    error: None,
  }
  let fixture : @program.Program = {
    name: "fixture",
    kind: Interpreter(language="nu"),
    send: (input, _) => {
      match input.text {
        "users" => reply(Data(@fixture.users))
        "config" => reply(Data(@fixture.config))
        "orders" => reply(Text(@fixture.orders_csv))
        "escape" => reply(Data([{ "a": "<x>" }]))
        text => { parts: [], error: Some("unknown: \{text}"), }
      }
    },
  }
  App::new([fixture, @mock.agent()])
}

///|
fn html(app : App) -> String {
  app.render().0
}

///|
fn click(app : App, action : UiAction, shift? : Bool = false) -> Unit {
  app.render() |> ignore
  match app.actions.iter().find_first(kv => kv.1 == action) {
    Some((id, _)) => app.dispatch(id, shift~)
    None => abort("no element for \{@debug.to_string(action)}")
  }
}

///|
fn view_of(app : App, b : Int) -> String {
  app.blocks[b].view_text
}

///|
test "gui actions write the view transform, not the output" {
  let app = new_app()
  app.send("users")
  click(app, Gui(0, SortColumn("age")))
  inspect(view_of(app, 0), content="sort-by age")
  click(app, OpenMenu(0, 4, 2))
  assert_true(html(app).contains("<code>where age &gt;= 34</code>"))
  click(app, Gui(0, Filter([Key("age")], Ge, 34)))
  inspect(view_of(app, 0), content="sort-by age | where age >= 34")
  app.set_view(0, view_of(app, 0) + " | length")
  assert_eq(app.blocks[0].shown, 4)
  assert_true(app.blocks[0].output is Array(rows) && rows.length() == 8)
}

///|
test "a nu view can be taken into the input" {
  let app = new_app()
  app.send("users")
  click(app, Gui(0, SortColumn("age")))
  click(app, UseInput("users | sort-by age"))
  assert_eq(app.next_input, Some("users | sort-by age"))
}

///|
test "a failing view keeps the last value and its stage can be removed" {
  let app = new_app()
  app.send("users")
  app.set_view(0, "length")
  app.set_view(0, "lenght")
  assert_eq(app.blocks[0].shown, 8)
  assert_eq(app.blocks[0].view_error, Some("unknown command: lenght (at 0)"))
  app.set_view(0, "lines")
  assert_eq(
    app.blocks[0].view_error,
    Some("stage 1: lines expects text, got list"),
  )
  assert_true(html(app).contains("stage failed"))
  click(app, Gui(0, RemoveStage(0)))
  assert_eq(app.blocks[0].view_error, None)
}

///|
test "gui actions wait until the view is fixed" {
  let app = new_app()
  app.send("users")
  app.set_view(0, "where age > 30 | sel")
  app.apply(0, SortColumn("age"))
  inspect(view_of(app, 0), content="where age > 30 | sel")
  assert_true(app.notice != "")
}

///|
test "selected rows copy as markdown and can be kept" {
  let app = new_app()
  app.send("users")
  app.set_view(0, "select name age")
  click(app, ToggleRow(0, 1))
  click(app, ToggleRow(0, 3), shift=true)
  click(app, CopySelection(0))
  inspect(
    app.clipboard,
    content=(
      #|| name | age |
      #|| --- | --- |
      #|| Bob | 27 |
      #|| 佐藤 花子 | 41 |
      #|| Carol | 30 |
      #|
    ),
  )
  click(app, Gui(0, KeepRows([1, 2, 3])))
  inspect(view_of(app, 0), content="select name age | select 1 2 3")
}

///|
test "copied cells are the data behind them" {
  let app = new_app()
  app.send("users")
  let copy = (rows, cols) => {
    app.blocks[0].copy_cells(rows, cols, app.copy_format)
  }
  inspect(copy([0], [1]), content="Alice")
  inspect(
    copy([0], [6]),
    content=(
      #|{
      #|  "city": "Tokyo",
      #|  "zip": "100-0001"
      #|}
    ),
  )
  click(app, SetCopyFormat(Tsv))
  inspect(
    copy([1, 2], [1, 2]),
    content=(
      #|name	age
      #|Bob	27
      #|佐藤 花子	41
      #|
    ),
  )
}

///|
test "drilling from a cell and from the tree adds get stages" {
  let app = new_app()
  app.send("config")
  click(app, OpenMenu(0, 4, 1))
  click(app, Gui(0, Drill([Key("owners")])))
  click(app, SetLayout(0, Tree))
  click(app, Gui(0, Drill([Idx(0), Key("email")])))
  inspect(view_of(app, 0), content="get owners | get 0.email")
}

///|
test "text output can be read as structured data" {
  let app = new_app()
  app.send("orders")
  click(app, Gui(0, Append(From(Csv))))
  assert_true(html(app).contains("表 · 10 行 × 6 列"))
}

///|
test "keeping rows of a record selects its fields" {
  let app = new_app()
  app.send("config")
  click(app, ToggleRow(0, 0))
  click(app, ToggleRow(0, 2))
  click(app, Gui(0, KeepColumns(["name", "server"])))
  inspect(view_of(app, 0), content="select name server")
}

///|
test "history walks the inputs of the current program" {
  let app = new_app()
  app.send("ls")
  app.send("users")
  click(app, SelectProgram(1))
  app.send("表")
  click(app, SelectProgram(0))
  let steps = [-1, -1, -1, 1, 1].map(delta => {
    app.next_input = None
    app.history_step(delta, "open u")
    app.next_input.unwrap_or("-")
  })
  assert_eq(steps, ["users", "ls", "-", "users", "open u"])
}

///|
test "values are escaped in html" {
  let app = new_app()
  app.send("escape")
  assert_true(html(app).contains("&lt;x&gt;"))
  assert_false(html(app).contains("<x>"))
}

///|
test "the sort arrow follows the view transform" {
  let app = new_app()
  app.send("users")
  app.set_view(0, "sort-by age --reverse")
  assert_true(html(app).contains("age<span class=\"arrow\"> ▼</span>"))
}

///|
test "a markdown table from the agent is data, and the markdown stays copyable" {
  let app = new_app()
  click(app, SelectProgram(1))
  app.send("表を見せて")
  assert_true(
    app.entries[0].blocks.map(b => app.blocks[b].content)
    is [Fragment(_), Data, Fragment(_)],
  )
  click(app, Gui(1, SortColumn("estimate")))
  click(app, OpenMenu(1, 1, 2))
  click(app, Gui(1, Filter([Key("priority")], Eq, "high")))
  click(app, SetCopyFormat(Csv))
  click(app, SelectAllRows(1))
  click(app, CopySelection(1))
  inspect(
    app.clipboard,
    content=(
      #|task,owner,priority,estimate
      #|ログイン画面,Alice,high,3
      #|検索,佐藤,high,8
      #|
    ),
  )
  html(app) |> ignore
  assert_true(
    app.actions.values().any(a => a is CopyText(md) && md.contains("| --- |")),
  )
}

///|
test "every kind of part is drawn" {
  let app = new_app()
  click(app, SelectProgram(1))
  app.send("図と html と画像と音とファイル")
  let page = html(app)
  for
    marker in [
      "<svg", "<iframe sandbox=\"allow-scripts\"", "<img src=\"data:image/svg+xml",
      "<audio controls", "tasks.csv",
    ] {
    assert_true(page.contains(marker), msg=marker)
  }
}

///|
test "attachments go with the next input" {
  let app = new_app()
  app.handle(Attach(name="a.txt", media_type="text/plain", data="x")) |> ignore
  app.handle(Attach(name="b.txt", media_type="text/plain", data="y")) |> ignore
  click(app, RemoveAttachment(0))
  assert_true(app.render().1.contains("b.txt"))
  click(app, SelectProgram(1))
  app.send("")
  assert_eq(app.entries[0].input.attachments.map(a => a.name), ["b.txt"])
  assert_false(app.render().1.contains("b.txt"))
}

///|
test "errors from the program are shown with the entry" {
  let app = new_app()
  app.send("nope")
  assert_true(html(app).contains("unknown: nope"))
}

///|
test "requests decode from json and frames carry the result" {
  let app = new_app()
  let request : Request = @json.from_json(
    @json.parse("[\"Send\", {\"text\": \"users\"}]"),
  )
  let frame = app.handle(request)
  assert_eq(frame.input, Some(""))
  assert_true(frame.scroll && frame.html.contains("Alice"))
  let frame = app.handle(Copy(block=0, rows=[0], cols=[1, 2]))
  assert_eq(frame.clipboard, "| name | age |\n| --- | --- |\n| Alice | 34 |\n")
  assert_eq(frame.notice, "2 セルをデータとしてコピーしました")
}

///|
test "an entry renders the same until it changes" {
  let app = new_app()
  app.send("users")
  app.send("users")
  let before = html(app)
  click(app, Gui(1, SortColumn("name")))
  let after = html(app)
  let first = (page : String) => {
    page[:page.find("data-key=\"e1\"").unwrap()].to_owned()
  }
  assert_eq(first(after), first(before))
}

///|
test "a list has a value header and a record field and value headers" {
  let app = new_app()
  app.send("users")
  app.set_view(0, "get name")
  assert_true(html(app).contains("<th>value</th>"))
  app.send("config")
  assert_true(html(app).contains("<th>field</th><th>value</th>"))
}

///|
test "an agent receives the exchanges it has not seen" {
  let app = new_app()
  app.send("users")
  click(app, SelectProgram(1))
  app.send("どう？")
  assert_true(
    app.entries[1].reply.parts is [Markdown(md), ..] &&
    md.contains("| fixture | `users` | 8 行 |"),
  )
  app.send("こんにちは")
  assert_true(
    app.entries[2].reply.parts is [Markdown(md)] &&
    !md.contains("受け取りました"),
  )
}

///|
test "programs an agent runs are drawn as steps of its entry" {
  let app = new_app()
  click(app, SelectProgram(1))
  app.send("`users` を見て")
  assert_true(app.entries[0].steps is [{ program: 0, .. }])
  let page = html(app)
  assert_true(page.contains("AI → fixture") && page.contains("Alice"))
}
