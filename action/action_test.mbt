///|
fn steps(src : String, actions : Array[@action.GuiAction]) -> String raise {
  let mut p = @lang.parse(src)
  let out : Array[String] = []
  for a in actions {
    p = @action.apply(p, a)
    out.push(@lang.print(p))
  }
  out.join("\n")
}

///|
test "a sort then a filter append stages" {
  inspect(
    steps("", [SortColumn("age"), Filter([Key("age")], Ge, 30)]),
    content=(
      #|sort-by age
      #|sort-by age | where age >= 30
    ),
  )
}

///|
test "clicking a header cycles the sort" {
  inspect(
    steps("", [SortColumn("age"), SortColumn("age"), SortColumn("age")]),
    content=(
      #|sort-by age
      #|sort-by age --reverse
      #|
    ),
  )
  inspect(
    steps("", [SortColumn("name"), SortColumn("size")]),
    content=(
      #|sort-by name
      #|sort-by size
    ),
  )
}

///|
test "the sort state is read back from the expression" {
  assert_eq(
    @action.sort_state(@lang.parse("sort-by size -r")),
    Some(("size", true)),
  )
  assert_eq(@action.sort_state(@lang.parse("sort-by size | first 3")), None)
  assert_eq(
    @action.sort_state(
      @lang.parse("sort-by size | where size > 1 | reject type"),
    ),
    Some(("size", false)),
  )
}

///|
test "a header click edits the sort that decides the order" {
  inspect(
    steps("sort-by age | where age >= 30", [
      SortColumn("age"),
      SortColumn("name"),
      SortColumn("name"),
      SortColumn("name"),
    ]),
    content=(
      #|sort-by age --reverse | where age >= 30
      #|sort-by name | where age >= 30
      #|sort-by name --reverse | where age >= 30
      #|where age >= 30
    ),
  )
  inspect(
    steps("sort-by age | first 3", [SortColumn("name")]),
    content="sort-by age | first 3 | sort-by name",
  )
}

///|
test "refining a filter replaces it; a new filter is appended" {
  inspect(
    steps("", [
      Filter([Key("age")], Ge, 30),
      Filter([Key("age")], Ge, 40),
      Filter([Key("age")], Le, 50),
      Filter([Key("address"), Key("city")], Eq, "Tokyo"),
    ]),
    content=(
      #|where age >= 30
      #|where age >= 40
      #|where age >= 40 | where age <= 50
      #|where age >= 40 | where age <= 50 | where address.city == "Tokyo"
    ),
  )
}

///|
test "hiding and keeping columns" {
  inspect(
    steps("", [
      HideColumn("tags"),
      HideColumn("address"),
      KeepColumns(["name", "age"]),
      KeepColumns(["name", "age", "role"]),
      HideColumn("age"),
      HideColumn("name"),
      HideColumn("role"),
    ]),
    content=(
      #|reject tags
      #|reject tags address
      #|reject tags address | select name age
      #|reject tags address | select name age role
      #|reject tags address | select name role
      #|reject tags address | select role
      #|reject tags address
    ),
  )
}

///|
test "keeping rows composes indices" {
  inspect(
    steps("", [KeepRows([4, 1, 6]), KeepRows([2, 0])]),
    content=(
      #|select 1 4 6
      #|select 1 6
    ),
  )
}

///|
test "drilling into nested values adds a get" {
  inspect(
    steps("", [Drill([Key("owners")]), Drill([Idx(1), Key("email")])]),
    content=(
      #|get owners
      #|get owners | get 1.email
    ),
  )
}

///|
test "appending and removing stages" {
  inspect(
    steps("", [Append(From(Json)), SortColumn("id"), RemoveStage(0)]),
    content=(
      #|from json
      #|from json | sort-by id
      #|sort-by id
    ),
  )
  inspect(steps("", [RemoveStage(5)]), content="")
}

///|
test "rewritten expressions give the view asked for" {
  let p = @action.apply(
    @action.apply(@lang.parse(""), SortColumn("age")),
    Filter([Key("age")], Ge, 30),
  )
  json_inspect(@eval.run([..p, Get([Key("name")])], @fixture.users), content=[
    "Carol", "Alice", "Eve", "佐藤 花子", "Frank",
  ])
}

///|
test "a header click after keeping rows sorts the kept rows" {
  inspect(
    steps("sort-by age | select 0 1", [SortColumn("age")]),
    content="sort-by age | select 0 1 | sort-by age",
  )
}

///|
test "drilling after getting a column indexes the column" {
  let p = @action.apply(@lang.parse("get tags"), Drill([Idx(0)]))
  inspect(@lang.print(p), content="get tags | get 0")
  json_inspect(@eval.run(p, @fixture.users), content=["ops", "oncall"])
}
