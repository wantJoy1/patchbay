///|
fn steps(src : String, actions : Array[@view.GuiAction]) -> Array[String] raise {
  let mut p = @view.parse(src)
  actions.map(a => {
    p = @view.apply(p, a)
    @view.print(p)
  })
}

///|
test "a header click cycles the sort that decides the order" {
  assert_eq(
    steps("", [SortColumn("age"), SortColumn("age"), SortColumn("age")]),
    ["sort-by age", "sort-by age --reverse", ""],
  )
  assert_eq(steps("sort-by age | where age >= 30", [SortColumn("name")]), [
    "sort-by name | where age >= 30",
  ])
  assert_eq(steps("sort-by age | first 3", [SortColumn("name")]), [
    "sort-by age | first 3 | sort-by name",
  ])
  assert_eq(steps("sort-by age | select 0 1", [SortColumn("age")]), [
    "sort-by age | select 0 1 | sort-by age",
  ])
}

///|
test "the sort state is that of the sort that decides the order" {
  let state = (src : String) => @view.sort_state(@view.parse(src))
  assert_eq(state("sort-by size -r"), Some(("size", true)))
  assert_eq(
    state("sort-by size | where size > 1 | reject type"),
    Some(("size", false)),
  )
  assert_eq(state("sort-by size | first 3"), None)
}

///|
test "a filter on the same path and operator replaces the last one" {
  assert_eq(
    steps("", [
      Filter([Key("age")], Ge, 30),
      Filter([Key("age")], Ge, 40),
      Filter([Key("age")], Le, 50),
      Filter([Key("address"), Key("city")], Eq, "Tokyo"),
    ]),
    [
      "where age >= 30", "where age >= 40", "where age >= 40 | where age <= 50",
      "where age >= 40 | where age <= 50 | where address.city == \"Tokyo\"",
    ],
  )
}

///|
test "hiding and keeping columns edit the last reject or select" {
  assert_eq(
    steps("", [
      HideColumn("tags"),
      HideColumn("address"),
      KeepColumns(["name", "age"]),
      KeepColumns(["name", "age", "role"]),
      HideColumn("age"),
      HideColumn("name"),
      HideColumn("role"),
    ]),
    [
      "reject tags", "reject tags address", "reject tags address | select name age",
      "reject tags address | select name age role", "reject tags address | select name role",
      "reject tags address | select role", "reject tags address",
    ],
  )
}

///|
test "keeping rows composes the indices of the last select" {
  assert_eq(steps("", [KeepRows([4, 1, 6]), KeepRows([2, 0])]), [
    "select 1 4 6", "select 1 6",
  ])
}

///|
test "drilling adds a get instead of extending the last one" {
  assert_eq(steps("get tags", [Drill([Idx(0)])]), ["get tags | get 0"])
  assert_eq(
    steps("", [Drill([Key("owners")]), Drill([Idx(1), Key("email")])]),
    ["get owners", "get owners | get 1.email"],
  )
}

///|
test "stages can be appended and removed" {
  assert_eq(
    steps("", [
      Append(From(Json)),
      SortColumn("id"),
      RemoveStage(0),
      RemoveStage(5),
    ]),
    ["from json", "from json | sort-by id", "sort-by id", "sort-by id"],
  )
}
