///|
test "columns are the union of keys in first-appearance order" {
  assert_eq(
    @table.columns([{ "a": 1, "b": 2 }, { "c": 3, "a": 4 }]),
    Some(["a", "b", "c"]),
  )
  assert_eq(@table.columns([1]), None)
  assert_eq(@table.columns([]), None)
}

///|
test "compare orders by type, then by value, and text lexicographically" {
  let sorted : Array[Json] = ["b", 2, null, "a", -1, true, "aa"]
  sorted.sort_by(@table.compare)
  json_inspect(sorted, content=[null, true, -1, 2, "a", "aa", "b"])
}

///|
test "csv infers scalars and unquotes fields" {
  json_inspect(
    @table.parse_delimited(
      (
        #|name,age,note
        #|Alice,30,"likes ""tea"", coffee"
        #|Bob,,plain
        #|
      ),
      ',',
    ),
    content=[
      { "name": "Alice", "age": 30, "note": "likes \"tea\", coffee" },
      { "name": "Bob", "age": null, "note": "plain" },
    ],
  )
}

///|
let users : Json = [
  { "name": "Alice", "age": 30, "tags": ["a"] },
  { "name": "ボブ|B", "age": 25.5, "tags": [] },
]

///|
test "markdown escapes pipes and writes nested values as json" {
  inspect(
    @table.to_markdown(users),
    content=(
      #|| name | age | tags |
      #|| --- | --- | --- |
      #|| Alice | 30 | ["a"] |
      #|| ボブ\|B | 25.5 | [] |
      #|
    ),
  )
}

///|
test "tsv quotes less than csv" {
  inspect(
    @table.to_delimited(users, '\t'),
    content=(
      #|name	age	tags
      #|Alice	30	["a"]
      #|ボブ|B	25.5	[]
      #|
    ),
  )
  inspect(
    @table.to_delimited(users, ','),
    content=(
      #|name,age,tags
      #|Alice,30,"[""a""]"
      #|ボブ|B,25.5,[]
      #|
    ),
  )
}

///|
test "grid of a list, a record and a scalar" {
  assert_eq(@table.grid([1, "x"]), Some((["value"], [["1"], ["x"]])))
  assert_eq(
    @table.grid({ "k": false }),
    Some((["field", "value"], [["k", "false"]])),
  )
  assert_eq(@table.grid(1), None)
}

///|
test "summary of nested values" {
  assert_eq(@table.summary([null]), "[1 item]")
  assert_eq(
    @table.summary({ "a": 1, "b": 2, "c": 3, "d": 4, "e": 5 }),
    "{a, b, c, d, …}",
  )
}

///|
test "infer reads numbers, booleans and empty fields" {
  json_inspect(["", "true", "-2.5", "1e3", "12a", "v1.2"].map(@table.infer), content=[
    null, true, -2.5, 1000, "12a", "v1.2",
  ])
}
