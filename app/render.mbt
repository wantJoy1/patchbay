///|
let row_limit = 200

///|
fn escape_html(s : String) -> String {
  s
  .replace_all(old="&", new="&amp;")
  .replace_all(old="<", new="&lt;")
  .replace_all(old=">", new="&gt;")
  .replace_all(old="\"", new="&quot;")
}

///|
fn App::act(self : App, action : UiAction) -> String {
  let key = "\{self.scope}.\{self.next_act}"
  self.next_act += 1
  self.actions[key] = action
  " data-act=\"\{key}\""
}

///|
fn App::button(
  self : App,
  label : String,
  action : UiAction,
  class? : String = "",
  title? : String = "",
) -> String {
  "<button class=\"\{class}\" title=\"\{escape_html(title)}\"\{self.act(action)}>\{label}</button>"
}

///|
fn code(text : String) -> String {
  "<code>\{escape_html(text)}</code>"
}

///|
fn App::gui_item(
  self : App,
  b : Int,
  action : @action.GuiAction,
  cmd : @lang.Command,
) -> String {
  self.button(code(@lang.print_command(cmd)), Gui(b, action), class="item")
}

///|
fn App::render(self : App) -> (String, String) {
  self.actions.clear()
  self.scope = "w"
  self.next_act = 0
  let entries = if self.entries.is_empty() {
    [self.render_welcome()]
  } else {
    self.entries.mapi((i, e) => {
      self.scope = "e\{i}"
      self.next_act = 0
      self.render_entry(i, e)
    })
  }
  self.scope = "c"
  self.next_act = 0
  let programs = self.programs.mapi((i, p) => {
    self.button(
      escape_html(p.name),
      SelectProgram(i),
      class=if i == self.current { "tab active" } else { "tab" },
    )
  })
  let pending = self.pending.mapi((i, a) => {
    "<span class=\"chip\">\{escape_html(a.name)}\{self.button("×", RemoveAttachment(i), class="remove")}</span>"
  })
  (
    "<div>\{entries.join("")}</div>",
    "<nav class=\"programs\">\{programs.join("")}</nav><div class=\"pending\">\{pending.join("")}</div>",
  )
}

///|
fn App::placeholder(self : App) -> String {
  match self.programs[self.current].kind {
    Interpreter(_) => "ls | sort-by size"
    Agent => "表と図で説明して"
  }
}

///|
fn App::render_welcome(self : App) -> String {
  let examples = match self.programs[self.current].kind {
    Interpreter(_) => ["ls", "ps", "sys host", "help commands"]
    Agent =>
      [
        "表を見せて", "図で説明して", "HTML のページを作って",
        "画像と音を出して", "CSV ファイルをちょうだい",
      ]
  }
  let items = examples.map(e => "<li>\{self.button(code(e), Send(e))}</li>")
  (
    $|<div class="welcome" data-key="w\{self.current}"><p>入力して Enter で、選んだ処理プログラムに送ります。
    $|出力の表への並べ替えや絞り込みは、出力そのものではなく、出力ごとの「表示の変換」に式として書き込まれます。</p>
    $|<ul>\{items.join("")}</ul></div>
  )
}

///|
fn App::render_entry(self : App, i : Int, entry : Entry) -> String {
  let program = self.programs[entry.program]
  let text = entry.input.text
  let said = if text == "" {
    ""
  } else {
    "<pre class=\"input-text\">\{escape_html(text)}</pre>\{self.button("入力に戻す", UseInput(text), class="small")}"
  }
  let attachments = entry.input.attachments.map(a => {
    "<span class=\"chip\">\{escape_html(a.name)}</span>"
  })
  let running = if entry.running {
    "<div class=\"running\">実行中…\{self.button("中断", Cancel(i), class="small")}</div>"
  } else {
    ""
  }
  let steps = entry.steps.map(step => {
    let name = escape_html(self.programs[step.program].name)
    "<div class=\"step\"><div class=\"said\"><span class=\"who\">AI → \{name}</span>\{code(step.input.text)}</div>\{self.render_reply(step)}</div>"
  })
  let markdown = entry.parts.filter_map(p => {
    if p is Markdown(md) {
      Some(md)
    } else {
      None
    }
  })
  let tools = if markdown.is_empty() {
    ""
  } else {
    self.button(
      "元の Markdown をコピー",
      CopyText(markdown.join("\n\n")),
      class="small",
    )
  }
  (
    $|<section class="entry" data-key="e\{i}"><div class="said"><span class="who">\{escape_html(program.name)}</span>
    $|\{said}\{attachments.join("")}</div>\{steps.join("")}\{self.render_reply(entry)}\{running}\{tools}</section>
  )
}

///|
fn App::render_reply(self : App, entry : Entry) -> String {
  // Why not for every interpreter: a view transform is written in nu, so only
  // a nu input can take it in.
  let adopt = if self.programs[entry.program].kind is Interpreter(language="nu") &&
    entry.input.text != "" {
    Some(entry.input.text)
  } else {
    None
  }
  let blocks = entry.blocks.map(b => self.render_block(b, adopt))
  blocks.join("") + entry.error.map(error_html).unwrap_or("")
}

///|
fn error_html(msg : String) -> String {
  "<div class=\"error\" role=\"alert\">\{escape_html(msg)}</div>"
}

///|
fn App::render_block(self : App, b : Int, adopt : String?) -> String {
  let block = self.blocks[b]
  let copy = (label, text) => self.button(label, CopyText(text), class="small")
  match block.content {
    Data => {
      let stale = if block.view_error is Some(_) { " stale" } else { "" }
      (
        $|<div class="block data" data-b="\{b}">\{self.render_toolbar(b)}\{self.render_view_bar(b, adopt)}
        $|\{self.render_selection_bar(b)}<div class="view\{stale}">\{self.render_value(b)}</div></div>
      )
    }
    Fragment(html) => "<div class=\"block md\">\{html}</div>"
    Diagram(src) => {
      let figure = @mermaid.to_svg(src).unwrap_or(
        "<pre>\{escape_html(src)}</pre>",
      )
      "<div class=\"block diagram\">\{figure}\{copy("Mermaid をコピー", src)}</div>"
    }
    Page(html) =>
      "<div class=\"block page\"><iframe sandbox=\"allow-scripts\" srcdoc=\"\{escape_html(html)}\"></iframe>\{copy("HTML をコピー", html)}</div>"
    Image(src) =>
      "<div class=\"block\"><img src=\"\{escape_html(src)}\" alt=\"\"></div>"
    Audio(src) =>
      "<div class=\"block\"><audio controls src=\"\{escape_html(src)}\"></audio></div>"
    File(data, name~, media_type~) => {
      let preview = if data.has_prefix("data:") {
        ""
      } else {
        "<pre>\{escape_html(data)}</pre>"
      }
      "<div class=\"block file\"><b>\{escape_html(name)}</b> <span class=\"info\">\{escape_html(media_type)}</span>\{copy("内容をコピー", data)}\{preview}</div>"
    }
  }
}

///|
fn App::render_view_bar(self : App, b : Int, adopt : String?) -> String {
  let block = self.blocks[b]
  // Why not show stages while the text does not parse: they would show an
  // older transform than the one being edited.
  let stages = if block.view_error is Some(_) && block.failed_stage is None {
    []
  } else {
    block.view.mapi((i, cmd) => {
      let failed = if block.failed_stage == Some(i) { " failed" } else { "" }
      "<span class=\"stage\{failed}\">\{code(@lang.print_command(cmd))}\{self.button("×", Gui(b, RemoveStage(i)), class="remove")}</span>"
    })
  }
  let adopt = match adopt {
    Some(src) if block.view_text.trim() != "" && block.view_error is None =>
      self.button(
        "入力に取り込む",
        UseInput("\{src} | \{block.view_text.trim()}"),
        class="small",
      )
    _ => ""
  }
  let error = block.view_error.map(error_html).unwrap_or("")
  (
    $|<div class="viewbar"><span class="label">表示の変換</span>\{stages.join("")}
    $|<input class="view-input" data-view="\{b}" value="\{escape_html(block.view_text)}" spellcheck="false" autocomplete="off" placeholder="sort-by age | where age &gt; 30">\{adopt}</div>\{error}
  )
}

///|
fn describe(v : Json) -> String {
  match shape_of(v) {
    Rows(rows, columns) =>
      "表 · \{rows.length()} 行 × \{columns.length()} 列"
    Items(items) => "リスト · \{items.length()} 件"
    Fields(fields) => "レコード · \{fields.length()} フィールド"
    Text(s) => "テキスト · \{s.length()} 文字"
    Scalar(v) => @table.type_name(v)
  }
}

///|
fn App::render_toolbar(self : App, b : Int) -> String {
  let block = self.blocks[b]
  let tab = (label, active, action) => {
    self.button(label, action, class=if active { "tab active" } else { "tab" })
  }
  let modes = [("table", Layout::Table), ("tree", Tree), ("json", Json)].map(m => {
    tab(m.0, m.1 == block.layout, SetLayout(b, m.1))
  })
  let formats = [@lang.Format::Md, Tsv, Csv, Json].map(f => {
    tab(f.name(), f == self.copy_format, SetCopyFormat(f))
  })
  let all = self.button(
    "全体をコピー",
    CopyText(@eval.serialize(block.shown, self.copy_format)),
    class="tab",
  )
  "<div class=\"toolbar\"><b>\{describe(block.shown)}</b><span>表示: \{modes.join("")}</span><span>コピー形式: \{formats.join("")}\{all}</span></div>"
}

///|
fn App::render_selection_bar(self : App, b : Int) -> String {
  let block = self.blocks[b]
  guard !block.selected.is_empty() else { return "" }
  // Why not `select ROW...` on a record: its rows are fields, kept by name.
  let (keep, cmd) : (@action.GuiAction, @lang.Command) = match block.shown {
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
    $|\{self.button("この行だけ残す \{code(@lang.print_command(cmd))}", Gui(b, keep))}
    $|\{self.button("選択を解除", ClearSelection(b))}</div>
  )
}

///|
fn App::render_value(self : App, b : Int) -> String {
  let block = self.blocks[b]
  let v = block.shown
  match (block.layout, shape_of(v)) {
    (Json, _) => "<pre>\{escape_html(v.stringify(indent=2))}</pre>"
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
          let path : Array[@lang.Seg] = [Key(name)]
          [
            "<td class=\"cell key\" data-r=\"\{r}\" data-c=\"0\">\{escape_html(name)}</td>",
            self.render_cell(b, r, 1, v, () => {
              [self.gui_item(b, Drill(path), Get(path)), self.copy_item(v)]
            }),
          ]
        },
      )
    (Table, Text(s)) => {
      let parse = [@lang.Format::Json, Csv, Tsv].map(f => {
        self.gui_item(b, Append(From(f)), From(f))
      })
      (
        $|<div class="text-actions">構造として読む: \{parse.join("")}\{self.gui_item(b, Append(Lines), Lines)}
        $|\{self.button("値をコピー", CopyText(s))}</div><pre>\{escape_html(s)}</pre>
      )
    }
    (Table, Scalar(v)) =>
      "<div class=\"scalar\">\{escape_html(@table.cell_text(v))}</div>"
  }
}

///|
fn cell_class(v : Json) -> String {
  match v {
    Number(_, ..) => "num"
    True | False => "bool"
    Null => "null"
    Array(_) | Object(_) => "nested"
    String(_) => "str"
  }
}

///|
fn App::render_grid(
  self : App,
  b : Int,
  header : Array[String],
  count : Int,
  cells : (Int) -> Array[String],
) -> String {
  let block = self.blocks[b]
  let all = if count > 0 && block.selected.length() == count {
    self.button("☑", ClearSelection(b), class="check")
  } else {
    self.button("☐", SelectAllRows(b), class="check")
  }
  let shown = if block.show_all {
    count
  } else {
    @cmp.minimum(count, row_limit)
  }
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
      title="Shift で範囲",
    )
    "<tr class=\"\{if selected { "selected" } else { "" }}\"><td class=\"sel\">\{check}</td><td class=\"idx\">\{r}</td>\{cells(r).join("")}</tr>"
  })
  let more = if shown < count {
    "<div class=\"more\">\{self.button("残り \{count - shown} 行を表示", ShowAllRows(b))}</div>"
  } else {
    ""
  }
  "<div class=\"table-wrap\"><table class=\"grid\"><thead><tr><th class=\"sel\">\{all}</th><th class=\"idx\">#</th>\{header.join("")}</tr></thead><tbody>\{rows.join("")}</tbody></table></div>\{more}"
}

///|
fn App::render_rows(
  self : App,
  b : Int,
  rows : Array[Json],
  columns : Array[String],
) -> String {
  let sort = @action.sort_state(self.blocks[b].view)
  let header = columns.map(col => {
    let arrow = match sort {
      Some((c, reverse)) if c == col => if reverse { " ▼" } else { " ▲" }
      _ => ""
    }
    let sort_button = self.button(
      "\{escape_html(col)}<span class=\"arrow\">\{arrow}</span>",
      Gui(b, SortColumn(col)),
      class="sort",
    )
    let hide = self.button(
      "×",
      Gui(b, HideColumn(col)),
      class="hide",
      title=@lang.print_command(Reject([col])),
    )
    "<th>\{sort_button}\{hide}</th>"
  })
  self.render_grid(b, header, rows.length(), r => {
    columns.mapi((c, col) => {
      let v = @table.field(rows[r], col).unwrap_or(null)
      self.render_cell(b, r, c, v, () => {
        let path : Array[@lang.Seg] = [Key(col)]
        let cell : Array[@lang.Seg] = [Idx(r), Key(col)]
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
  b : Int,
  r : Int,
  c : Int,
  v : Json,
  menu : () -> Array[String],
) -> String {
  let text = if @table.is_scalar(v) {
    @table.cell_text(v)
  } else {
    @table.summary(v)
  }
  let open = if self.menu == Some((b, r, c)) {
    "<div class=\"menu\">\{menu().join("")}\{self.button("閉じる", CloseMenu, class="item close")}</div>"
  } else {
    ""
  }
  "<td class=\"cell \{cell_class(v)}\" data-r=\"\{r}\" data-c=\"\{c}\"\{self.act(OpenMenu(b, r, c))}>\{escape_html(text)}\{open}</td>"
}

///|
fn App::filter_items(
  self : App,
  b : Int,
  path : Array[@lang.Seg],
  v : Json,
) -> Array[String] {
  let ops : Array[@lang.CmpOp] = match v {
    Number(_, ..) => [Eq, Ne, Ge, Le]
    String(_) => [Eq, Ne, Contains]
    Array(_) | Object(_) => []
    _ => [Eq, Ne]
  }
  ops.map(op => self.gui_item(b, Filter(path, op, v), Where(Cmp(path, op, v))))
}

///|
fn App::copy_item(self : App, v : Json) -> String {
  let text = if @table.is_scalar(v) {
    @table.cell_text(v)
  } else {
    v.stringify(indent=2)
  }
  self.button("値をコピー", CopyText(text), class="item")
}

///|
fn App::render_tree(
  self : App,
  b : Int,
  v : Json,
  path : Array[@lang.Seg],
  depth : Int,
) -> String {
  let children : Array[(@lang.Seg, String, Json)] = match v {
    Array(items) => items.mapi((i, item) => (Idx(i), i.to_string(), item))
    Object(fields) => fields.to_array().map(f => (Key(f.0), f.0, f.1))
    _ =>
      return "<span class=\"\{cell_class(v)}\">\{escape_html(@table.cell_text(v))}</span>"
  }
  let items = children.map(child => {
    let (seg, label, item) = child
    let child_path = [..path, seg]
    let key = "<span class=\"key\"\{self.act(Gui(b, Drill(child_path)))}>\{escape_html(label)}</span>"
    let inner = self.render_tree(b, item, child_path, depth + 1)
    if @table.is_scalar(item) {
      "<li>\{key}: \{inner}</li>"
    } else {
      let open = if depth < 2 { " open" } else { "" }
      "<li><details\{open}><summary>\{key} <span class=\"summary\">\{escape_html(@table.summary(item))}</span></summary>\{inner}</details></li>"
    }
  })
  "<ul>\{items.join("")}</ul>"
}
