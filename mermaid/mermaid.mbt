///|
priv suberror Unsupported

///|
priv enum Shape {
  Rect
  Round
  Stadium
  Circle
  Diamond
  Subroutine
}

///|
priv enum Stroke {
  Solid
  Dotted
  Thick
}

///|
priv struct Edge {
  from : String
  to : String
  label : String
  stroke : Stroke
  arrow : Bool
}

///|
priv struct Flowchart {
  vertical : Bool
  reversed : Bool
  mut rest : StringView
  nodes : Map[String, (String, Shape)?]
  edges : Array[Edge]
}

///|
pub fn to_svg(src : String) -> String? {
  let chart = parse(src) catch { _ => return None }
  Some(chart.render())
}

///|
fn parse(src : String) -> Flowchart raise Unsupported {
  let stmts = src
    .split("\n")
    .filter(l => !l.trim_start().has_prefix("%%"))
    .flat_map(l => l.split(";"))
    .map(s => s.trim())
    .filter(s => s != "")
    .to_array()
  guard stmts is [header, .. body] else { raise Unsupported }
  let (vertical, reversed) = match
    header.split(" ").filter(w => w != "").to_array() {
    ["flowchart" | "graph"] | ["flowchart" | "graph", "TD" | "TB"] =>
      (true, false)
    ["flowchart" | "graph", "BT"] => (true, true)
    ["flowchart" | "graph", "LR"] => (false, false)
    ["flowchart" | "graph", "RL"] => (false, true)
    _ => raise Unsupported
  }
  let chart = { vertical, reversed, rest: "", nodes: {}, edges: [], }
  let ignored = [
    "classDef", "class ", "style ", "linkStyle", "click ", "subgraph", "direction",
  ]
  for s in body {
    if s == "end" || ignored.any(p => s.has_prefix(p)) {
      continue
    }
    chart.rest = s
    chart.statement()
  }
  chart
}

///|
fn Flowchart::take(self : Flowchart, pred : (Char) -> Bool) -> String {
  self.rest = self.rest.trim_start()
  let n = self.rest
    .iter()
    .take_while(pred)
    .fold(init=0, (n, c) => n + c.utf16_len())
  let taken = self.rest[:n].to_owned()
  self.rest = self.rest[n:]
  taken
}

///|
fn Flowchart::eat(self : Flowchart, token : String) -> Bool {
  self.rest = self.rest.trim_start()
  guard self.rest.has_prefix(token) else { return false }
  self.rest = self.rest[token.length():]
  true
}

///|
fn Flowchart::before(
  self : Flowchart,
  token : String,
) -> String raise Unsupported {
  guard self.rest.find(token) is Some(i) else { raise Unsupported }
  let text = self.rest[:i].trim().to_owned()
  self.rest = self.rest[i:]
  text
}

///|
fn Flowchart::until(
  self : Flowchart,
  token : String,
) -> String raise Unsupported {
  let text = self.before(token)
  self.rest = self.rest[token.length():]
  text
}

///|
fn Flowchart::statement(self : Flowchart) -> Unit raise Unsupported {
  let mut from = self.node()
  while self.link() is Some((stroke, arrow, label)) {
    let to = self.node()
    self.edges.push({ from, to, label, stroke, arrow, })
    from = to
  }
  guard self.rest.trim() is "" else { raise Unsupported }
}

///|
fn Flowchart::node(self : Flowchart) -> String raise Unsupported {
  let id = self.take(c => {
    c.is_ascii_alphabetic() || c.is_ascii_digit() || c == '_' || !c.is_ascii()
  })
  guard id != "" else { raise Unsupported }
  let shapes = [
    ("([", "])", Stadium),
    ("((", "))", Circle),
    ("[[", "]]", Subroutine),
    ("[", "]", Rect),
    ("(", ")", Round),
    ("{", "}", Diamond),
  ]
  for (open, close, shape) in shapes {
    guard self.eat(open) else { continue }
    let label = if self.eat("\"") {
      let quoted = self.until("\"")
      guard self.eat(close) else { raise Unsupported }
      quoted
    } else {
      self.until(close)
    }
    if !(self.nodes.get(id) is Some(Some(_))) {
      self.nodes[id] = Some((label, shape))
    }
    return id
  }
  if !self.nodes.contains(id) {
    self.nodes[id] = None
  }
  id
}

///|
fn Flowchart::link(
  self : Flowchart,
) -> (Stroke, Bool, String)? raise Unsupported {
  let link_char = c => c is ('-' | '.' | '=' | '>')
  let run = self.take(link_char)
  let (label, close) = match run {
    "" => return None
    "--" | "==" => (self.before(run), self.take(link_char))
    "-." => (self.before(".-"), self.take(link_char))
    _ if run.length() >= 3 =>
      (if self.eat("|") { self.until("|") } else { "" }, run)
    _ => raise Unsupported
  }
  let stroke = if run.contains("=") {
    Thick
  } else if run.contains(".") {
    Dotted
  } else {
    Solid
  }
  Some((stroke, close.has_suffix(">"), label))
}

///|
fn text_width(s : String) -> Double {
  s
  .iter()
  .fold(init=0.0, (w, c) => w + (if c.to_int() >= 0x2E80 { 13.0 } else { 7.5 }))
}

///|
fn num(x : Double) -> String {
  ((x * 10.0).round() / 10.0).to_string()
}

///|
fn rect(
  l : Double,
  t : Double,
  w : Double,
  h : Double,
  attrs : String,
) -> String {
  "<rect x=\"\{num(l)}\" y=\"\{num(t)}\" width=\"\{num(w)}\" height=\"\{num(h)}\"\{attrs}/>"
}

///|
fn Flowchart::render(self : Flowchart) -> String {
  let { vertical, reversed, .. } = self
  let ids = self.nodes.keys().to_array()
  let nodes = ids.map(id => self.nodes[id].unwrap_or((id, Rect)))
  let index = Map::from_iter(ids.iter().mapi((i, id) => (id, i)))
  let pairs = self.edges.map(e => (index[e.from], index[e.to]))
  let n = ids.length()
  let dag = []
  let visited = Array::make(n, false)
  let active = Array::make(n, false)
  fn visit(u : Int32) -> Unit {
    visited[u] = true
    active[u] = true
    for p in pairs {
      guard p.0 == u else { continue }
      if !active[p.1] {
        dag.push(p)
      }
      if !visited[p.1] {
        visit(p.1)
      }
    }
    active[u] = false
  }

  for u in 0..<n {
    if !visited[u] {
      visit(u)
    }
  }
  let layer = Array::make(n, 0)
  for _ in 0..<n {
    for p in dag {
      layer[p.1] = layer[p.1].max(layer[p.0] + 1)
    }
  }
  let rows : Array[Array[Int32]] = Array::makei(
    layer.fold(init=0, Int32::max) + 1,
    _ => [],
  )
  for v in 0..<n {
    rows[layer[v]].push(v)
  }
  let pos = Array::makei(n, v => v)
  fn reorder(row : Array[Int32], links : Array[(Int32, Int32)]) {
    row.sort_by_key(v => {
      let near = links.filter_map(l => {
        if l.1 == v {
          Some(pos[l.0].to_double())
        } else {
          None
        }
      })
      let centre = if near.is_empty() {
        pos[v].to_double()
      } else {
        near.fold(init=0.0, (a, b) => a + b) / near.length().to_double()
      }
      (centre, pos[v])
    })
    row.eachi((i, v) => pos[v] = i)
  }

  rows.each(row => reorder(row, dag))
  let up = dag.map(p => (p.1, p.0))
  rows.rev_iter().each(row => reorder(row, up))
  let size = nodes.map(node => {
    let t = text_width(node.0)
    match node.1 {
      Diamond => (t + 48.0, t + 48.0)
      Circle => {
        let d = (t + 24.0).max(36.0)
        (d, d)
      }
      Subroutine => (t + 40.0, 36.0)
      _ => (t + 24.0, 36.0)
    }
  })
  let main = size.map(s => if vertical { s.1 } else { s.0 })
  let cross = size.map(s => if vertical { s.0 } else { s.1 })
  let gap = if vertical {
    48.0
  } else {
    self.edges.fold(init=48.0, (g, e) => g.max(text_width(e.label) + 32.0))
  }
  let thick = rows.map(r => r.fold(init=0.0, (t, v) => t.max(main[v])))
  let span = rows.map(r => r.fold(init=-20.0, (s, v) => s + cross[v] + 20.0))
  let width = span.fold(init=0.0, Double::max)
  let length = thick.fold(init=-gap, (s, t) => s + t + gap)
  let centre = Array::make(n, (0.0, 0.0))
  let mut offset = 0.0
  for l, row in rows {
    let middle = offset + thick[l] / 2.0
    let along = if reversed { length - middle } else { middle }
    let mut across = (width - span[l]) / 2.0
    for v in row {
      let c = across + cross[v] / 2.0
      centre[v] = if vertical { (c, along) } else { (along, c) }
      across += cross[v] + 20.0
    }
    offset += thick[l] + gap
  }
  let lines = StringBuilder()
  let shapes = StringBuilder()
  let texts = StringBuilder()
  for v, node in nodes {
    let (label, shape) = node
    let (x, y) = centre[v]
    let (w, h) = size[v]
    let (l, t) = (x - w / 2.0, y - h / 2.0)
    shapes.write_string(
      match shape {
        Rect => rect(l, t, w, h, "")
        Round => rect(l, t, w, h, " rx=\"8\"")
        Stadium => rect(l, t, w, h, " rx=\"\{num(h / 2.0)}\"")
        Subroutine =>
          rect(l, t, w, h, "") +
          "<path d=\"M\{num(l + 8.0)} \{num(t)}v\{num(h)}M\{num(l + w - 8.0)} \{num(t)}v\{num(h)}\"/>"
        Circle =>
          "<circle cx=\"\{num(x)}\" cy=\"\{num(y)}\" r=\"\{num(w / 2.0)}\"/>"
        Diamond =>
          "<polygon points=\"\{num(x)},\{num(t)} \{num(l + w)},\{num(y)} \{num(x)},\{num(t + h)} \{num(l)},\{num(y)}\"/>"
      },
    )
    texts.write_string(
      "<text x=\"\{num(x)}\" y=\"\{num(y)}\">\{@html.escape(label)}</text>",
    )
  }
  fn clip(v : Int32, toward : Int32) -> (Double, Double) {
    let (x, y) = centre[v]
    let (dx, dy) = (centre[toward].0 - x, centre[toward].1 - y)
    let s = (size[v].0 / 2.0 / dx.abs()).min(size[v].1 / 2.0 / dy.abs())
    (x + dx * s, y + dy * s)
  }

  for k, e in self.edges {
    let (a, b) = pairs[k]
    if a == b {
      continue
    }
    // Why not draw every edge on the centre line: an edge and its reverse
    // would cover each other, labels included.
    let (ox, oy) = if pairs.contains((b, a)) {
      let (dx, dy) = (centre[b].0 - centre[a].0, centre[b].1 - centre[a].1)
      let len = (dx * dx + dy * dy).sqrt()
      (-dy / len * 11.0, dx / len * 11.0)
    } else {
      (0.0, 0.0)
    }
    let (x1, y1) = clip(a, b)
    let (x2, y2) = clip(b, a)
    let (x1, y1, x2, y2) = (x1 + ox, y1 + oy, x2 + ox, y2 + oy)
    let style = match e.stroke {
      Solid => ""
      Dotted => " stroke-dasharray=\"5 4\""
      Thick => " stroke-width=\"3\""
    }
    let head = if e.arrow { " marker-end=\"url(#patchbay-arrow)\"" } else { "" }
    lines.write_string(
      "<line x1=\"\{num(x1)}\" y1=\"\{num(y1)}\" x2=\"\{num(x2)}\" y2=\"\{num(y2)}\"\{style}\{head}/>",
    )
    if e.label != "" {
      let (x, y) = ((x1 + x2) / 2.0, (y1 + y2) / 2.0)
      let w = text_width(e.label) + 8.0
      shapes.write_string(
        rect(x - w / 2.0, y - 9.0, w, 18.0, " stroke=\"none\""),
      )
      texts.write_string(
        "<text x=\"\{num(x)}\" y=\"\{num(y)}\">\{@html.escape(e.label)}</text>",
      )
    }
  }
  let (w, h) = if vertical { (width, length) } else { (length, width) }
  let (w, h) = (num(w + 16.0), num(h + 16.0))
  // Why not a `fill` attribute: not every engine accepts var() in
  // presentation attributes.
  (
    $|<svg xmlns="http://www.w3.org/2000/svg" width="\{w}" height="\{h}" viewBox="-8 -8 \{w} \{h}" font-size="13" stroke-width="1.5">
    $|<defs><marker id="patchbay-arrow" viewBox="0 0 10 10" refX="10" refY="5" markerWidth="8" markerHeight="8" markerUnits="userSpaceOnUse" orient="auto"><path d="M0 0L10 5L0 10z" fill="currentColor"/></marker></defs>
    $|<g fill="none" stroke="currentColor">\{lines}</g>
    $|<g stroke="currentColor" style="fill: var(--panel, #fff)">\{shapes}</g>
    $|<g fill="currentColor" text-anchor="middle" dominant-baseline="central">\{texts}</g>
    $|</svg>
  )
}
