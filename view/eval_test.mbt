///|
using @fixture {users, config, orders_csv, server_log}

///|
fn results(input : Json, sources : Array[String]) -> Array[String] raise {
  let out = []
  for src in sources {
    let p = @view.parse(src)
    out.push(@view.run(p, input).stringify() catch { e => e.message() })
  }
  out
}

///|
let orders : Json = Json(orders_csv)

///|
let log : Json = Json(server_log)

///|
test "sort-by is stable and --reverse inverts it" {
  assert_eq(
    results(users, [
      "sort-by role | get id", "sort-by role --reverse | get id", "sort-by age | where age >= 30 | get id",
    ]),
    ["[1,8,4,2,3,5,7,6]", "[6,7,2,3,5,4,1,8]", "[4,1,6,3,8]"],
  )
  assert_eq(results([3, 1, 2], ["sort", "sort -r"]), ["[1,2,3]", "[3,2,1]"])
}

///|
test "where combines conditions, compares text case-sensitively and reads a missing column as null" {
  assert_eq(
    results(users, [
      "where address.city == Tokyo | get id", "where tags =~ oncall | get id", "where name =~ A | get id",
      "where name =~ a and not active == true | get id", "where role == admin or age < 25 | get id",
      "where name starts-with 佐 | get id", "where nope > 1", "where role != dev and age <= 30 | get id",
      "where name !~ e and name ends-with k | get id",
    ]),
    ["[1,3,6]", "[1,6]", "[1]", "[5,8]", "[1,5,8]", "[3]", "[]", "[4,7]", "[8]"],
  )
  assert_eq(results([1, 5, 10], ["where $it > 3"]), ["[5,10]"])
}

///|
test "select, reject, get, first, last and skip pick parts of a value" {
  assert_eq(
    results(users, [
      "first 2 | select name age", "select 0 2 | get name", "get 2.address.city",
      "first | get name", "last | get name", "skip 6 | get id", "last 2 | get id",
    ]),
    [
      "[{\"name\":\"Alice\",\"age\":34},{\"name\":\"Bob\",\"age\":27}]", "[\"Alice\",\"佐藤 花子\"]",
      "\"Tokyo\"", "\"Alice\"", "\"Frank\"", "[7,8]", "[7,8]",
    ],
  )
  assert_eq(
    results(config, ["reject owners features server", "get owners.name"]),
    ["{\"name\":\"patchbay\",\"version\":\"0.1.0\"}", "[\"Alice\",\"Eve\"]"],
  )
}

///|
test "list commands reverse, deduplicate, count and name columns" {
  assert_eq(
    results(config, [
      "length", "columns", "get owners | reverse | get name", "get features.export | uniq | length",
    ]),
    [
      "5", "[\"name\",\"version\",\"server\",\"features\",\"owners\"]", "[\"Eve\",\"Alice\"]",
      "3",
    ],
  )
}

///|
test "csv fields are typed for math, uniq and columns" {
  assert_eq(
    results(orders, [
      "from csv | get qty | math sum", "from csv | get price | math max", "from csv | get price | math min",
      "from csv | where item == \"Desk, standing\" | get qty", "from csv | get item | uniq | length",
      "from csv | columns",
    ]),
    [
      "14", "59800", "1200", "[1]", "7", "[\"order_id\",\"user_id\",\"item\",\"qty\",\"price\",\"date\"]",
    ],
  )
  assert_eq(results(users, ["get age | math avg"]), ["34.25"])
}

///|
test "text converts to and from data" {
  assert_eq(
    results(users, [
      "first 2 | select id name | to md", "to json | from json | length",
    ]),
    ["\"| id | name |\\n| --- | --- |\\n| 1 | Alice |\\n| 2 | Bob |\\n\"", "8"],
  )
}

///|
test "lines, parse and find split text into lines" {
  assert_eq(
    results(log, [
      "lines | length", "parse \"{line}\" | length", "parse \"{date} {time} {level} {msg}\" | where level == ERROR | get msg",
      "find \"Disk\"",
    ]),
    [
      "7", "7", "[\"failed to send mail: timeout\",\"disk usage above 90%\"]", "[\"2026-10-16 10:15:27 ERROR disk usage above 90%\"]",
    ],
  )
  assert_eq(results(["a=1", "junk", "b=2"], ["parse \"{k}={v}\""]), [
    "[{\"k\":\"a\",\"v\":1},{\"k\":\"b\",\"v\":2}]",
  ])
}

///|
test "errors name the failing stage" {
  assert_eq(results(users, ["lines", "get 99", "math sum"]), [
    "stage 1: lines expects text, got list", "stage 1: cannot find 99", "stage 1: math sum expects numbers, got record",
  ])
  assert_eq(results([], ["first", "math max"]), [
    "stage 1: first on an empty list", "stage 1: math max on an empty list",
  ])
  assert_true(
    results(log, ["from json"])[0].has_prefix("stage 1: invalid JSON"),
  )
}
