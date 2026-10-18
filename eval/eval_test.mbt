///|
using @fixture {users, config, orders_csv, server_log}

///|
fn json(src : String, input : Json) -> String raise {
  @eval.run(@lang.parse(src), input).stringify()
}

///|
fn error(src : String, input : Json) -> String raise {
  let p = @lang.parse(src)
  @eval.run(p, input).stringify() catch {
    e => e.message()
  }
}

///|
let orders : Json = Json::string(orders_csv)

///|
let log : Json = Json::string(server_log)

///|
test "sort then filter" {
  inspect(
    json("sort-by age | where age >= 30 | get name", users),
    content="[\"Carol\",\"Alice\",\"Eve\",\"佐藤 花子\",\"Frank\"]",
  )
}

///|
test "sort is stable and reversible" {
  inspect(json("sort-by role | get id", users), content="[1,8,4,2,3,5,7,6]")
  inspect(
    json("sort-by role --reverse | get id", users),
    content="[6,7,2,3,5,4,1,8]",
  )
  inspect(json("sort", [3, 1, 2]), content="[1,2,3]")
  inspect(json("sort -r", [3, 1, 2]), content="[3,2,1]")
}

///|
test "where combines conditions and treats a missing column as null" {
  inspect(
    json("where address.city == \"Tokyo\" | get id", users),
    content="[1,3,6]",
  )
  inspect(json("where tags =~ oncall | get id", users), content="[1,6]")
  inspect(
    json("where name =~ \"a\" and not active == true | get id", users),
    content="[5,8]",
  )
  inspect(
    json("where role == \"admin\" or age < 25 | get id", users),
    content="[1,5,8]",
  )
  inspect(json("where name starts-with \"佐\" | get id", users), content="[3]")
  inspect(json("where $it > 3", [1, 5, 10]), content="[5,10]")
  inspect(json("where nope > 1", users), content="[]")
}

///|
test "select, reject and get pick parts of a value" {
  inspect(
    json("first 2 | select name age", users),
    content="[{\"name\":\"Alice\",\"age\":34},{\"name\":\"Bob\",\"age\":27}]",
  )
  inspect(
    json("select 0 2 | get name", users),
    content="[\"Alice\",\"佐藤 花子\"]",
  )
  inspect(
    json("reject owners features server", config),
    content="{\"name\":\"patchbay\",\"version\":\"0.1.0\"}",
  )
  inspect(json("get 2.address.city", users), content="\"Tokyo\"")
  inspect(json("get owners.name", config), content="[\"Alice\",\"Eve\"]")
  inspect(json("first | get name", users), content="\"Alice\"")
  inspect(json("last | get name", users), content="\"Frank\"")
  inspect(json("skip 6 | get id", users), content="[7,8]")
  inspect(json("last 2 | get id", users), content="[7,8]")
}

///|
test "csv fields are typed for math, uniq and columns" {
  inspect(json("from csv | get qty | math sum", orders), content="14")
  inspect(json("from csv | get price | math max", orders), content="59800")
  inspect(json("from csv | get price | math min", orders), content="1200")
  inspect(
    json("from csv | where item == \"Desk, standing\" | get qty", orders),
    content="[1]",
  )
  inspect(json("get age | math avg", users), content="34.25")
  inspect(json("from csv | get item | uniq | length", orders), content="7")
  inspect(
    json("from csv | columns", orders),
    content="[\"order_id\",\"user_id\",\"item\",\"qty\",\"price\",\"date\"]",
  )
}

///|
test "text converts to and from data" {
  inspect(json("lines | find error | length", log), content="2")
  guard @eval.run(@lang.parse("first 2 | select id name | to md"), users)
    is String(md) else {
    fail("to md gives text")
  }
  inspect(
    md,
    content=(
      #|| id | name |
      #|| --- | --- |
      #|| 1 | Alice |
      #|| 2 | Bob |
      #|
    ),
  )
  inspect(json("from json | length", users.stringify().to_json()), content="8")
}

///|
test "errors carry the failing stage" {
  inspect(
    error("lines", users),
    content="stage 1: lines expects text, got list",
  )
  inspect(error("get 99", users), content="stage 1: cannot find 99")
  inspect(error("first", []), content="stage 1: first on an empty list")
  inspect(
    error("math sum", ["a"]),
    content="stage 1: math sum expects numbers, got string",
  )
  assert_true(error("from json", log).has_prefix("stage 1: invalid JSON"))
}

///|
test "parse turns matching lines into typed records" {
  inspect(
    json(
      "parse \"{date} {time} {level} {msg}\" | where level == ERROR | get msg", log,
    ),
    content="[\"failed to send mail: timeout\",\"disk usage above 90%\"]",
  )
  inspect(
    json("parse \"{k}={v}\"", ["a=1", "junk", "b=2"]),
    content="[{\"k\":\"a\",\"v\":1},{\"k\":\"b\",\"v\":2}]",
  )
}

///|
test "find on text keeps matching lines" {
  inspect(
    json("find \"90%\"", log),
    content="[\"2026-10-16 10:15:27 ERROR disk usage above 90%\"]",
  )
}

///|
test "parse and lines agree on the number of lines" {
  inspect(json("parse \"{line}\" | length", log), content="7")
  inspect(json("lines | length", log), content="7")
}
