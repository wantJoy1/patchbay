///|
pub suberror ParseError {
  ParseError(pos~ : Int, String)
} derive(Debug)

///|
pub fn ParseError::message(self : ParseError) -> String {
  let ParseError(pos~, msg) = self
  "\{msg} (at \{pos})"
}

///|
priv enum Tok {
  Punct(Char)
  Op(String)
  Word(String)
  Str(String)
  Num(Double)
  Flag(String)
  Var(String)
  QPath(Array[(String, Bool)])
  Eof
}

///|
fn number_of_word(w : StringView) -> Double? {
  lexmatch w with longest {
    re"^-?[0-9]+(\.[0-9]+)?([eE](\+|-)?[0-9]+)?$" =>
      Some(@string.parse_double(w)) catch {
        _ => None
      }
    _ => None
  }
}

///|
fn is_delimiter(c : Char) -> Bool {
  " \t\r\n|[]{}(),:\"'=!<>".contains_char(c)
}

///|
fn tokenize(src : String) -> Array[(Tok, Int)] raise ParseError {
  let tokens = []
  let mut rest = src[:]
  while rest is [c, ..] {
    let pos = src.length() - rest.length()
    let push = tok => tokens.push((tok, pos))
    rest = lexmatch rest with longest {
      (re"^[ \t\r\n]+", after=r) => r
      (re"^(==|=~|!=|!~|<=|>=|<|>)" as op, after=r) => {
        push(Op(op.to_owned()))
        r
      }
      (re"^[|\[\]{}(),:]" as p, after=r) => {
        push(Punct(p))
        r
      }
      (re"^'[^']*'" as q, after=r) => {
        push(Str(q[1:q.length() - 1].to_owned()))
        r
      }
      (re"^\"([^\"\\]|\\.)*\"", after=_) => {
        let (s, r) = quoted(rest, pos)
        push(Str(s))
        r
      }
      (re"^[^ \t\r\n|\[\]{}(),:\"'=!<>]+" as w, after=r) =>
        if w.has_suffix(".") && r is ['"', ..] {
          let (parts, r) = quoted_path(w, r, src)
          push(QPath(parts))
          r
        } else {
          push(word_token(w))
          r
        }
      _ =>
        raise ParseError(
          pos~,
          if c is ('"' | '\'') {
            "unterminated string"
          } else {
            "unexpected '\{c}'"
          },
        )
    }
  }
  tokens.push((Eof, src.length()))
  tokens
}

///|
fn word_token(w : StringView) -> Tok {
  match w {
    ['$', .. v] => Var(v.to_owned())
    _ if number_of_word(w) is Some(x) => Num(x)
    ['-', _, ..] => Flag(w.to_owned())
    _ => Word(w.to_owned())
  }
}

///|
/// Why not unescape by hand: the printer writes strings as JSON, so JSON
/// decodes exactly what it writes.
fn quoted(s : StringView, pos : Int) -> (String, StringView) raise ParseError {
  lexmatch s with longest {
    (re"^\"([^\"\\]|\\.)*\"" as q, after=r) => {
      // Why not hand raw line breaks to JSON: it rejects them, but strings
      // here may span lines.
      let escaped = q
        .to_owned()
        .replace_all(old="\n", new="\\n")
        .replace_all(old="\r", new="\\r")
        .replace_all(old="\t", new="\\t")
      let json = @json.parse(escaped) catch {
        _ => raise ParseError(pos~, "invalid escape in string")
      }
      guard json is String(text) else {
        raise ParseError(pos~, "invalid string")
      }
      (text, r)
    }
    _ => raise ParseError(pos~, "unterminated string")
  }
}

///|
fn quoted_path(
  head : StringView,
  rest : StringView,
  src : String,
) -> (Array[(String, Bool)], StringView) raise ParseError {
  let parts = []
  let bare = (fragment : StringView) => {
    for piece in fragment.split(".") {
      if piece != "" {
        parts.push((piece.to_owned(), false))
      }
    }
  }
  bare(head)
  let mut rest = rest
  while rest is ['"', ..] {
    let pos = src.length() - rest.length()
    let (key, r) = quoted(rest, pos)
    parts.push((key, true))
    let mut tail = r
    while tail is [c, .. t] && !is_delimiter(c) {
      tail = t
    }
    let fragment = r[:r.length() - tail.length()]
    if fragment != "" && !fragment.has_prefix(".") {
      raise ParseError(pos~, "expected '.' after a quoted key")
    }
    bare(fragment)
    rest = tail
    if !fragment.has_suffix(".") {
      break
    }
  }
  (parts, rest)
}
