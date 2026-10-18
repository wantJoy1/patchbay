///|
priv enum Content {
  Data
  Fragment(String)
  Diagram(String)
  Page(String)
  Image(String)
  Audio(String)
  File(@program.Attachment)
}

///|
priv struct Block {
  content : Content
  output : Json
  mut view : Array[@view.Command]
  mut view_text : String
  mut view_error : String?
  mut failed_stage : Int32?
  mut shown : Json
  selected : Array[Int32]
  mut anchor : Int32?
  mut layout : Layout
  mut show_all : Bool
  mut editing : Bool
}

///|
fn Block::new(content : Content, output~ : Json = null) -> Block {
  {
    content,
    output,
    view: [],
    view_text: "",
    view_error: None,
    failed_stage: None,
    shown: output,
    selected: [],
    anchor: None,
    layout: Table,
    show_all: false,
    editing: false,
  }
}

///|
fn blocks_of(part : @program.Part) -> Array[Block] {
  match part {
    Markdown(md) =>
      @markdown.split(md).map(b => {
        match b {
          Html(html) => Block::new(Fragment(html))
          Table(v) => Block::new(Data, output=v)
          Mermaid(code) => Block::new(Diagram(code))
        }
      })
    Mermaid(code) => [Block::new(Diagram(code))]
    Html(html) => [Block::new(Page(html))]
    Data(v) => [Block::new(Data, output=v)]
    Text(s) => [Block::new(Data, output=Json::Json(s))]
    Image(src) => [Block::new(Image(src))]
    Audio(src) => [Block::new(Audio(src))]
    File(a) => [Block::new(File(a))]
  }
}

///|
fn Block::set_view_text(self : Block, src : String) -> Bool {
  self.view_text = src
  let view = @view.parse(src) catch {
    e => {
      self.view_error = Some(e.message())
      self.failed_stage = None
      return false
    }
  }
  self.run(view)
}

///|
fn Block::run(self : Block, view : Array[@view.Command]) -> Bool {
  self.view = view
  let value = @view.run(view, self.output) catch {
    e => {
      self.view_error = Some(e.message())
      self.failed_stage = Some(e.stage())
      return false
    }
  }
  self.view_error = None
  self.failed_stage = None
  guard value != self.shown else { return false }
  self.shown = value
  self.selected.clear()
  self.anchor = None
  self.show_all = false
  true
}

///|
/// Why not apply while the view has an error: the shown value is stale, so the
/// action would rewrite something else than what is seen; only removing a
/// stage of a view that runs but fails stays possible, as a way to fix it.
fn Block::apply(self : Block, action : @view.GuiAction) -> Result[Bool, String] {
  if self.view_error is Some(_) &&
    !(action is RemoveStage(_) && self.failed_stage is Some(_)) {
    return Err(
      "表示の変換のエラーを直してから操作してください",
    )
  }
  let view = @view.apply(self.view, action)
  self.view_text = @view.print(view)
  Ok(self.run(view))
}

///|
fn Block::toggle_row(self : Block, r : Int32, shift~ : Bool) -> Unit {
  match (shift, self.anchor) {
    (true, Some(a)) =>
      for i in a.min(r)..<=a.max(r) {
        if !self.selected.contains(i) {
          self.selected.push(i)
        }
      }
    _ => {
      match self.selected.search(r) {
        Some(i) => self.selected.remove(i) |> ignore
        None => self.selected.push(r)
      }
      self.anchor = Some(r)
    }
  }
  self.selected.sort()
}

///|
priv enum Shape {
  Rows(Array[Json], Array[String])
  Items(Array[Json])
  Fields(Array[(String, Json)])
  Text(String)
  Scalar(Json)
}

///|
fn shape_of(v : Json) -> Shape {
  match v {
    Array(items) =>
      match @table.columns(items) {
        Some(columns) => Rows(items, columns)
        None => Items(items)
      }
    Object(fields) => Fields(fields.to_array())
    String(s) => Text(s)
    _ => Scalar(v)
  }
}

///|
fn Block::row_count(self : Block) -> Int32 {
  match shape_of(self.shown) {
    Rows(rows, _) | Items(rows) => rows.length()
    Fields(fields) => fields.length()
    _ => 0
  }
}

///|
fn Block::sub_value(
  self : Block,
  rows : Array[Int32],
  cols : Array[Int32]?,
) -> Json? {
  let record = fields => Json::Json(Map::from_array(fields))
  match shape_of(self.shown) {
    Rows(items, columns) => {
      let picked = rows.filter_map(r => items.get(r))
      let names = match cols {
        Some(cols) => cols.filter_map(c => columns.get(c))
        None => columns
      }
      Some(
        Json::Json(
          picked.map(row => {
            record(names.map(n => (n, @table.field(row, n).unwrap_or(null))))
          }),
        ),
      )
    }
    Items(items) => Some(Json::Json(rows.filter_map(r => items.get(r))))
    Fields(fields) => {
      let picked = rows.filter_map(r => fields.get(r))
      match cols {
        Some([0]) => Some(Json::Json(picked.map(f => Json::Json(f.0))))
        Some([1]) => Some(Json::Json(picked.map(f => f.1)))
        _ => Some(record(picked))
      }
    }
    _ => None
  }
}

///|
fn Block::selection_text(self : Block, format : @view.Format) -> String {
  self
  .sub_value(self.selected, None)
  .map(v => @view.serialize(v, format))
  .unwrap_or("")
}

///|
/// Why not copy the selected characters: they are the drawing, with borders and
/// wrapping, not the data behind the cells.
fn Block::copy_cells(
  self : Block,
  rows : Array[Int32],
  cols : Array[Int32],
  format : @view.Format,
) -> String {
  guard self.sub_value(rows, Some(cols)) is Some(sub) && !rows.is_empty() else {
    return ""
  }
  guard rows.length() == 1 && cols.length() == 1 else {
    return @view.serialize(sub, format)
  }
  let cell = match sub {
    Array([Object(fields)]) => fields.values().next().unwrap_or(null)
    Array([v]) => v
    _ => sub
  }
  @table.value_text(cell)
}
