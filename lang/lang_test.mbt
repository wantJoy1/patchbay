///|
fn roundtrip(src : String) -> String raise {
  let p = @lang.parse(src)
  let printed = @lang.print(p)
  assert_eq(@lang.parse(printed), p)
  printed
}

///|
test "spacing is normalized" {
  inspect(
    roundtrip("sort-by age|where age>=30|length"),
    content="sort-by age | where age >= 30 | length",
  )
}

///|
test "printing is canonical and parses back" {
  inspect(roundtrip("  length  "), content="length")
  inspect(
    roundtrip("sort-by --reverse name age"),
    content="sort-by name age --reverse",
  )
  inspect(roundtrip("sort -r"), content="sort --reverse")
  inspect(
    roundtrip("where name == 'Al \"B\"'"),
    content="where name == \"Al \\\"B\\\"\"",
  )
  inspect(
    roundtrip("where a == 1 or b == 2 and not c == 3"),
    content="where a == 1 or b == 2 and not c == 3",
  )
  inspect(
    roundtrip("where (a == 1 or b == 2) and c =~ \"x\""),
    content="where (a == 1 or b == 2) and c =~ \"x\"",
  )
  inspect(
    roundtrip("where not (a < 1 and b > 2)"),
    content="where not (a < 1 and b > 2)",
  )
  inspect(roundtrip("where $it > 3"), content="where $it > 3")
  inspect(
    roundtrip("where $it.address.city starts-with \"T\""),
    content="where address.city starts-with \"T\"",
  )
  inspect(roundtrip("get 0.address.city"), content="get 0.address.city")
  inspect(roundtrip("get $it.2.8"), content="get $it.2.8")
  inspect(
    roundtrip("get 0.\"home address\".city"),
    content="get 0.\"home address\".city",
  )
  inspect(roundtrip("get 0.\"2024\""), content="get 0.\"2024\"")
  inspect(
    roundtrip("where $it.\"a b\".\"c.d\" == 1"),
    content="where $it.\"a b\".\"c.d\" == 1",
  )
  inspect(roundtrip("where \"v1.2\" > 1"), content="where \"v1.2\" > 1")
  inspect(roundtrip("get \"first name\""), content="get \"first name\"")
  inspect(roundtrip("select 0 2 5"), content="select 0 2 5")
  inspect(
    roundtrip("select name \"zip code\""),
    content="select name \"zip code\"",
  )
  inspect(
    roundtrip("first | last 2 | skip 1"),
    content="first | last 2 | skip 1",
  )
  inspect(roundtrip("from json | to md"), content="from json | to md")
  inspect(roundtrip("math avg"), content="math avg")
  inspect(roundtrip("find tea"), content="find \"tea\"")
  inspect(
    roundtrip("parse '{date} {level} {msg}'"),
    content="parse \"{date} {level} {msg}\"",
  )
}

///|
test "values in conditions print as JSON" {
  inspect(
    roundtrip("where tags == [1 2, three, true, null, -1.5]"),
    content="where tags == [1,2,\"three\",true,null,-1.5]",
  )
  inspect(
    roundtrip("where a == {name: Alice, \"two words\": [a]}"),
    content="where a == {\"name\":\"Alice\",\"two words\":[\"a\"]}",
  )
}

///|
test "names that need quoting" {
  inspect(@lang.print_name("age"), content="age")
  inspect(@lang.print_name("users.json"), content="users.json")
  inspect(@lang.print_name("a b"), content="\"a b\"")
  inspect(@lang.print_name("true"), content="\"true\"")
  inspect(@lang.print_name("42"), content="\"42\"")
  inspect(@lang.print_name("-x"), content="\"-x\"")
  inspect(@lang.print_name(""), content="\"\"")
}

///|
test "empty source is the empty pipeline" {
  assert_eq(@lang.parse(""), [])
  assert_eq(@lang.parse("   "), [])
}

///|
fn parse_error(src : String) -> String {
  @lang.parse(src).length().to_string() catch {
    e => e.message()
  }
}

///|
test "errors point at the offending token" {
  inspect(
    parse_error("frobnicate"),
    content="unknown command: frobnicate (at 0)",
  )
  inspect(parse_error("uniq |"), content="expected a command (at 6)")
  inspect(parse_error("| uniq"), content="expected a command (at 0)")
  inspect(parse_error("sort-by"), content="sort-by needs a column (at 0)")
  inspect(parse_error("where age >="), content="expected a value (at 12)")
  inspect(
    parse_error("where age 3"),
    content="expected a comparison operator (at 10)",
  )
  inspect(
    parse_error("uniq extra"),
    content="unexpected argument to uniq (at 5)",
  )
  inspect(parse_error("find \"x"), content="unterminated string (at 5)")
  inspect(parse_error("sort-by a --up"), content="unknown flag: --up (at 10)")
  inspect(
    parse_error("from md"),
    content="cannot parse from this format (at 5)",
  )
  inspect(parse_error("where (a == 1"), content="expected ')' (at 13)")
}
