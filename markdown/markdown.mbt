///|
pub(all) enum Block {
  Html(String)
  Table(Json)
  Mermaid(String)
} derive(Eq, Debug)

///|
/// Why not render tables as HTML: as data they can be sorted, filtered and
/// copied like any other output.
pub fn split(md : String) -> Array[Block] {
  let lines = md.split("\n").map(l => l.trim_end(chars="\r")).collect()
  let blocks = []
  let html = StringBuilder()
  let flush = () => {
    if !html.is_empty() {
      blocks.push(Html(html.to_string()))
      html.reset()
    }
  }
  let paragraph = []
  let end_paragraph = () => {
    if !paragraph.is_empty() {
      html.write_string("<p>\{inline(paragraph.join(" "))}</p>")
      paragraph.clear()
    }
  }
  let mut i = 0
  let take = (keep : (StringView) -> Bool) => {
    let start = i
    while i < lines.length() && keep(lines[i].trim(chars=" ")) {
      i += 1
    }
    lines[start:i].to_owned()
  }
  while i < lines.length() {
    let line = lines[i].trim(chars=" ")
    if !(line is ("" | ['#', ..] | ['`', '`', '`', ..] | ['|', ..] | ['>', ..]) ||
      list_item(line) is Some(_) ||
      line is ("---" | "***")) {
      paragraph.push(line.to_owned())
      i += 1
      continue
    }
    end_paragraph()
    match line {
      "" => i += 1
      ['`', '`', '`', .. lang] => {
        i += 1
        let body = take(l => !l.has_prefix("```"))
        i += 1
        let code = body.map(l => l.to_owned()).join("\n")
        if lang.trim(chars=" ") == "mermaid" {
          flush()
          blocks.push(Mermaid(code))
        } else {
          html.write_string("<pre><code>\{escape(code)}</code></pre>")
        }
      }
      ['|', ..] if i + 1 < lines.length() && is_separator(lines[i + 1]) => {
        let header = row_cells(line)
        i += 2
        let rows = take(l => l.has_prefix("|"))
        flush()
        blocks.push(
          Table(
            Json::array(
              rows.map(row => {
                let cells = row_cells(row)
                Json::object(
                  Map::from_array(
                    header.mapi((c, name) => {
                      (
                        name,
                        @table.infer(strip_inline(cells.get(c).unwrap_or(""))),
                      )
                    }),
                  ),
                )
              }),
            ),
          ),
        )
      }
      ['>', ..] => {
        let quoted = take(l => l.has_prefix(">")).map(l => {
          l.trim(chars=" ")[1:].trim(chars=" ").to_owned()
        })
        html.write_string(
          "<blockquote><p>\{inline(quoted.join(" "))}</p></blockquote>",
        )
      }
      "---" | "***" => {
        html.write_string("<hr>")
        i += 1
      }
      _ =>
        match heading(line) {
          Some((level, text)) => {
            html.write_string("<h\{level}>\{inline(text)}</h\{level}>")
            i += 1
          }
          None => {
            let ordered = list_item(line).unwrap().0
            let tag = if ordered { "ol" } else { "ul" }
            let items = take(l => list_item(l).map(x => x.0) == Some(ordered))
            html.write_string("<\{tag}>")
            for item in items {
              html.write_string(
                "<li>\{inline(list_item(item.trim(chars=" ")).unwrap().1)}</li>",
              )
            }
            html.write_string("</\{tag}>")
          }
        }
    }
  }
  end_paragraph()
  flush()
  blocks
}

///|
fn heading(line : StringView) -> (Int, String)? {
  lexmatch line with longest {
    (re"^#{1,6} +" as marks, after=text) =>
      Some((marks.trim_end(chars=" ").length(), text.to_owned()))
    _ => None
  }
}

///|
fn list_item(line : StringView) -> (Bool, String)? {
  lexmatch line with longest {
    (re"^(-|\*|\+) ", after=text) => Some((false, text.to_owned()))
    (re"^[0-9]+[.)] ", after=text) => Some((true, text.to_owned()))
    _ => None
  }
}

///|
fn is_separator(line : StringView) -> Bool {
  lexmatch line.trim(chars=" ") with longest {
    re"^\|?( *:?-+:? *\|)* *:?-+:? *\|?$" => true
    _ => false
  }
}

///|
fn row_cells(line : StringView) -> Array[String] {
  let cells = []
  let cell = StringBuilder()
  let mut escaped = false
  let s = line.trim(chars=" ")
  for ch in (if s is ['|', .. rest] { rest } else { s }) {
    match (escaped, ch) {
      (true, '|') => {
        cell.write_char('|')
        escaped = false
      }
      (true, _) => {
        cell.write_char('\\')
        cell.write_char(ch)
        escaped = false
      }
      (false, '\\') => escaped = true
      (false, '|') => {
        cells.push(cell.to_string().trim(chars=" ").to_owned())
        cell.reset()
      }
      (false, _) => cell.write_char(ch)
    }
  }
  let last = cell.to_string().trim(chars=" ").to_owned()
  if last != "" {
    cells.push(last)
  }
  cells
}

///|
fn strip_inline(s : String) -> String {
  lexmatch s[:] with longest {
    re"^`.*`$" => s[1:s.length() - 1].to_owned()
    re"^\*\*.*\*\*$" => s[2:s.length() - 2].to_owned()
    _ => s
  }
}

///|
fn escape(s : StringView) -> String {
  let sb = StringBuilder()
  for ch in s {
    match ch {
      '&' => sb.write_string("&amp;")
      '<' => sb.write_string("&lt;")
      '>' => sb.write_string("&gt;")
      '"' => sb.write_string("&quot;")
      _ => sb.write_char(ch)
    }
  }
  sb.to_string()
}

///|
pub fn inline(s : StringView) -> String {
  let sb = StringBuilder()
  let mut rest = s
  while rest is [c, ..] {
    rest = lexmatch rest with longest {
      (re"^`[^`]+`" as code, after=r) => {
        sb.write_string("<code>\{escape(code[1:code.length() - 1])}</code>")
        r
      }
      (re"^\*\*[^*]+\*\*" as t, after=r) => {
        sb.write_string("<strong>\{inline(t[2:t.length() - 2])}</strong>")
        r
      }
      (re"^\*[^* ][^*]*\*" as t, after=r) => {
        sb.write_string("<em>\{inline(t[1:t.length() - 1])}</em>")
        r
      }
      // Why not any URL: `javascript:` links would run in the page.
      (re"^\[[^\]]*\]\((https?:|mailto:)[^)]*\)" as link, after=r) => {
        let mid = link.find("](").unwrap()
        sb.write_string(
          "<a href=\"\{escape(link[mid + 2:link.length() - 1])}\">\{inline(link[1:mid])}</a>",
        )
        r
      }
      (re"^.", after=r) => {
        sb.write_string(escape(c.to_string()))
        r
      }
      _ => ""
    }
  }
  sb.to_string()
}
