///|
async fn with_app(
  f : async (App) -> Unit,
  changed~ : (Frame) -> Unit = _ => (),
) -> Unit {
  let fixture : @program.Program = {
    name: "fixture",
    kind: Interpreter(language="nu"),
    send: (input, session) => {
      match input.text {
        "users" => (session.emit)(Data(@fixture.users))
        "config" => (session.emit)(Data(@fixture.config))
        "orders" => (session.emit)(Text(@fixture.orders_csv))
        "escape" => (session.emit)(Data([{ "a": "<x>" }]))
        "slow" => @async.sleep(60_000)
        "many" => (session.emit)(Data(Json::Json(Array::makei(201, i => i))))
        text => raise @program.Failure("unknown: \{text}")
      }
    },
  }
  @async.with_task_group(group => {
    let app = App::new(
      [fixture, @mock.agent()],
      spawn=job => {
        let task = group.spawn(job, allow_failure=true)
        () => task.cancel()
      },
      changed~,
    )
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
    assert_true(html(app).contains("表 · 10 行 × 6 列"))
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
    assert_true(html(app).contains("age<span class=\"arrow\"> ▼</span>"))
  })
}

///|
async test "a markdown table from the agent is data, and the markdown stays copyable" {
  with_app(app => {
    click(app, SelectProgram(1))
    send(app, "表を見せて")
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
  })
}

///|
async test "every kind of part is drawn" {
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
    assert_eq(app.entries[0].input.attachments.map(a => a.name), ["b.txt"])
    assert_false(app.render().1.contains("b.txt"))
  })
}

///|
async test "errors from the program are shown with the entry" {
  with_app(app => {
    send(app, "nope")
    assert_true(html(app).contains("unknown: nope"))
  })
}

///|
async test "requests decode from json and frames carry the result" {
  with_app(app => {
    let request : Request = @json.from_json(
      @json.parse("[\"Send\", {\"text\": \"users\"}]"),
    )
    let frame = app.handle(request)
    assert_true(
      frame.input == Some("") &&
      frame.scroll &&
      frame.html.contains("実行中"),
    )
    settle(app)
    assert_true(app.frame().html.contains("Alice"))
    let frame = app.handle(Copy(block=0, rows=[0], cols=[1, 2]))
    assert_eq(
      frame.clipboard,
      "| name | age |\n| --- | --- |\n| Alice | 34 |\n",
    )
    assert_eq(
      frame.notice,
      "2 セルをデータとしてコピーしました",
    )
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
      app.entries[1].parts is [Markdown(md), ..] &&
      md.contains("| fixture | `users` | 8 行 |"),
    )
    send(app, "こんにちは")
    assert_true(
      app.entries[2].parts is [Markdown(md)] &&
      !md.contains("受け取りました"),
    )
  })
}

///|
async test "programs an agent runs are drawn as steps of its entry" {
  with_app(app => {
    click(app, SelectProgram(1))
    send(app, "`users` を見て")
    assert_true(app.entries[0].steps is [{ program: 0, .. }])
    let page = html(app)
    assert_true(page.contains("AI → fixture") && page.contains("Alice"))
  })
}

///|
async test "a running input shows as running and can be cancelled" {
  with_app(app => {
    app.send("slow")
    @async.pause()
    assert_true(html(app).contains("実行中"))
    click(app, Cancel(0))
    assert_true(
      !app.entries[0].running &&
      app.entries[0].error == Some("中断しました"),
    )
    assert_false(html(app).contains("実行中"))
  })
}

///|
async test "frames follow the output as it arrives" {
  let frames = []
  with_app(changed=frame => frames.push(frame.html), app => {
    click(app, SelectProgram(1))
    send(app, "表と図")
  })
  assert_true(frames.length() >= 2 && frames.last().unwrap().contains("<svg"))
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
