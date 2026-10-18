///|
fn is_bare_safe(s : String) -> Bool {
  !(s is ("" | "true" | "false" | "null" | "and" | "or" | "not")) &&
  !s.has_prefix("-") &&
  !s.has_prefix("$") &&
  number_of_word(s) is None &&
  !s.iter().any(c => is_delimiter(c) || c == '\\')
}

///|
pub fn quote_string(s : String) -> String {
  Json::string(s).stringify()
}

///|
pub fn print_name(s : String) -> String {
  if is_bare_safe(s) {
    s
  } else {
    quote_string(s)
  }
}

///|
pub fn print_path(path : Array[Seg]) -> String {
  let bare = (k : String) => is_bare_safe(k) && !k.contains_char('.')
  let text = path
    .map(seg => {
      match seg {
        Key(k) => if bare(k) { k } else { quote_string(k) }
        Idx(i) => i.to_string()
      }
    })
    .join(".")
  match path {
    [] => "$it"
    [_] => text
    // Why not print every path bare: a path may not start with a quote, and
    // `2.8` would read as a number.
    [Key(k), ..] if !bare(k) => "$it.\{text}"
    _ if number_of_word(text) is Some(_) => "$it.\{text}"
    _ => text
  }
}

///|
fn cond_precedence(c : Cond) -> Int {
  match c {
    Or(_, _) => 0
    And(_, _) => 1
    Not(_) | Cmp(_, _, _) => 2
  }
}

///|
pub fn print_cond(c : Cond) -> String {
  let sub = (inner, min) => {
    let text = print_cond(inner)
    if cond_precedence(inner) < min {
      "(\{text})"
    } else {
      text
    }
  }
  match c {
    Cmp(path, op, v) => "\{print_path(path)} \{op.symbol()} \{v.stringify()}"
    And(a, b) => "\{sub(a, 1)} and \{sub(b, 2)}"
    Or(a, b) => "\{sub(a, 0)} or \{sub(b, 1)}"
    Not(a) => "not \{sub(a, 2)}"
  }
}

///|
pub fn print_command(cmd : Command) -> String {
  let names = (xs : Array[String]) => xs.map(print_name).join(" ")
  let reversed = (r : Bool) => if r { " --reverse" } else { "" }
  let count = (n : Int?) => n.map(n => " \{n}").unwrap_or("")
  match cmd {
    SortBy(cols, reverse~) => "sort-by \{names(cols)}\{reversed(reverse)}"
    Sort(reverse~) => "sort\{reversed(reverse)}"
    Where(c) => "where \{print_cond(c)}"
    Select(cols) => "select \{names(cols)}"
    SelectRows(rows) => "select \{rows.map(r => r.to_string()).join(" ")}"
    Reject(cols) => "reject \{names(cols)}"
    Get(path) => "get \{print_path(path)}"
    First(n) => "first\{count(n)}"
    Last(n) => "last\{count(n)}"
    Skip(n) => "skip \{n}"
    From(f) => "from \{f.name()}"
    To(f) => "to \{f.name()}"
    Math(op) => "math \{op.name()}"
    Find(s) => "find \{quote_string(s)}"
    Parse(pattern) => "parse \{quote_string(pattern)}"
    _ => name_of(bare_commands, cmd)
  }
}

///|
pub fn print(p : Array[Command]) -> String {
  p.map(print_command).join(" | ")
}
