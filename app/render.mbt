///|
let row_limit = 200

///|
/// Why not number every action of an entry in order: a streaming entry adds
/// blocks, which would shift the keys a click from an older frame still
/// names. Blocks get their own scopes and entry buttons their own names.
fn App::act(self : App, action : UiAction, name? : String) -> String {
  let name = match name {
    Some(name) => name
    None => {
      self.next_act += 1
      (self.next_act - 1).to_string()
    }
  }
  let key = "\{self.scope}.\{name}"
  self.actions[key] = action
  " data-act=\"\{key}\""
}

///|
fn App::button(
  self : App,
  label : String,
  action : UiAction,
  class~ : String = "",
  title~ : String = "",
  name? : String,
) -> String {
  "<button class=\"\{class}\" title=\"\{@html.escape(title)}\"\{self.act(action, name?)}>\{label}</button>"
}

///|
fn code(text : String) -> String {
  "<code>\{@html.escape(text)}</code>"
}

///|
fn App::enter(self : App, scope : String) -> Unit {
  self.scope = scope
  self.next_act = 0
}

///|
fn App::render(self : App) -> (String, String) {
  self.actions.clear()
  self.enter("w")
  let turns = if self.entries.is_empty() {
    [self.render_welcome()]
  } else {
    self.entries.mapi((i, e) => {
      self.enter("e\{i}")
      self.render_entry(i, e)
    })
  }
  self.enter("c")
  let programs = self.programs.mapi((i, p) => {
    let class = if i == self.current { "active" } else { "" }
    self.button(@html.escape(p.name), SelectProgram(i), class~)
  })
  let settings = match self.programs[self.current].settings {
    Some(settings) =>
      (settings.current)().map(s => self.render_setting(self.current, s))
    None => []
  }
  let pending = self.pending.mapi((i, a) => {
    "<span class=\"chip\">\{@html.escape(a.name)}\{self.button("×", RemoveAttachment(i), title="添付を外す")}</span>"
  })
  (
    "<div>\{turns.join("")}</div>",
    "<nav class=\"segmented\">\{programs.join("")}</nav>\{settings.join("")}\{pending.join("")}",
  )
}

///|
fn App::render_setting(
  self : App,
  p : Int32,
  setting : @program.Setting,
) -> String {
  let label = match setting.choices.search_by(c => c.value == setting.value) {
    Some(i) => setting.choices[i].name
    None => setting.value
  }
  let menu = if self.menu == Some(Setting(p, setting.id)) {
    let items = setting.choices.map(c => {
      let mark = if c.value == setting.value { "✓ " } else { "" }
      self.button(
        "\{mark}\{@html.escape(c.name)}",
        ChangeSetting(p, setting.id, c.value),
        class="item",
      )
    })
    "<div class=\"menu\">\{items.join("")}</div>"
  } else {
    ""
  }
  let open = self.button(
    "\{@html.escape(label)} ▾",
    OpenSetting(p, setting.id),
    title=setting.name,
  )
  "<span class=\"split\">\{open}\{menu}</span>"
}

///|
fn App::placeholder(self : App) -> String {
  match self.programs[self.current].kind {
    Interpreter(language~) => "\{language} のコード"
    Agent => "メッセージ"
  }
}

///|
fn App::render_welcome(self : App) -> String {
  let examples = match self.programs[self.current].kind {
    Interpreter(_) => ["ls", "ps | first 10", "sys host"]
    Agent =>
      [
        "表を見せて", "図で説明して", "HTML のページを作って",
        "画像と音を出して",
      ]
  }
  let chips = examples.map(e => {
    self.button(@html.escape(e), Send(e), class="chip")
  })
  (
    $|<div class="welcome" data-key="w\{self.current}">\{chips.join("")}</div>
  )
}

///|
fn App::render_entry(self : App, i : Int32, entry : Entry) -> String {
  let output = entry.output
  let program = self.programs[output.program]
  let text = output.input.text
  let said = match program.kind {
    Interpreter(_) => code(text)
    Agent => @html.escape(text)
  }
  let attachments = output.input.attachments.map(a => {
    "<span class=\"chip\">\{@html.escape(a.name)}</span>"
  })
  let markdown = output.parts.filter_map(p => {
    if p is Markdown(md) {
      Some(md)
    } else {
      None
    }
  })
  let copy = if markdown.is_empty() {
    ""
  } else {
    self.button(
      "コピー",
      CopyText(markdown.join("\n\n")),
      title="Markdown をコピー",
      name="markdown",
    )
  }
  let status = if entry.running {
    "<span class=\"spinner\"></span>\{self.button("中断", Cancel(i), name="cancel")}"
  } else if text != "" {
    copy +
    self.button("↺", UseInput(text), title="入力欄に戻す", name="input")
  } else {
    copy
  }
  let steps = entry.steps.mapi((s, step) => self.render_step(i, s, step))
  (
    $|<section class="turn" data-key="e\{i}"><header><span class="badge">\{@html.escape(program.name)}</span>
    $|<span class="said">\{said}</span>\{attachments.join("")}<span class="status">\{status}</span></header>
    $|\{steps.join("")}\{self.render_output(output)}</section>
  )
}

///|
fn App::render_step(self : App, i : Int32, s : Int32, step : Output) -> String {
  let result = match (step.error, step.parts) {
    (Some(_), _) => "エラー"
    (_, [Data(v), ..]) => describe(v)
    (_, [Text(t), ..]) => describe(Json(t))
    _ => ""
  }
  let summary = "<summary\{self.act(ToggleStep(i, s), name="step\{s}")}><span class=\"badge\">AI → \{@html.escape(self.programs[step.program].name)}</span>\{code(step.input.text)}<span class=\"muted\">\{result}</span></summary>"
  let body = if step.open { self.render_output(step) } else { "" }
  let open = if step.open { " open" } else { "" }
  "<details class=\"step\"\{open}>\{summary}\{body}</details>"
}

///|
fn App::render_output(self : App, output : Output) -> String {
  // Why not for every interpreter: a view transform is written in nu, so only
  // a nu input can take it in.
  let adopt = if self.programs[output.program].kind
    is Interpreter(language="nu") &&
    output.input.text != "" {
    Some(output.input.text)
  } else {
    None
  }
  let blocks = output.blocks.map(b => self.render_block(b, adopt))
  blocks.join("") + output.error.map(e => self.error_html(e)).unwrap_or("")
}

///|
fn App::error_html(self : App, msg : String) -> String {
  let copy = self.button(
    "コピー",
    CopyText(msg),
    title="エラーをコピー",
  )
  "<div class=\"error\" role=\"alert\"><span>\{@html.escape(msg)}</span>\{copy}</div>"
}

///|
fn App::render_block(self : App, b : Int32, adopt : String?) -> String {
  self.enter("b\{b}")
  let block = self.blocks[b]
  let source = (kind, text) => {
    "<div class=\"bar\"><span class=\"muted\">\{kind}</span>\{self.button("コピー", CopyText(text))}</div>"
  }
  match block.content {
    Data => self.render_data(b, adopt)
    Fragment(html) => "<div class=\"block md\">\{html}</div>"
    Diagram(src) => {
      let figure = @mermaid.to_svg(src).unwrap_or(
        "<pre>\{@html.escape(src)}</pre>",
      )
      "<div class=\"block\">\{source("Mermaid", src)}<div class=\"figure\">\{figure}</div></div>"
    }
    Page(html) =>
      "<div class=\"block\">\{source("HTML", html)}<iframe sandbox=\"allow-scripts\" srcdoc=\"\{@html.escape(html)}\"></iframe></div>"
    Image(src) =>
      "<div class=\"block\"><img src=\"\{@html.escape(src)}\" alt=\"\"></div>"
    Audio(src) =>
      "<div class=\"block\"><audio controls src=\"\{@html.escape(src)}\"></audio></div>"
    File(a) => {
      let preview = if a.is_text() {
        "<pre>\{@html.escape(a.data)}</pre>"
      } else {
        ""
      }
      "<div class=\"block\">\{source("\{@html.escape(a.name)} · \{@html.escape(a.media_type)}", a.data)}\{preview}</div>"
    }
  }
}

///|
fn App::render_data(self : App, b : Int32, adopt : String?) -> String {
  let block = self.blocks[b]
  let layouts = [("表", Layout::Table), ("ツリー", Tree), ("JSON", Json)].map(l => {
      let class = if l.1 == block.layout { "active" } else { "" }
      self.button(l.0, SetLayout(b, l.1), class~)
    },
  )
  let transform = if block.view_text == "" && !block.editing {
    self.button(
      "＋ 変換",
      EditView(b),
      title="出力を変えずに表示を変換する",
    )
  } else {
    ""
  }
  let formats = [
    ("Markdown", @view.Format::Md),
    ("TSV", Tsv),
    ("CSV", Csv),
    ("JSON", Json),
  ]
  let menu = if self.menu == Some(Copy(b)) {
    let items = formats.map(f => {
      let mark = if f.1 == self.copy_format { "✓ " } else { "" }
      self.button("\{mark}\{f.0}", CopyAs(b, f.1), class="item")
    })
    "<div class=\"menu\">\{items.join("")}</div>"
  } else {
    ""
  }
  let copy = "<span class=\"split\">\{self.button("コピー", CopyAll(b), title=self.copy_format.name())}\{self.button("▾", OpenCopy(b), title="形式を選んでコピー")}\{menu}</span>"
  let stale = if block.view_error is Some(_) { " stale" } else { "" }
  (
    $|<div class="block" data-b="\{b}"><div class="bar"><span class="muted">\{describe(block.shown)}</span>
    $|<nav class="segmented">\{layouts.join("")}</nav>\{transform}\{copy}</div>\{self.render_transform(b, adopt)}
    $|\{self.render_selection_bar(b)}<div class="view\{stale}">\{self.render_value(b)}</div></div>
  )
}

///|
/// Why not show the stages and the text together: they say the same thing;
/// the text replaces the stages only while it is being edited.
fn App::render_transform(self : App, b : Int32, adopt : String?) -> String {
  let block = self.blocks[b]
  guard block.view_text != "" || block.editing else { return "" }
  // Why not show stages while the text does not parse: they would show an
  // older transform than the text.
  let editing = block.editing ||
    (block.view_error is Some(_) && block.failed_stage is None)
  let body = if editing {
    let example = match shape_of(block.output) {
      Rows(_, [column, ..]) => "sort-by \{column}"
      Text(_) => "lines"
      _ => ""
    }
    "<input class=\"view-input\" data-view=\"\{b}\" value=\"\{@html.escape(block.view_text)}\" spellcheck=\"false\" autocomplete=\"off\" placeholder=\"\{@html.escape(example)}\">"
  } else {
    block.view
    .mapi((i, cmd) => {
      let failed = if block.failed_stage == Some(i) { " failed" } else { "" }
      "<span class=\"stage\{failed}\">\{code(@view.print_command(cmd))}\{self.button("×", Gui(b, RemoveStage(i)), title="この段を消す")}</span>"
    })
    .join("")
  }
  let toggle = self.button(
    if editing {
      "完了"
    } else {
      "編集"
    },
    EditView(b),
  )
  let adopt = match adopt {
    Some(src) if block.view_text.trim() != "" && block.view_error is None =>
      self.button(
        "入力に取り込む",
        UseInput("\{src} | \{block.view_text.trim()}"),
        title="この変換を処理系への入力に足す",
      )
    _ => ""
  }
  let error = block.view_error.map(e => self.error_html(e)).unwrap_or("")
  "<div class=\"transform\"><span class=\"muted\">変換</span>\{body}\{toggle}\{adopt}</div>\{error}"
}

///|
fn describe(v : Json) -> String {
  match shape_of(v) {
    Rows(rows, columns) => "\{rows.length()} 行 · \{columns.length()} 列"
    Items(items) => "\{items.length()} 件"
    Fields(fields) => "\{fields.length()} 項目"
    Text(s) => "テキスト · \{s.length()} 文字"
    Scalar(v) => @table.type_name(v)
  }
}

///|
fn App::render_selection_bar(self : App, b : Int32) -> String {
  let block = self.blocks[b]
  guard !block.selected.is_empty() else { return "" }
  // Why not `select ROW...` on a record: its rows are fields, kept by name.
  let (keep, cmd) : (@view.GuiAction, @view.Command) = match block.shown {
    Object(fields) => {
      let names = fields.keys().collect()
      let cols = block.selected.filter_map(r => names.get(r))
      (KeepColumns(cols), Select(cols))
    }
    _ => (KeepRows(block.selected.copy()), SelectRows(block.selected))
  }
  (
    $|<div class="selection"><span>\{block.selected.length()} 行を選択中</span>
    $|\{self.button("\{self.copy_format.name()} でコピー", CopySelection(b))}
    $|\{self.button("この行だけ残す \{code(@view.print_command(cmd))}", Gui(b, keep))}
    $|\{self.button("選択を解除", ClearSelection(b))}</div>
  )
}

///|
fn App::render_value(self : App, b : Int32) -> String {
  let block = self.blocks[b]
  let v = block.shown
  match (block.layout, shape_of(v)) {
    (Json, _) => "<pre>\{@html.escape(v.stringify(indent=2))}</pre>"
    (Tree, _) => "<div class=\"tree\">\{self.render_tree(b, v, [], 0)}</div>"
    (Table, Rows(rows, columns)) => self.render_rows(b, rows, columns)
    (Table, Items(items)) =>
      self.render_grid(b, ["<th>value</th>"], items.length(), r => {
        let v = items[r]
        let drill = if @table.is_scalar(v) {
          []
        } else {
          [self.gui_item(b, Drill([Idx(r)]), Get([Idx(r)]))]
        }
        [
          self.render_cell(b, r, 0, v, () => {
            [..self.filter_items(b, [], v), ..drill, self.copy_item(v)]
          }),
        ]
      })
    (Table, Fields(fields)) =>
      self.render_grid(
        b,
        ["<th>field</th>", "<th>value</th>"],
        fields.length(),
        r => {
          let (name, v) = fields[r]
          let path : Array[@view.Seg] = [Key(name)]
          [
            "<td class=\"key\" data-r=\"\{r}\" data-c=\"0\">\{@html.escape(name)}</td>",
            self.render_cell(b, r, 1, v, () => {
              [self.gui_item(b, Drill(path), Get(path)), self.copy_item(v)]
            }),
          ]
        },
      )
    (Table, Text(s)) => {
      let parse = [@view.Format::Json, Csv, Tsv].map(f => {
        self.gui_item(b, Append(From(f)), From(f))
      })
      (
        $|<pre>\{@html.escape(s)}</pre><div class="hint"><span class="muted">構造として読む</span>
        $|\{parse.join("")}\{self.gui_item(b, Append(Lines), Lines)}</div>
      )
    }
    (Table, Scalar(v)) =>
      "<div class=\"scalar\">\{@html.escape(@table.cell_text(v))}</div>"
  }
}

///|
fn App::gui_item(
  self : App,
  b : Int32,
  action : @view.GuiAction,
  cmd : @view.Command,
) -> String {
  self.button(code(@view.print_command(cmd)), Gui(b, action), class="item")
}

///|
/// Why not show timestamps and fractions as they come: nu sends datetimes as
/// ISO strings, which bury the date and time in offsets and fractions, and
/// measurements with digits nobody reads; the full value stays in the title
/// and in copies.
fn display(v : Json) -> (String, String, String) {
  match v {
    Number(n, ..) if (n * 100).round() / 100 != n =>
      (
        "num",
        Json::Json((n * 100).round() / 100).stringify(),
        @table.cell_text(v),
      )
    Number(_, ..) => ("num", @table.cell_text(v), "")
    True | False => ("bool", @table.cell_text(v), "")
    Null => ("null", "—", "")
    Array(_) | Object(_) => ("nested", @table.summary(v), "")
    String(s) =>
      lexmatch s[:] with longest {
        (re"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}" as prefix, after=_) =>
          ("date", prefix.to_owned().replace(old="T", new=" "), s)
        _ => ("", s, "")
      }
  }
}

///|
fn App::render_grid(
  self : App,
  b : Int32,
  header : Array[String],
  count : Int32,
  cells : (Int32) -> Array[String],
) -> String {
  let block = self.blocks[b]
  let all = if count > 0 && block.selected.length() == count {
    self.button(
      "☑",
      ClearSelection(b),
      class="check",
      title="選択を解除",
    )
  } else {
    self.button("☐", SelectAllRows(b), class="check", title="すべて選択")
  }
  let shown = if block.show_all { count } else { count.min(row_limit) }
  let rows = Array::makei(shown, r => {
    let selected = block.selected.contains(r)
    let check = self.button(
      if selected {
        "☑"
      } else {
        "☐"
      },
      ToggleRow(b, r),
      class="check",
      title="行を選択（Shift で範囲）",
    )
    "<tr class=\"\{if selected { "selected" } else { "" }}\"><td class=\"sel\">\{check}</td>\{cells(r).join("")}</tr>"
  })
  let more = if shown < count {
    "<div class=\"more\">\{self.button("残り \{count - shown} 行を表示", ShowAllRows(b))}</div>"
  } else {
    ""
  }
  let selecting = if block.selected.is_empty() { "" } else { " selecting" }
  "<div class=\"table-wrap\"><table class=\"grid\{selecting}\"><thead><tr><th class=\"sel\">\{all}</th>\{header.join("")}</tr></thead><tbody>\{rows.join("")}</tbody></table></div>\{more}"
}

///|
fn App::render_rows(
  self : App,
  b : Int32,
  rows : Array[Json],
  columns : Array[String],
) -> String {
  let sort = @view.sort_state(self.blocks[b].view)
  let header = columns.map(col => {
    let arrow = match sort {
      Some((c, reverse)) if c == col => if reverse { " ↓" } else { " ↑" }
      _ => ""
    }
    let sort_button = self.button(
      "\{@html.escape(col)}<span class=\"arrow\">\{arrow}</span>",
      Gui(b, SortColumn(col)),
      class="sort",
      title="並べ替え",
    )
    let hide = self.button(
      "×",
      Gui(b, HideColumn(col)),
      class="hide",
      title=@view.print_command(Reject([col])),
    )
    "<th>\{sort_button}\{hide}</th>"
  })
  self.render_grid(b, header, rows.length(), r => {
    columns.mapi((c, col) => {
      let v = @table.field(rows[r], col).unwrap_or(null)
      self.render_cell(b, r, c, v, () => {
        let path : Array[@view.Seg] = [Key(col)]
        let cell : Array[@view.Seg] = [Idx(r), Key(col)]
        [
          ..self.filter_items(b, path, v),
          ..if @table.is_scalar(v) {
            []
          } else {
            [self.gui_item(b, Drill(cell), Get(cell))]
          },
          self.gui_item(b, SortColumn(col), SortBy([col], reverse=false)),
          self.gui_item(b, Drill(path), Get(path)),
          self.gui_item(b, HideColumn(col), Reject([col])),
          self.copy_item(v),
        ]
      })
    })
  })
}

///|
/// Why not build every menu: each item registers an action.
fn App::render_cell(
  self : App,
  b : Int32,
  r : Int32,
  c : Int32,
  v : Json,
  menu : () -> Array[String],
) -> String {
  let (class, text, title) = display(v)
  let open = if self.menu == Some(Cell(b, r, c)) {
    "<div class=\"menu\">\{menu().join("")}</div>"
  } else {
    ""
  }
  "<td class=\"\{class}\" title=\"\{@html.escape(title)}\" data-r=\"\{r}\" data-c=\"\{c}\"\{self.act(OpenMenu(b, r, c))}>\{@html.escape(text)}\{open}</td>"
}

///|
fn App::filter_items(
  self : App,
  b : Int32,
  path : Array[@view.Seg],
  v : Json,
) -> Array[String] {
  let ops : Array[@view.CmpOp] = match v {
    Number(_, ..) => [Eq, Ne, Ge, Le]
    String(_) => [Eq, Ne, Contains]
    Array(_) | Object(_) => []
    _ => [Eq, Ne]
  }
  ops.map(op => self.gui_item(b, Filter(path, op, v), Where(Cmp(path, op, v))))
}

///|
fn App::copy_item(self : App, v : Json) -> String {
  self.button("値をコピー", CopyText(@table.value_text(v)), class="item")
}

///|
fn App::render_tree(
  self : App,
  b : Int32,
  v : Json,
  path : Array[@view.Seg],
  depth : Int32,
) -> String {
  let children : Array[(@view.Seg, String, Json)] = match v {
    Array(items) => items.mapi((i, item) => (Idx(i), i.to_string(), item))
    Object(fields) => fields.to_array().map(f => (Key(f.0), f.0, f.1))
    _ => {
      let (class, text, title) = display(v)
      return "<span class=\"\{class}\" title=\"\{@html.escape(title)}\">\{@html.escape(text)}</span>"
    }
  }
  let items = children.map(child => {
    let (seg, label, item) = child
    let child_path = [..path, seg]
    let key = "<span class=\"key\"\{self.act(Gui(b, Drill(child_path)))}>\{@html.escape(label)}</span>"
    let inner = self.render_tree(b, item, child_path, depth + 1)
    if @table.is_scalar(item) {
      "<li>\{key} \{inner}</li>"
    } else {
      let open = if depth < 2 { " open" } else { "" }
      "<li><details\{open}><summary>\{key} <span class=\"muted\">\{@html.escape(@table.summary(item))}</span></summary>\{inner}</details></li>"
    }
  })
  "<ul>\{items.join("")}</ul>"
}
