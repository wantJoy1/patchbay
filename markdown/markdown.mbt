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
    match line {
      "" => {
        end_paragraph()
        i += 1
      }
      ['`', '`', '`', .. lang] => {
        end_paragraph()
        i += 1
        let code = take(l => !l.has_prefix("```"))
          .map(l => l.to_owned())
          .join("\n")
        i += 1
        if lang.trim(chars=" ") == "mermaid" {
          flush()
          blocks.push(Mermaid(code))
        } else {
          html.write_string("<pre><code>\{@html.escape(code)}</code></pre>")
        }
      }
      ['|', ..] if i + 1 < lines.length() && is_separator(lines[i + 1]) => {
        end_paragraph()
        let header = row_cells(line)
        i += 2
        let rows = take(l => l.has_prefix("|")).map(row => {
          let cells = row_cells(row)
          Json(
            Map::from_array(
              header.mapi((c, name) => {
                (name, @table.infer(strip_inline(cells.get(c).unwrap_or(""))))
              }),
            ),
          )
        })
        flush()
        blocks.push(Table(Json(rows)))
      }
      ['>', ..] => {
        end_paragraph()
        let quoted = take(l => l.has_prefix(">")).map(l => {
          l.trim(chars=" ")[1:].trim(chars=" ").to_owned()
        })
        html.write_string(
          "<blockquote><p>\{inline(quoted.join(" "))}</p></blockquote>",
        )
      }
      "---" | "***" => {
        end_paragraph()
        html.write_string("<hr>")
        i += 1
      }
      _ if heading(line) is Some((level, text)) => {
        end_paragraph()
        html.write_string("<h\{level}>\{inline(text)}</h\{level}>")
        i += 1
      }
      _ if list_item(line) is Some((ordered, _)) => {
        end_paragraph()
        let tag = if ordered { "ol" } else { "ul" }
        html.write_string("<\{tag}>")
        while i < lines.length() &&
              list_item(lines[i].trim(chars=" ")) is Some((o, text)) &&
              o == ordered {
          html.write_string("<li>\{inline(text)}</li>")
          i += 1
        }
        html.write_string("</\{tag}>")
      }
      _ => {
        paragraph.push(line.to_owned())
        i += 1
      }
    }
  }
  end_paragraph()
  flush()
  blocks
}

///|
fn heading(line : StringView) -> (Int32, String)? {
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
fn inline(s : StringView) -> String {
  let sb = StringBuilder()
  let mut rest = s
  while rest is [c, ..] {
    rest = lexmatch rest with longest {
      (re"^`[^`]+`" as code, after=r) => {
        sb.write_string(
          "<code>\{@html.escape(code[1:code.length() - 1].to_owned())}</code>",
        )
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
          "<a href=\"\{@html.escape(link[mid + 2:link.length() - 1].to_owned())}\">\{inline(link[1:mid])}</a>",
        )
        r
      }
      (re"^.", after=r) => {
        sb.write_string(@html.escape(c.to_string()))
        r
      }
      _ => ""
    }
  }
  sb.to_string()
}
