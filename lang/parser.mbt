///|
priv struct Parser {
  tokens : Array[(Tok, Int)]
  mut i : Int
}

///|
fn Parser::peek(self : Parser) -> Tok {
  self.tokens[self.i].0
}

///|
fn Parser::error(self : Parser, msg : String) -> ParseError {
  ParseError(pos=self.tokens[self.i].1, msg)
}

///|
fn Parser::next(self : Parser) -> Tok {
  let t = self.peek()
  if !(t is Eof) {
    self.i += 1
  }
  t
}

///|
fn Parser::at_stage_end(self : Parser) -> Bool {
  self.peek() is (Punct('|') | Eof)
}

///|
pub fn parse(src : String) -> Array[Command] raise ParseError {
  let p : Parser = { tokens: tokenize(src), i: 0, }
  let stages = []
  if p.peek() is Eof {
    return stages
  }
  while true {
    if p.at_stage_end() {
      raise p.error("expected a command")
    }
    stages.push(p.command())
    match p.next() {
      Punct('|') => continue
      Eof => break
      _ => raise p.error("unexpected input")
    }
  }
  stages
}

///|
pub let command_names : Array[String] = [
  "sort-by",
  "sort",
  "where",
  "select",
  "reject",
  "get",
  "first",
  "last",
  "skip",
  "from",
  "to",
  "math",
  "find",
  "parse",
  ..bare_commands.map(c => c.0),
]

///|
fn Parser::command(self : Parser) -> Command raise ParseError {
  let start = self.error("")
  let fail = msg => {
    let ParseError(pos~, _) = start
    ParseError(pos~, msg)
  }
  guard self.next() is Word(name) else { raise fail("expected a command") }
  let cmd = match name {
    "sort-by" => {
      let (columns, reverse) = self.names_and_reverse()
      guard !columns.is_empty() else { raise fail("sort-by needs a column") }
      SortBy(columns, reverse~)
    }
    "sort" => {
      let (columns, reverse) = self.names_and_reverse()
      guard columns.is_empty() else {
        raise self.error("sort takes no column; use sort-by")
      }
      Sort(reverse~)
    }
    "where" => Where(self.cond())
    "select" =>
      if self.peek() is Num(_) {
        let rows = []
        while self.count() is Some(n) {
          rows.push(n)
        }
        SelectRows(rows)
      } else {
        Select(self.columns("select"))
      }
    "reject" => Reject(self.columns("reject"))
    "get" => Get(self.path())
    "first" => First(self.count())
    "last" => Last(self.count())
    "skip" => Skip(self.count().unwrap_or_error(fail("skip needs a count")))
    "from" => {
      let err = self.error("cannot parse from this format")
      match self.format() {
        Md => raise err
        f => From(f)
      }
    }
    "to" => To(self.format())
    "math" =>
      match self.next() {
        Word(op) if lookup(math_ops, op) is Some(op) => Math(op)
        _ => raise fail("expected math sum, avg, min or max")
      }
    "find" =>
      match self.next() {
        Str(s) | Word(s) => Find(s)
        Num(n) => Find(Json::number(n).stringify())
        _ => raise fail("find needs a text")
      }
    "parse" =>
      match self.next() {
        Str(s) => Parse(s)
        _ => raise fail("parse needs a pattern such as \"{a} {b}\"")
      }
    _ =>
      match lookup(bare_commands, name) {
        Some(cmd) => cmd
        None => {
          let similar = command_names.filter(c => c.has_prefix(name))
          raise fail(
            if similar.is_empty() {
              "unknown command: \{name}"
            } else {
              "unknown command: \{name} (did you mean \{similar.join(", ")}?)"
            },
          )
        }
      }
  }
  if !self.at_stage_end() {
    raise self.error("unexpected argument to \{name}")
  }
  cmd
}

///|
fn Parser::names(self : Parser) -> Array[String] {
  let names = []
  while self.peek() is (Word(s) | Str(s)) {
    names.push(s)
    self.i += 1
  }
  names
}

///|
fn Parser::columns(
  self : Parser,
  cmd : String,
) -> Array[String] raise ParseError {
  let names = self.names()
  guard !names.is_empty() else { raise self.error("\{cmd} needs a column") }
  names
}

///|
fn Parser::reverse_flag(self : Parser) -> Bool raise ParseError {
  match self.peek() {
    Flag("--reverse" | "-r") => {
      self.i += 1
      true
    }
    Flag(f) => raise self.error("unknown flag: \{f}")
    _ => false
  }
}

///|
fn Parser::names_and_reverse(
  self : Parser,
) -> (Array[String], Bool) raise ParseError {
  let before = self.reverse_flag()
  let names = self.names()
  (names, self.reverse_flag() || before)
}

///|
fn Parser::count(self : Parser) -> Int? raise ParseError {
  guard self.peek() is Num(n) else { return None }
  if n != n.trunc() || n < 0 {
    raise self.error("expected a count")
  }
  self.i += 1
  Some(n.to_int())
}

///|
fn Parser::format(self : Parser) -> Format raise ParseError {
  match self.peek() {
    Word(f) if lookup(formats, f) is Some(format) => {
      self.i += 1
      format
    }
    _ => raise self.error("expected a format: json, csv, tsv or md")
  }
}

///|
fn seg_of_piece(piece : StringView) -> Seg {
  match number_of_word(piece) {
    Some(n) if n == n.trunc() => Idx(n.to_int())
    _ => Key(piece.to_owned())
  }
}

///|
fn path_of_word(w : StringView) -> Array[Seg] {
  w.split(".").map(seg_of_piece).collect()
}

///|
fn Parser::path(self : Parser) -> Array[Seg] raise ParseError {
  match self.next() {
    Word(w) => path_of_word(w)
    Str(s) => [Key(s)]
    Num(n) if n == n.trunc() && n >= 0 => [Idx(n.to_int())]
    Var("it") => []
    Var(v) if v.has_prefix("it.") => path_of_word(v[3:])
    Var(v) => raise self.error("unknown variable: $\{v}")
    QPath(parts) => {
      let parts = if parts is [("$it", false), .. rest] {
        rest
      } else {
        parts[:]
      }
      if parts is [(v, false), ..] && v.has_prefix("$") {
        raise self.error("unknown variable: \{v}")
      }
      parts
      .iter()
      .map(p => if p.1 { Seg::Key(p.0) } else { seg_of_piece(p.0) })
      .collect()
    }
    _ => raise self.error("expected a cell path")
  }
}

///|
fn Parser::cond(self : Parser) -> Cond raise ParseError {
  let mut left = self.cond_and()
  while self.peek() is Word("or") {
    self.i += 1
    left = Or(left, self.cond_and())
  }
  left
}

///|
fn Parser::cond_and(self : Parser) -> Cond raise ParseError {
  let mut left = self.cond_unary()
  while self.peek() is Word("and") {
    self.i += 1
    left = And(left, self.cond_unary())
  }
  left
}

///|
fn Parser::cond_unary(self : Parser) -> Cond raise ParseError {
  match self.peek() {
    Word("not") => {
      self.i += 1
      Not(self.cond_unary())
    }
    Punct('(') => {
      self.i += 1
      let c = self.cond()
      guard self.next() is Punct(')') else { raise self.error("expected ')'") }
      c
    }
    _ => {
      let path = self.path()
      let op = match self.peek() {
        Op(s) | Word(s) => lookup(cmp_ops, s)
        _ => None
      }
      guard op is Some(op) else {
        raise self.error("expected a comparison operator")
      }
      self.i += 1
      Cmp(path, op, self.value())
    }
  }
}

///|
/// Why not require quotes for strings: Nushell reads bare words such as
/// `where role == admin` and `[a b]` as strings.
fn Parser::value(self : Parser) -> Json raise ParseError {
  match self.peek() {
    Word(w) if !(w is ("true" | "false" | "null")) => {
      self.i += 1
      Json::string(w)
    }
    _ => self.literal()
  }
}

///|
fn Parser::literal(self : Parser) -> Json raise ParseError {
  let err = self.error("expected a value")
  match self.next() {
    Num(n) => Json::number(n)
    Str(s) => Json::string(s)
    Word("true") => true
    Word("false") => false
    Word("null") => null
    Punct('[') => {
      let items = []
      while !(self.peek() is Punct(']')) {
        guard !(self.peek() is Eof) else {
          raise self.error("unterminated list")
        }
        items.push(self.value())
        if self.peek() is Punct(',') {
          self.i += 1
        }
      }
      self.i += 1
      Json::array(items)
    }
    Punct('{') => {
      let fields = Map([])
      while !(self.peek() is Punct('}')) {
        let key = match self.next() {
          Word(w) | Str(w) => w
          Num(n) => Json::number(n).stringify()
          Eof => raise self.error("unterminated record")
          _ => raise self.error("expected a field name")
        }
        guard self.next() is Punct(':') else {
          raise self.error("expected ':'")
        }
        fields[key] = self.value()
        if self.peek() is Punct(',') {
          self.i += 1
        }
      }
      self.i += 1
      Json::object(fields)
    }
    _ => raise err
  }
}
