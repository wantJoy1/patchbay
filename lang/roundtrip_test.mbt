///|
let tricky_names : Array[String] = [
  "age", "first name", "true", "or", "42", "-x", "a\"b", "c\\d", "v1.2", "名前",
  "$x", "a|b", "", "x:y",
]

///|
let path_keys : Array[String] = ["age", "address", "city", "名前", "zip_code"]

///|
fn pick(r : @random.Rand, xs : Array[String]) -> String {
  xs[r.int(limit=xs.length())]
}

///|
fn gen_value(r : @random.Rand, depth : Int) -> Json {
  match r.int(limit=if depth > 1 { 4 } else { 6 }) {
    0 => null
    1 => Json::boolean(r.boolean())
    2 => Json::number((r.int(limit=2001) - 1000).to_double() / 4.0)
    3 => Json::string(pick(r, tricky_names))
    4 => Json::array(Array::makei(r.int(limit=3), _ => gen_value(r, depth + 1)))
    _ =>
      Json::object(
        Map::from_array(
          Array::makei(r.int(limit=3), _ => {
            (pick(r, tricky_names), gen_value(r, depth + 1))
          }),
        ),
      )
  }
}

///|
fn gen_path(r : @random.Rand) -> Array[@lang.Seg] {
  match r.int(limit=3) {
    0 => []
    1 => [Key(pick(r, tricky_names))]
    _ =>
      Array::makei(1 + r.int(limit=3), _ => {
        if r.boolean() {
          @lang.Seg::Key(
            pick(r, if r.boolean() { path_keys } else { tricky_names }),
          )
        } else {
          @lang.Seg::Idx(r.int(limit=10))
        }
      })
  }
}

///|
let ops : Array[@lang.CmpOp] = [
  Eq,
  Ne,
  Lt,
  Le,
  Gt,
  Ge,
  Contains,
  NotContains,
  StartsWith,
  EndsWith,
]

///|
fn gen_cond(r : @random.Rand, depth : Int) -> @lang.Cond {
  match r.int(limit=if depth > 2 { 1 } else { 4 }) {
    0 => Cmp(gen_path(r), ops[r.int(limit=ops.length())], gen_value(r, 2))
    1 => And(gen_cond(r, depth + 1), gen_cond(r, depth + 1))
    2 => Or(gen_cond(r, depth + 1), gen_cond(r, depth + 1))
    _ => Not(gen_cond(r, depth + 1))
  }
}

///|
fn gen_names(r : @random.Rand) -> Array[String] {
  Array::makei(1 + r.int(limit=3), _ => pick(r, tricky_names))
}

///|
fn gen_command(r : @random.Rand) -> @lang.Command {
  match r.int(limit=18) {
    0 => SortBy(gen_names(r), reverse=r.boolean())
    1 => Sort(reverse=r.boolean())
    2 => Where(gen_cond(r, 0))
    3 => Select(gen_names(r))
    4 => SelectRows(Array::makei(1 + r.int(limit=3), _ => r.int(limit=20)))
    5 => Reject(gen_names(r))
    6 => {
      let path = gen_path(r)
      Get(if path.is_empty() { [Idx(0)] } else { path })
    }
    7 => First(if r.boolean() { Some(r.int(limit=5)) } else { None })
    8 => Last(if r.boolean() { Some(r.int(limit=5)) } else { None })
    9 => Skip(r.int(limit=5))
    10 => Length
    11 => Reverse
    12 => Uniq
    13 => From([@lang.Format::Json, Csv, Tsv][r.int(limit=3)])
    14 => To([@lang.Format::Json, Csv, Tsv, Md][r.int(limit=4)])
    15 => Math([@lang.MathOp::Sum, Avg, Min, Max][r.int(limit=4)])
    16 => Find(pick(r, tricky_names))
    _ => Parse("{" + pick(r, path_keys) + "} - {rest}")
  }
}

///|
test "print then parse is the identity on random pipelines" {
  let r = @random.Rand::new()
  for _ in 0..<2000 {
    let p = Array::makei(1 + r.int(limit=4), _ => gen_command(r))
    let printed = @lang.print(p)
    let back = @lang.parse(printed) catch {
      e => fail("does not parse: \{printed}\n\{e.message()}")
    }
    if back != p {
      fail(
        "round trip changed the pipeline: \{printed}\n\{Repr(p)}\n\{Repr(back)}",
      )
    }
  }
}
