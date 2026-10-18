///|
fn count(svg : String, needle : String) -> Int32 {
  svg.split(needle).count() - 1
}

///|
fn position(svg : String, label : String) -> (Double, Double) raise {
  guard svg.find(">\{label}</text>") is Some(end) &&
    svg[:end].rev_find("<text ") is Some(start) &&
    svg[start:end].split("\"").to_array() is [_, x, _, y, ..] else {
    fail("no text \{label}")
  }
  (@string.parse_double(x), @string.parse_double(y))
}

///|
test "anything but a supported flowchart is None" {
  for
    src in [
      "", "sequenceDiagram\nA->>B: hi", "flowchart XY\nA --> B", "graph TD\nA --o B",
      "graph TD\nA[open",
    ] {
    assert_eq(@mermaid.to_svg(src), None)
  }
}

///|
test "each node is drawn once with the label of its first labelled definition" {
  let svg = @mermaid.to_svg("flowchart TD\nA --> B\nA[Start] --> C\nA[Other]").unwrap()
  assert_eq(count(svg, "<text"), 3)
  assert_true(svg.contains(">Start</text>"))
  assert_true(!svg.contains("Other"))
}

///|
test "each bracket picks its shape" {
  let svg = @mermaid.to_svg(
    "graph\nA{\"Ok?\"} --> B((c)) --> C([s]) --> D[[sub]] --> E(r)",
  ).unwrap()
  assert_eq(count(svg, "<polygon"), 1)
  assert_eq(count(svg, "<circle"), 1)
  assert_eq(count(svg, "<path d=\"M"), 2)
  assert_true(svg.contains(">Ok?</text>"))
}

///|
test "direction decides where successors go" {
  let lr = @mermaid.to_svg("flowchart LR\nA --> B").unwrap()
  assert_true(position(lr, "B").0 > position(lr, "A").0)
  assert_eq(position(lr, "B").1, position(lr, "A").1)
  let bt = @mermaid.to_svg("graph BT\nA --> B").unwrap()
  assert_true(position(bt, "B").1 < position(bt, "A").1)
}

///|
test "a cycle still gets one layer per node" {
  let svg = @mermaid.to_svg("graph TD\nA --> B --> C --> A").unwrap()
  let (a, b, c) = (
    position(svg, "A").1,
    position(svg, "B").1,
    position(svg, "C").1,
  )
  assert_true(a < b && b < c)
}

///|
test "children follow their parents' order to avoid crossings" {
  let svg = @mermaid.to_svg("graph TD\nA --> D\nB --> C").unwrap()
  assert_true(position(svg, "D").0 < position(svg, "C").0)
}

///|
test "link syntax sets dash, thickness, arrowhead and label" {
  let svg = @mermaid.to_svg(
    "graph LR\nA -.-> B\nB === C\nC -- go on --> D\nD -. maybe .- E\nE ==>|yes| F",
  ).unwrap()
  assert_eq(count(svg, "stroke-dasharray"), 2)
  assert_eq(count(svg, "stroke-width=\"3\""), 2)
  assert_eq(count(svg, "marker-end"), 3)
  for label in ["go on", "maybe", "yes"] {
    assert_true(svg.contains(">\{label}</text>"))
  }
}

///|
test "comments, semicolons and styling statements are accepted" {
  let svg = @mermaid.to_svg(
    (
      #|%% a comment; still a comment
      #|graph TD; A --> B; B --> C
      #|classDef hot fill:#f00
      #|class A hot
      #|style B stroke:#0f0
      #|subgraph group
      #|  direction LR
      #|end
    ),
  ).unwrap()
  assert_eq(count(svg, "<text"), 3)
}

///|
test "text is escaped" {
  let svg = @mermaid.to_svg("graph TD\nA[a < b & c] -->|\"x\"| B").unwrap()
  assert_true(svg.contains(">a &lt; b &amp; c</text>"))
  assert_true(svg.contains(">&quot;x&quot;</text>"))
}

///|
test "wide characters make wider nodes" {
  let svg = @mermaid.to_svg("graph TD\nA[開始]").unwrap()
  assert_true(svg.contains("width=\"50\""))
}

///|
test "a tiny graph renders to this svg" {
  inspect(
    @mermaid.to_svg("flowchart LR\nA --> B[End]").unwrap(),
    content=(
      #|<svg xmlns="http://www.w3.org/2000/svg" width="142" height="52" viewBox="-8 -8 142 52" font-size="13" stroke-width="1.5">
      #|<defs><marker id="patchbay-arrow" viewBox="0 0 10 10" refX="10" refY="5" markerWidth="8" markerHeight="8" markerUnits="userSpaceOnUse" orient="auto"><path d="M0 0L10 5L0 10z" fill="currentColor"/></marker></defs>
      #|<g fill="none" stroke="currentColor"><line x1="31.5" y1="18" x2="79.5" y2="18" marker-end="url(#patchbay-arrow)"/></g>
      #|<g stroke="currentColor" style="fill: var(--surface, #fff)"><rect x="0" y="0" width="31.5" height="36"/><rect x="79.5" y="0" width="46.5" height="36"/></g>
      #|<g fill="currentColor" text-anchor="middle" dominant-baseline="central"><text x="15.8" y="18">A</text><text x="102.8" y="18">End</text></g>
      #|</svg>
    ),
  )
}

///|
test "an edge and its reverse are drawn apart" {
  let svg = @mermaid.to_svg("flowchart LR\nA -->|go| B\nB -->|back| A").unwrap()
  let heights = svg
    .split(" y1=\"")
    .drop(1)
    .map(s => s.split("\"").next().unwrap().to_owned())
    .collect()
  assert_true(heights is [a, b] && a != b)
}
