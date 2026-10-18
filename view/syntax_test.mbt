///|
fn canonical(sources : Array[String]) -> Array[String] raise {
  let printed = []
  for src in sources {
    let p = @view.parse(src)
    let text = @view.print(p)
    assert_eq(@view.parse(text), p)
    printed.push(text)
  }
  printed
}

///|
test "a pipeline prints in one canonical form that parses back to it" {
  assert_eq(
    canonical([
      "  sort-by age|where age>=30|length  ", "sort-by --reverse name age", "sort -r",
      "first | last 2 | skip 1", "from json | to md", "math avg", "find tea", "parse '{date} {msg}'",
      "select 0 2 5",
    ]),
    [
      "sort-by age | where age >= 30 | length", "sort-by name age --reverse", "sort --reverse",
      "first | last 2 | skip 1", "from json | to md", "math avg", "find \"tea\"",
      "parse \"{date} {msg}\"", "select 0 2 5",
    ],
  )
}

///|
test "conditions keep only the parentheses that precedence needs" {
  assert_eq(
    canonical([
      "where a == 1 or b == 2 and not c == 3", "where (a == 1 or b == 2) and c =~ \"x\"",
      "where not (a < 1 and b > 2)",
    ]),
    [
      "where a == 1 or b == 2 and not c == 3", "where (a == 1 or b == 2) and c =~ \"x\"",
      "where not (a < 1 and b > 2)",
    ],
  )
}

///|
test "values print as JSON and bare words are strings" {
  assert_eq(
    canonical([
      "where name == 'Al \"B\"'", "where role == admin", "where tags == [1 2, three, true, null, -1.5]",
      "where a == {name: Alice, \"two words\": [a]}",
    ]),
    [
      "where name == \"Al \\\"B\\\"\"", "where role == \"admin\"", "where tags == [1,2,\"three\",true,null,-1.5]",
      "where a == {\"name\":\"Alice\",\"two words\":[\"a\"]}",
    ],
  )
}

///|
test "names and paths quote only what bare words cannot hold" {
  assert_eq(
    canonical([
      "where $it > 3", "where $it.address.city > 1", "get 0.address.city", "get $it.2.8",
      "get 0.\"home address\".city", "get 0.\"2024\"", "where $it.\"a b\".\"c.d\" == 1",
      "where \"v1.2\" > 1", "select name \"zip code\" \"true\" \"42\" \"-x\" \"\"",
    ]),
    [
      "where $it > 3", "where address.city > 1", "get 0.address.city", "get $it.2.8",
      "get 0.\"home address\".city", "get 0.\"2024\"", "where $it.\"a b\".\"c.d\" == 1",
      "where \"v1.2\" > 1", "select name \"zip code\" \"true\" \"42\" \"-x\" \"\"",
    ],
  )
}

///|
test "an empty source is the empty pipeline" {
  assert_eq(@view.parse(" "), [])
}

///|
test "errors point at the offending token" {
  let error = (src : String) => {
    @view.parse(src).length().to_string() catch {
      e => e.message()
    }
  }
  assert_eq(
    [
      "frobnicate", "uniq |", "| uniq", "sort-by", "where age >=", "where age 3",
      "uniq extra", "find \"x", "sort-by a --up", "from md", "where (a == 1",
    ].map(error),
    [
      "unknown command: frobnicate (at 0)", "expected a command (at 6)", "expected a command (at 0)",
      "sort-by needs a column (at 0)", "expected a value (at 12)", "expected a comparison operator (at 10)",
      "unexpected argument to uniq (at 5)", "unterminated string (at 5)", "unknown flag: --up (at 10)",
      "cannot parse from this format (at 5)", "expected ')' (at 13)",
    ],
  )
}
