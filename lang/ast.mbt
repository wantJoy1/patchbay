///|
pub(all) enum Seg {
  Key(String)
  Idx(Int)
} derive(Eq, Debug)

///|
pub(all) enum CmpOp {
  Eq
  Ne
  Lt
  Le
  Gt
  Ge
  Contains
  NotContains
  StartsWith
  EndsWith
} derive(Eq, Debug)

///|
pub(all) enum Cond {
  Cmp(Array[Seg], CmpOp, Json)
  And(Cond, Cond)
  Or(Cond, Cond)
  Not(Cond)
} derive(Eq, Debug)

///|
pub(all) enum Format {
  Json
  Csv
  Tsv
  Md
} derive(Eq, Debug)

///|
pub(all) enum MathOp {
  Sum
  Avg
  Min
  Max
} derive(Eq, Debug)

///|
pub(all) enum Command {
  SortBy(Array[String], reverse~ : Bool)
  Sort(reverse~ : Bool)
  Where(Cond)
  Select(Array[String])
  SelectRows(Array[Int])
  Reject(Array[String])
  Get(Array[Seg])
  First(Int?)
  Last(Int?)
  Skip(Int)
  Length
  Reverse
  Uniq
  Columns
  Lines
  From(Format)
  To(Format)
  Math(MathOp)
  Find(String)
  Parse(String)
} derive(Eq, Debug)

///|
let cmp_ops : Array[(String, CmpOp)] = [
  ("==", Eq),
  ("!=", Ne),
  ("<", Lt),
  ("<=", Le),
  (">", Gt),
  (">=", Ge),
  ("=~", Contains),
  ("!~", NotContains),
  ("starts-with", StartsWith),
  ("ends-with", EndsWith),
]

///|
let formats : Array[(String, Format)] = [
  ("json", Json),
  ("csv", Csv),
  ("tsv", Tsv),
  ("md", Md),
]

///|
let math_ops : Array[(String, MathOp)] = [
  ("sum", Sum),
  ("avg", Avg),
  ("min", Min),
  ("max", Max),
]

///|
let bare_commands : Array[(String, Command)] = [
  ("length", Length),
  ("reverse", Reverse),
  ("uniq", Uniq),
  ("columns", Columns),
  ("lines", Lines),
]

///|
fn[T : Eq] name_of(table : Array[(String, T)], x : T) -> String {
  table.iter().find_first(e => e.1 == x).unwrap().0
}

///|
fn[T] lookup(table : Array[(String, T)], name : String) -> T? {
  table.iter().find_first(e => e.0 == name).map(e => e.1)
}

///|
pub fn CmpOp::symbol(self : CmpOp) -> String {
  name_of(cmp_ops, self)
}

///|
pub fn Format::name(self : Format) -> String {
  name_of(formats, self)
}

///|
pub fn MathOp::name(self : MathOp) -> String {
  name_of(math_ops, self)
}
