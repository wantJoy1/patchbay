///|
async fn with_app(
  f : async (App) -> Unit,
  changed~ : (Frame) -> Unit = _ => (),
) -> Unit {
  let fixture : @program.Program = {
    name: "fixture",
    kind: Interpreter(language="nu"),
    settings: None,
    send: (input, session) => {
      match input.text {
        "users" => (session.emit)(Data(@fixture.users))
        "config" => (session.emit)(Data(@fixture.config))
        "orders" => (session.emit)(Text(@fixture.orders_csv))
        "escape" => (session.emit)(Data([{ "a": "<x>" }]))
        "times" =>
          (session.emit)(Data([{ "t": "2026-10-18T15:07:24.4+09:00" }]))
        "fraction" => (session.emit)(Data([{ "cpu": 3.106144393241167 }]))
        "slow" => @async.sleep(60_000)
        "brief" => {
          @async.sleep(20)
          (session.emit)(Text("done"))
        }
        "many" => (session.emit)(Data(Json::Json(Array::makei(201, i => i))))
        text => raise @program.Failure("unknown: \{text}")
      }
    },
  }
  @async.with_task_group(group => {
    let app = App::new([fixture, @mock.agent()], group, changed~)
    f(app)
  })
}

///|
async fn settle(app : App) -> Unit {
  while app.entries.iter().any(e => e.running) {
    @async.pause()
  }
}

///|
async fn send(app : App, text : String) -> Unit {
  app.send(text)
  settle(app)
}

///|
fn html(app : App) -> String {
  app.render().0
}

///|
async fn click(app : App, action : UiAction, shift~ : Bool = false) -> Unit {
  app.render() |> ignore
  match app.actions.iter().find_first(kv => kv.1 == action) {
    Some((id, _)) => app.dispatch(id, shift~)
    None => abort("no element for \{@debug.to_string(action)}")
  }
  settle(app)
}

///|
fn view_of(app : App, b : Int32) -> String {
  app.blocks[b].view_text
}

///|
async test "gui actions write the view transform, not the output" {
  with_app(app => {
    send(app, "users")
    click(app, Gui(0, SortColumn("age")))
    inspect(view_of(app, 0), content="sort-by age")
    click(app, OpenMenu(0, 4, 2))
    assert_true(html(app).contains("<code>where age &gt;= 34</code>"))
    click(app, Gui(0, Filter([Key("age")], Ge, 34)))
    inspect(view_of(app, 0), content="sort-by age | where age >= 34")
    app.set_view(0, view_of(app, 0) + " | length")
    assert_eq(app.blocks[0].shown, 4)
    assert_true(app.blocks[0].output is Array(rows) && rows.length() == 8)
  })
}

///|
async test "a nu view can be taken into the input" {
  with_app(app => {
    send(app, "users")
    click(app, Gui(0, SortColumn("age")))
    click(app, UseInput("users | sort-by age"))
    assert_eq(app.next_input, Some("users | sort-by age"))
  })
}

///|
async test "a failing view keeps the last value and its stage can be removed" {
  with_app(app => {
    send(app, "users")
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
  })
}

///|
async test "gui actions wait until the view is fixed" {
  with_app(app => {
    send(app, "users")
    app.set_view(0, "where age > 30 | sel")
    app.apply(0, SortColumn("age"))
    inspect(view_of(app, 0), content="where age > 30 | sel")
    assert_true(app.notice != "")
  })
}

///|
async test "selected rows copy as markdown and can be kept" {
  with_app(app => {
    send(app, "users")
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
  })
}

///|
async test "copied cells are the data behind them" {
  with_app(app => {
    send(app, "users")
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
    click(app, OpenCopy(0))
    click(app, CopyAs(0, Tsv))
    inspect(
      copy([1, 2], [1, 2]),
      content=(
        #|name	age
        #|Bob	27
        #|佐藤 花子	41
        #|
      ),
    )
  })
}

///|
async test "drilling from a cell and from the tree adds get stages" {
  with_app(app => {
    send(app, "config")
    click(app, OpenMenu(0, 4, 1))
    click(app, Gui(0, Drill([Key("owners")])))
    click(app, SetLayout(0, Tree))
    click(app, Gui(0, Drill([Idx(0), Key("email")])))
    inspect(view_of(app, 0), content="get owners | get 0.email")
  })
}

///|
async test "text output can be read as structured data" {
  with_app(app => {
    send(app, "orders")
    click(app, Gui(0, Append(From(Csv))))
    assert_true(html(app).contains("10 行 · 6 列"))
  })
}

///|
async test "keeping rows of a record selects its fields" {
  with_app(app => {
    send(app, "config")
    click(app, ToggleRow(0, 0))
    click(app, ToggleRow(0, 2))
    click(app, Gui(0, KeepColumns(["name", "server"])))
    inspect(view_of(app, 0), content="select name server")
  })
}

///|
async test "history walks the inputs of the current program" {
  with_app(app => {
    send(app, "ls")
    send(app, "users")
    click(app, SelectProgram(1))
    send(app, "表")
    click(app, SelectProgram(0))
    let steps = [-1, -1, -1, 1, 1].map(delta => {
      app.next_input = None
      app.history_step(delta, "open u")
      app.next_input.unwrap_or("-")
    })
    assert_eq(steps, ["users", "ls", "-", "users", "open u"])
  })
}

///|
async test "values are escaped in html" {
  with_app(app => {
    send(app, "escape")
    assert_true(html(app).contains("&lt;x&gt;"))
    assert_false(html(app).contains("<x>"))
  })
}

///|
async test "the sort arrow follows the view transform" {
  with_app(app => {
    send(app, "users")
    app.set_view(0, "sort-by age --reverse")
    assert_true(html(app).contains("age<span class=\"arrow\"> ↓</span>"))
  })
}

///|
async test "a markdown table from the agent is data, and the markdown stays copyable" {
  with_app(app => {
    click(app, SelectProgram(1))
    send(app, "表を見せて")
    assert_true(
      app.entries[0].output.blocks.map(b => app.blocks[b].content)
      is [Fragment(_), Data, Fragment(_)],
    )
    html(app) |> ignore
    assert_true(
      app.actions.values().any(a => a is CopyText(md) && md.contains("| --- |")),
    )
  })
}

///|
async test "diagrams, pages, images, sounds and files are drawn" {
  with_app(app => {
    click(app, SelectProgram(1))
    send(app, "図と html と画像と音とファイル")
    let page = html(app)
    for
      marker in [
        "<svg", "<iframe sandbox=\"allow-scripts\"", "<img src=\"data:image/svg+xml",
        "<audio controls", "tasks.csv",
      ] {
      assert_true(page.contains(marker), msg=marker)
    }
  })
}

///|
async test "attachments go with the next input" {
  with_app(app => {
    app.handle(Attach(name="a.txt", media_type="text/plain", data="x"))
    |> ignore
    app.handle(Attach(name="b.txt", media_type="text/plain", data="y"))
    |> ignore
    click(app, RemoveAttachment(0))
    assert_true(app.render().1.contains("b.txt"))
    click(app, SelectProgram(1))
    send(app, "")
    assert_eq(app.entries[0].output.input.attachments.map(a => a.name), [
      "b.txt",
    ])
    assert_false(app.render().1.contains("b.txt"))
  })
}

///|
async test "errors from the program are shown with the entry and copy as text" {
  with_app(app => {
    send(app, "nope")
    assert_true(html(app).contains("unknown: nope"))
    click(app, CopyText("unknown: nope"))
    assert_eq(app.clipboard, "unknown: nope")
  })
}

///|
async test "a decoded request yields a frame whose one-shot fields are not repeated" {
  let frames = []
  with_app(changed=frame => frames.push(frame), app => {
    app.handle(
      @json.from_json(@json.parse("[\"Send\", {\"text\": \"users\"}]")),
    )
    assert_true(frames[0].input == Some("") && frames[0].scroll)
    settle(app)
    assert_true(frames.last().unwrap() is { input: None, scroll: false, .. })
  })
}

///|
async test "an entry renders the same until it changes" {
  with_app(app => {
    send(app, "users")
    send(app, "users")
    let before = html(app)
    click(app, Gui(1, SortColumn("name")))
    let after = html(app)
    let first = (page : String) => {
      page[:page.find("data-key=\"e1\"").unwrap()].to_owned()
    }
    assert_eq(first(after), first(before))
  })
}

///|
async test "a list has a value column and a record field and value columns" {
  with_app(app => {
    send(app, "users")
    app.set_view(0, "get name")
    assert_true(html(app).contains("<th>value</th>"))
    send(app, "config")
    assert_true(html(app).contains("<th>field</th><th>value</th>"))
  })
}

///|
async test "an agent receives only the exchanges it has not seen yet" {
  with_app(app => {
    send(app, "users")
    click(app, SelectProgram(1))
    send(app, "どう？")
    assert_true(
      app.entries[1].output.parts is [Markdown(md), ..] &&
      md.contains("| fixture | `users` | 8 行 |"),
    )
    send(app, "こんにちは")
    assert_true(
      app.entries[2].output.parts is [Markdown(md)] &&
      !md.contains("受け取りました"),
    )
  })
}

///|
async test "programs an agent runs are steps of its entry, drawn when opened" {
  with_app(app => {
    click(app, SelectProgram(1))
    send(app, "`users` を見て")
    assert_true(app.entries[0].steps is [{ program: 0, .. }])
    let page = html(app)
    assert_true(page.contains("AI → fixture") && !page.contains("Alice"))
    click(app, ToggleStep(0, 0))
    assert_true(html(app).contains("Alice"))
  })
}

///|
async test "a running input shows as running and can be cancelled" {
  with_app(app => {
    app.send("slow")
    @async.pause()
    assert_true(html(app).contains("中断"))
    click(app, Cancel(0))
    assert_true(
      !app.entries[0].running &&
      app.entries[0].output.error == Some("中断しました"),
    )
    assert_false(html(app).contains("中断</button>"))
  })
}

///|
async test "frames follow the output as it arrives" {
  let frames = []
  with_app(changed=frame => frames.push(frame.html), app => {
    click(app, SelectProgram(1))
    send(app, "表と図")
  })
  assert_true(frames.any(f => f.contains("estimate") && !f.contains("<svg")))
  assert_true(frames.last().unwrap().contains("<svg"))
}

///|
async test "a long output shows its first rows until all are asked for" {
  with_app(app => {
    send(app, "many")
    assert_true(html(app).contains("残り 1 行を表示"))
    click(app, ShowAllRows(0))
    assert_false(html(app).contains("残り"))
  })
}

///|
async test "the same value can be drawn as a table, a tree or JSON" {
  with_app(app => {
    send(app, "config")
    click(app, SetLayout(0, Tree))
    assert_true(html(app).contains("<div class=\"tree\">"))
    click(app, SetLayout(0, Json))
    assert_true(html(app).contains("&quot;name&quot;: &quot;patchbay&quot;"))
  })
}

///|
async test "an exchange still running when an agent is asked reaches it on a later turn" {
  with_app(app => {
    app.send("brief")
    app.current = 1
    send(app, "hi")
    assert_true(
      app.entries[1].output.parts is [Markdown(md)] && !md.contains("brief"),
    )
    send(app, "again")
    assert_true(
      app.entries[2].output.parts is [Markdown(md), ..] &&
      md.contains("| fixture | `brief` |"),
    )
  })
}

///|
async test "a block copies in the format last chosen" {
  with_app(app => {
    send(app, "users")
    click(app, OpenCopy(0))
    click(app, CopyAs(0, Csv))
    assert_true(app.clipboard.has_prefix("id,name,age"))
    click(app, CopyAll(0))
    assert_true(
      app.copy_format == Csv && app.clipboard.has_prefix("id,name,age"),
    )
  })
}

///|
async test "the transform editor shows only when asked for or in use" {
  with_app(app => {
    send(app, "users")
    assert_false(html(app).contains("data-view"))
    click(app, EditView(0))
    assert_true(html(app).contains("data-view=\"0\""))
    click(app, EditView(0))
    assert_false(html(app).contains("data-view"))
  })
}

///|
async test "a timestamp shows its date and minute and keeps the full value" {
  with_app(app => {
    send(app, "times")
    assert_true(
      html(app).contains(
        "title=\"2026-10-18T15:07:24.4+09:00\" data-r=\"0\" data-c=\"0\" data-act=\"b0.",
      ) &&
      html(app).contains(">2026-10-18 15:07<"),
    )
  })
}

///|
async test "a long fraction shows two decimals and keeps the full value" {
  with_app(app => {
    send(app, "fraction")
    assert_true(
      html(app).contains("title=\"3.106144393241167\"") &&
      html(app).contains(">3.11<"),
    )
  })
}

///|
fn configurable(
  model : Ref[String],
  changes : Array[String],
) -> @program.Program {
  {
    name: "agent",
    kind: Agent,
    send: (_, _) => (),
    settings: Some({
      current: () => {
        [
          {
            id: "model",
            name: "Model",
            value: model.val,
            choices: [
              { value: "free", name: "Free", },
              { value: "paid", name: "Paid", },
            ],
          },
        ]
      },
      change: (_, value) => {
        changes.push(value)
        model.val = value
      },
    }),
  }
}

///|
async test "a setting is chosen from the controls and remembered" {
  let model : Ref[String] = { val: "free", }
  let changes = []
  let saved = []
  @async.with_task_group(group => {
    let app = App::new([configurable(model, changes)], group, changed=_ => (), remember=c => {
      saved.push(c.to_array())
    })
    assert_true(app.render().1.contains("Free ▾"))
    click(app, OpenSetting(0, "model"))
    assert_true(app.render().1.contains("✓ Free"))
    click(app, ChangeSetting(0, "model", "paid"))
    while changes.is_empty() {
      @async.pause()
    }
    assert_eq(changes, ["paid"])
    assert_eq(saved.length(), 1)
    assert_true(
      saved[0] is [("agent", values)] && values.get("model") == Some("paid"),
    )
    assert_true(
      app.render().1.contains("Paid ▾") && !app.render().1.contains("menu"),
    )
  })
}

///|
async test "a remembered setting is restored unless the program no longer offers it" {
  let model : Ref[String] = { val: "free", }
  let changes = []
  @async.with_task_group(group => {
    App::new([configurable(model, changes)], group, changed=_ => (), chosen={
      "agent": { "model": "gone" },
    })
    |> ignore
    App::new([configurable(model, changes)], group, changed=_ => (), chosen={
      "agent": { "model": "paid" },
    })
    |> ignore
  })
  assert_eq(changes, ["paid"])
}
