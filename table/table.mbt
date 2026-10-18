///|
pub fn type_name(v : Json) -> String {
  match v {
    Null => "null"
    True | False => "bool"
    Number(_, ..) => "number"
    String(_) => "string"
    Array(_) => "list"
    Object(_) => "record"
  }
}

///|
pub fn is_scalar(v : Json) -> Bool {
  !(v is (Array(_) | Object(_)))
}

///|
pub fn field(v : Json, name : String) -> Json? {
  guard v is Object(fields) else { return None }
  fields.get(name)
}

///|
pub fn index(v : Json, i : Int32) -> Json? {
  guard v is Array(items) else { return None }
  items.get(if i < 0 { items.length() + i } else { i })
}

///|
pub fn columns(rows : Array[Json]) -> Array[String]? {
  guard !rows.is_empty() else { return None }
  let columns = []
  for row in rows {
    guard row is Object(fields) else { return None }
    for name, _ in fields {
      if !columns.contains(name) {
        columns.push(name)
      }
    }
  }
  Some(columns)
}

///|
fn rank(v : Json) -> Int32 {
  match v {
    Null => 0
    True | False => 1
    Number(_, ..) => 2
    String(_) => 3
    Array(_) => 4
    Object(_) => 5
  }
}

///|
pub fn compare(a : Json, b : Json) -> Int32 {
  match (a, b) {
    (Number(x, ..), Number(y, ..)) => x.compare(y)
    // Why not `String::compare`: it orders by length first.
    (String(x), String(y)) =>
      compare_lists(x.to_array(), y.to_array(), Char::compare)
    (Array(xs), Array(ys)) => compare_lists(xs, ys, compare)
    (Object(xs), Object(ys)) =>
      compare_lists(xs.values().collect(), ys.values().collect(), compare)
    _ => rank(a).compare(rank(b))
  }
}

///|
fn[T] compare_lists(
  xs : Array[T],
  ys : Array[T],
  cmp : (T, T) -> Int32,
) -> Int32 {
  for i in 0..<@cmp.minimum(xs.length(), ys.length()) {
    let c = cmp(xs[i], ys[i])
    if c != 0 {
      return c
    }
  }
  xs.length().compare(ys.length())
}

///|
pub fn cell_text(v : Json) -> String {
  match v {
    Null => ""
    String(s) => s
    _ => v.stringify()
  }
}

///|
pub fn summary(v : Json) -> String {
  match v {
    Array([_]) => "[1 item]"
    Array(items) => "[\{items.length()} items]"
    Object(fields) => {
      let names = fields.keys().collect()
      let shown = names.length() > 4
      let names = if shown { names[:4].to_owned() } else { names }
      "{\{names.join(", ")}\{if shown { ", …" } else { "" }}}"
    }
    _ => cell_text(v)
  }
}

///|
pub fn infer(s : String) -> Json {
  lexmatch s[:] with longest {
    re"^$" => null
    re"^true$" => true
    re"^false$" => false
    re"^(\+|-)?([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE](\+|-)?[0-9]+)?$" =>
      Json(@string.parse_double(s)) catch {
        _ => Json(s)
      }
    _ => Json(s)
  }
}

///|
pub fn grid(v : Json) -> (Array[String], Array[Array[String]])? {
  match v {
    Array(items) =>
      match columns(items) {
        Some(cols) =>
          Some(
            (
              cols,
              items.map(row => {
                cols.map(c => cell_text(field(row, c).unwrap_or(null)))
              }),
            ),
          )
        None => Some((["value"], items.map(item => [cell_text(item)])))
      }
    Object(fields) =>
      Some((["field", "value"], [ for k, v in fields => [k, cell_text(v)] ]))
    _ => None
  }
}

///|
pub fn to_markdown(v : Json) -> String {
  guard grid(v) is Some((header, rows)) else { return cell_text(v) }
  let line = (cells : Array[String]) => {
    let escaped = cells.map(c => {
      c
      .replace_all(old="\\", new="\\\\")
      .replace_all(old="|", new="\\|")
      .replace_all(old="\n", new="<br>")
    })
    "| \{escaped.join(" | ")} |\n"
  }
  [line(header), line(header.map(_ => "---")), ..rows.map(line)].join("")
}

///|
pub fn to_delimited(v : Json, sep : Char) -> String {
  guard grid(v) is Some((header, rows)) else { return cell_text(v) }
  let quote = (s : String) => {
    // Why not quote every field with a quote in TSV: spreadsheets read
    // TSV leniently and only treat a quote that opens a field as quoting.
    let has_quote = if sep == ',' {
      s.contains_char('"')
    } else {
      s.has_prefix("\"")
    }
    if has_quote ||
      s.contains_char(sep) ||
      s.contains_char('\n') ||
      s.contains_char('\r') {
      "\"\{s.replace_all(old="\"", new="\"\"")}\""
    } else {
      s
    }
  }
  [header, ..rows]
  .map(row => row.map(quote).join(sep.to_string()) + "\n")
  .join("")
}

///|
pub fn parse_delimited(text : String, sep : Char) -> Json {
  guard split_delimited(text, sep) is [header, .. body] else { return [] }
  Json(
    body.map(cells => {
      Json(
        Map::from_array(
          header.mapi((i, name) => (name, infer(cells.get(i).unwrap_or("")))),
        ),
      )
    }),
  )
}

///|
fn split_delimited(text : String, sep : Char) -> Array[Array[String]] {
  let rows = []
  let row = []
  let field = StringBuilder()
  let mut quoted = false
  let mut started = false
  let mut prev_quote = false
  let end_field = () => {
    row.push(field.to_string())
    field.reset()
  }
  let end_row = () => {
    if started {
      end_field()
      rows.push(row.copy())
    }
    row.clear()
    started = false
  }
  for c in text {
    if quoted {
      if c == '"' {
        quoted = false
        prev_quote = true
      } else {
        field.write_char(c)
      }
      continue
    }
    if c == '"' {
      if prev_quote {
        field.write_char('"')
      }
      quoted = true
      started = true
    } else if c == sep {
      end_field()
      started = true
    } else if c == '\n' {
      end_row()
    } else if c != '\r' {
      field.write_char(c)
      started = true
    }
    prev_quote = false
  }
  end_row()
  rows
}
