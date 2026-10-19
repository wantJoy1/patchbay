///|
/// Why not other languages: everything builds with moon alone, and only the
/// macOS window, the page and the checks run by git and CI need glue in their
/// own languages.
let glue : Array[String] = [
  "macos/host.m", "macos/page.html", ".githooks/pre-commit", ".github/workflows/check.yml",
]

///|
async fn files() -> (String, Array[String]) {
  let (_, root) = @process.collect_stdout("git", [
    "rev-parse", "--show-toplevel",
  ])
  let root = root.text().trim().to_owned()
  let (_, list) = @process.collect_stdout("git", [
    "-C", root, "ls-files", "--cached", "--others", "--exclude-standard",
  ])
  (
    root,
    list
    .text()
    .split("\n")
    .filter(f => f != "")
    .map(f => f.to_owned())
    .collect(),
  )
}

///|
async test "every file is MoonBit, module metadata, docs or listed glue" {
  let (_, files) = files()
  let foreign = files.filter(f => {
    !(f.has_suffix(".mbt") ||
    f.has_suffix(".mbti") ||
    f.has_suffix("moon.pkg") ||
    f.has_suffix(".md") ||
    f is ("moon.mod" | "LICENSE" | ".gitignore") ||
    glue.contains(f))
  })
  assert_eq(foreign, [])
}

///|
async test "every comment says why another way was not taken" {
  let (root, files) = files()
  let offending = []
  for f in files {
    let marker = match f {
      ".githooks/pre-commit" | ".github/workflows/check.yml" => "#"
      _ if f.has_suffix(".mbt") || f is ("macos/host.m" | "macos/page.html") =>
        "/"
      _ => continue
    }
    let mut in_comment = false
    for i, line in @fs.read_file("\{root}/\{f}").text().split("\n").collect() {
      let t = line.trim()
      let comment = t.has_prefix(marker) && !(t is ("///|" | "#!/bin/sh"))
      if comment &&
        !in_comment &&
        !t.trim_start(chars=marker).trim().has_prefix("Why not") {
        offending.push("\{f}:\{i + 1}: \{t}")
      }
      in_comment = comment
    }
  }
  assert_eq(offending, [])
}

///|
/// Why not any section: the README holds only the problem and the ideal state;
/// anything else can be derived from the code, so a new section must first be
/// judged to be part of the ideal state and listed here.
async test "the README has only the listed sections" {
  let (root, _) = files()
  let headings = @fs.read_file("\{root}/README.mbt.md")
    .text()
    .split("\n")
    .filter(l => l.has_prefix("#"))
    .map(l => l.to_owned())
    .collect()
  assert_eq(headings, ["# patchbay", "## 注意", "## 目標", "## 小目標"])
}

///|
/// Why not any author: a dependency's build can run its own commands and C
/// code, so only owners whose code is trusted may appear, transitive ones
/// included.
async test "every dependency comes from a trusted owner" {
  let (root, _) = files()
  assert_eq(
    @fs.readdir("\{root}/.mooncakes", include_hidden=false, sort=true),
    ["moonbitlang"],
  )
}
