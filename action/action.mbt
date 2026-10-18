///|
pub(all) enum GuiAction {
  SortColumn(String)
  Filter(Array[@lang.Seg], @lang.CmpOp, Json)
  HideColumn(String)
  KeepColumns(Array[String])
  KeepRows(Array[Int])
  Drill(Array[@lang.Seg])
  Append(@lang.Command)
  RemoveStage(Int)
} derive(Eq, Debug)

///|
/// Why not always add a stage: clicking a header twice would give
/// `sort-by age | sort-by age` rather than `sort-by age --reverse`.
pub fn apply(
  p : Array[@lang.Command],
  action : GuiAction,
) -> Array[@lang.Command] {
  let init = if p.is_empty() { [] } else { p[:p.length() - 1].to_owned() }
  let replace_last = cmd => [..init, cmd]
  let push = cmd => [..p, cmd]
  match (action, p.last()) {
    (SortColumn(c), _) =>
      match effective_sort(p) {
        Some((i, [col], false)) if col == c =>
          p.mapi((j, s) => if j == i { SortBy([c], reverse=true) } else { s })
        Some((i, [col], true)) if col == c => remove(p, i)
        Some((i, _, _)) =>
          p.mapi((j, s) => if j == i { SortBy([c], reverse=false) } else { s })
        None => push(SortBy([c], reverse=false))
      }
    (Filter(path, op, v), Some(Where(Cmp(path2, op2, _)))) if path2 == path &&
      op2 == op => replace_last(Where(Cmp(path, op, v)))
    (Filter(path, op, v), _) => push(Where(Cmp(path, op, v)))
    (HideColumn(c), Some(Reject(cols))) if !cols.contains(c) =>
      replace_last(Reject([..cols, c]))
    (HideColumn(c), Some(Select(cols))) if cols.contains(c) => {
      let rest = cols.filter(x => x != c)
      if rest.is_empty() {
        init
      } else {
        replace_last(Select(rest))
      }
    }
    (HideColumn(c), _) => push(Reject([c]))
    (KeepColumns(cols), Some(Select(_))) => replace_last(Select(cols))
    (KeepColumns(cols), _) => push(Select(cols))
    (KeepRows(rows), last) => {
      let rows = rows.copy()
      rows.sort()
      match last {
        // Why not add another `select`: the indices refer to the output of
        // the last one, so composing them keeps a single stage.
        Some(SelectRows(prev)) =>
          replace_last(SelectRows(rows.filter_map(i => prev.get(i))))
        _ => push(SelectRows(rows))
      }
    }
    // Why not merge into a preceding `get`: a key applied to a list maps over
    // its rows, so `get tags | get 0` differs from `get tags.0`.
    (Drill(path), _) => push(Get(path))
    (Append(cmd), _) => push(cmd)
    (RemoveStage(i), _) =>
      if i >= 0 && i < p.length() {
        remove(p, i)
      } else {
        p
      }
  }
}

///|
fn remove(p : Array[@lang.Command], i : Int) -> Array[@lang.Command] {
  [..p[:i], ..p[i + 1:]]
}

///|
fn effective_sort(p : Array[@lang.Command]) -> (Int, Array[String], Bool)? {
  for i = p.length() - 1; i >= 0; i = i - 1 {
    match p[i] {
      SortBy(cols, reverse~) => return Some((i, cols, reverse))
      // Why not `select ROW...`: its indices refer to the incoming order.
      Where(_) | Select(_) | Reject(_) | Find(_) => continue
      _ => return None
    }
  }
  None
}

///|
pub fn sort_state(p : Array[@lang.Command]) -> (String, Bool)? {
  match effective_sort(p) {
    Some((_, [col], reverse)) => Some((col, reverse))
    _ => None
  }
}
