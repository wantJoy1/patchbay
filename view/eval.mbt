///|
pub suberror EvalError {
  EvalError(stage~ : Int32, String)
} derive(Debug)

///|
pub fn EvalError::message(self : EvalError) -> String {
  let EvalError(stage~, msg) = self
  "stage \{stage + 1}: \{msg}"
}

///|
pub fn EvalError::stage(self : EvalError) -> Int32 {
  let EvalError(stage~, _) = self
  stage
}

///|
priv suberror CmdError {
  CmdError(String)
}

///|
pub fn run(p : Array[Command], input : Json) -> Json raise EvalError {
  let mut v = input
  for i, cmd in p {
    v = step(cmd, v) catch { CmdError(msg) => raise EvalError(stage=i, msg) }
  }
  v
}

///|
fn expect_list(v : Json, cmd : String) -> Array[Json] raise CmdError {
  guard v is Array(items) else {
    raise CmdError("\{cmd} expects a list, got \{@table.type_name(v)}")
  }
  items
}

///|
fn expect_text(v : Json, cmd : String) -> String raise CmdError {
  guard v is String(s) else {
    raise CmdError("\{cmd} expects text, got \{@table.type_name(v)}")
  }
  s
}

///|
fn parse_as(text : String, format : Format) -> Json raise CmdError {
  match format {
    Json =>
      @json.parse(text) catch {
        e => raise CmdError("invalid JSON: \{e}")
      }
    Csv => @table.parse_delimited(text, ',')
    Tsv => @table.parse_delimited(text, '\t')
    Md => Json::Json(text)
  }
}

///|
pub fn serialize(v : Json, format : Format) -> String {
  match format {
    Json => v.stringify(indent=2)
    Csv => @table.to_delimited(v, ',')
    Tsv => @table.to_delimited(v, '\t')
    Md => @table.to_markdown(v)
  }
}

///|
fn record(fields : Array[(String, Json)]) -> Json {
  Json::Json(Map::from_array(fields))
}

///|
fn map_rows(
  v : Json,
  cmd : String,
  f : (Map[String, Json]) -> Json,
) -> Json raise CmdError {
  match v {
    Array(items) =>
      Json::Json(items.map(row => if row is Object(r) { f(r) } else { row }))
    Object(r) => f(r)
    _ =>
      raise CmdError(
        "\{cmd} expects a table or record, got \{@table.type_name(v)}",
      )
  }
}

///|
fn sorted(items : Array[Json], reverse : Bool, key : (Json) -> Json) -> Json {
  // Why not `sort_by` alone: it is not stable, and re-sorting a sorted table
  // by another column must keep the earlier order among ties.
  let indexed = items.mapi((i, v) => (i, v))
  indexed.sort_by((a, b) => {
    let c = @table.compare(key(a.1), key(b.1))
    if c != 0 {
      if reverse {
        -c
      } else {
        c
      }
    } else {
      a.0.compare(b.0)
    }
  })
  Json::Json(indexed.map(p => p.1))
}

///|
fn step(cmd : Command, input : Json) -> Json raise CmdError {
  match cmd {
    SortBy(columns, reverse~) =>
      sorted(expect_list(input, "sort-by"), reverse, row => {
        Json::Json(columns.map(c => @table.field(row, c).unwrap_or(null)))
      })
    Sort(reverse~) => sorted(expect_list(input, "sort"), reverse, v => v)
    Where(cond) =>
      Json::Json(
        expect_list(input, "where").filter(row => test_cond(cond, row)),
      )
    Select(columns) =>
      map_rows(input, "select", r => {
        record(columns.map(c => (c, r.get(c).unwrap_or(null))))
      })
    SelectRows(rows) => {
      let items = expect_list(input, "select")
      Json::Json(rows.filter_map(i => items.get(i)))
    }
    Reject(columns) =>
      map_rows(input, "reject", r => {
        record(r.iter().filter(f => !columns.contains(f.0)).collect())
      })
    Get(path) =>
      lookup(input, path).unwrap_or_error(
        CmdError("cannot find \{print_path(path)}"),
      )
    First(n) => take(input, n, from_end=false)
    Last(n) => take(input, n, from_end=true)
    Skip(n) => Json::Json(expect_list(input, "skip").iter().drop(n).collect())
    Length =>
      match input {
        Array(items) => Json::Json(items.length())
        Object(fields) => Json::Json(fields.length())
        _ =>
          raise CmdError(
            "length expects a list, got \{@table.type_name(input)}",
          )
      }
    Reverse => Json::Json(expect_list(input, "reverse").rev())
    Uniq => {
      let out = []
      for item in expect_list(input, "uniq") {
        if !out.contains(item) {
          out.push(item)
        }
      }
      Json::Json(out)
    }
    Columns => {
      let names = match input {
        Object(fields) => fields.keys().collect()
        Array(items) => @table.columns(items).unwrap_or([])
        _ =>
          raise CmdError(
            "columns expects a table or record, got \{@table.type_name(input)}",
          )
      }
      Json::Json(names)
    }
    Lines => Json::Json(split_lines(expect_text(input, "lines")))
    From(format) =>
      parse_as(expect_text(input, "from \{format.name()}"), format)
    To(format) => Json::Json(serialize(input, format))
    Math(op) => math(op, expect_list(input, "math \{op.name()}"))
    Parse(pattern) => {
      let lines = match input {
        String(text) => split_lines(text)
        Array(items) => items.map(@table.cell_text)
        _ =>
          raise CmdError("parse expects text, got \{@table.type_name(input)}")
      }
      Json::Json(lines.filter_map(line => match_pattern(pattern, line)))
    }
    Find(text) => {
      let rows = match input {
        String(s) => split_lines(s).map(line => Json::Json(line))
        _ => expect_list(input, "find")
      }
      Json::Json(rows.filter(row => contains_text(row, text, ignore_case=true)))
    }
  }
}

///|
fn take(input : Json, n : Int32?, from_end~ : Bool) -> Json raise CmdError {
  let name = if from_end { "last" } else { "first" }
  let items = expect_list(input, name)
  match n {
    None =>
      (if from_end { items.last() } else { items.get(0) }).unwrap_or_error(
        CmdError("\{name} on an empty list"),
      )
    Some(n) => {
      let n = @cmp.minimum(n, items.length())
      Json::Json(
        if from_end {
          items[items.length() - n:].to_owned()
        } else {
          items[:n].to_owned()
        },
      )
    }
  }
}

///|
/// Why not fail on a key applied to a list: mapping it over the rows makes
/// `get name` on a table give the column.
fn lookup(v : Json, path : ArrayView[Seg]) -> Json? {
  match (path, v) {
    ([], _) => Some(v)
    ([Idx(i), .. rest], Array(items)) =>
      items.get(i).bind(item => lookup(item, rest))
    ([Key(k), .. rest], Object(fields)) =>
      fields.get(k).bind(item => lookup(item, rest))
    ([Key(_), ..], Array(items)) => {
      let out = []
      for item in items {
        guard lookup(item, path) is Some(x) else { return None }
        out.push(x)
      }
      Some(Json::Json(out))
    }
    _ => None
  }
}

///|
fn test_cond(cond : Cond, row : Json) -> Bool {
  match cond {
    And(a, b) => test_cond(a, row) && test_cond(b, row)
    Or(a, b) => test_cond(a, row) || test_cond(b, row)
    Not(a) => !test_cond(a, row)
    Cmp(path, op, rhs) =>
      compare_cell(lookup(row, path).unwrap_or(null), op, rhs)
  }
}

///|
fn compare_cell(lhs : Json, op : CmpOp, rhs : Json) -> Bool {
  let ordered = (pred : (Int32) -> Bool) => {
    (lhs, rhs) is ((Number(_, ..), Number(_, ..)) | (String(_), String(_))) &&
    pred(@table.compare(lhs, rhs))
  }
  // Why not compare text case-insensitively: a view can be taken into a
  // Nushell input, where these operators are case-sensitive.
  let text = (f : (String, String) -> Bool) => {
    lhs is String(s) && rhs is String(t) && f(s, t)
  }
  match op {
    Eq => lhs == rhs
    Ne => lhs != rhs
    Lt => ordered(c => c < 0)
    Le => ordered(c => c <= 0)
    Gt => ordered(c => c > 0)
    Ge => ordered(c => c >= 0)
    Contains => contains_text(lhs, @table.cell_text(rhs))
    NotContains => !contains_text(lhs, @table.cell_text(rhs))
    StartsWith => text((s, t) => s.has_prefix(t))
    EndsWith => text((s, t) => s.has_suffix(t))
  }
}

///|
fn contains_text(
  v : Json,
  needle : String,
  ignore_case~ : Bool = false,
) -> Bool {
  let fold = (s : String) => if ignore_case { s.to_lower() } else { s }
  let needle = fold(needle)
  fn go(v : Json) -> Bool {
    match v {
      Array(items) => items.iter().any(go)
      Object(fields) => fields.values().any(go)
      Null => false
      _ => fold(@table.cell_text(v)).contains(needle)
    }
  }
  go(v)
}

///|
fn math(op : MathOp, items : Array[Json]) -> Json raise CmdError {
  let numbers = []
  for item in items {
    match item {
      Number(n, ..) => numbers.push(n)
      Null => ()
      _ =>
        raise CmdError(
          "math \{op.name()} expects numbers, got \{@table.type_name(item)}",
        )
    }
  }
  let sum = numbers.fold(init=0.0, (a, n) => a + n)
  if op is Sum {
    return Json::Json(sum)
  }
  guard numbers is [first, ..] else {
    raise CmdError("math \{op.name()} on an empty list")
  }
  Json::Json(
    match op {
      Min => numbers.fold(init=first, @cmp.minimum)
      Max => numbers.fold(init=first, @cmp.maximum)
      _ => sum / numbers.length().to_double()
    },
  )
}

///|
fn split_lines(text : String) -> Array[String] {
  let lines = text
    .split("\n")
    .map(l => l.trim_end(chars="\r").to_owned())
    .collect()
  if lines.last() is Some("") {
    lines.pop() |> ignore
  }
  lines
}

///|
fn match_pattern(pattern : String, line : String) -> Json? {
  let fields = Map([])
  let mut rest = line[:]
  let mut pat = pattern[:]
  while pat is [_, ..] {
    match pat.find("{") {
      Some(0) => {
        let close = pat.find("}").unwrap_or(pat.length())
        let name = pat[1:close].to_owned()
        pat = if close < pat.length() { pat[close + 1:] } else { "" }
        let literal = pat[:pat.find("{").unwrap_or(pat.length())]
        guard (if literal == "" {
            Some(rest.length())
          } else {
            rest.find(literal)
          })
          is Some(end) else {
          return None
        }
        fields[name] = @table.infer(rest[:end].trim().to_owned())
        rest = rest[end:]
      }
      at => {
        let literal = pat[:at.unwrap_or(pat.length())]
        guard rest.has_prefix(literal) else { return None }
        rest = rest[literal.length():]
        pat = pat[literal.length():]
      }
    }
  }
  if rest != "" || fields.is_empty() {
    return None
  }
  Some(Json::Json(fields))
}
