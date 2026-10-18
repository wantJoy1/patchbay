///|
test "tables become data and the rest stays html" {
  let blocks = @markdown.split(
    (
      #|# 結果
      #|
      #|ユーザーは **3 人** です。
      #|
      #|| name | age |
      #|| --- | ---: |
      #|| Alice | 34 |
      #|| `Bob` | |
      #|
      #|- 一つ目
      #|- [リンク](https://example.com)
    ),
  )
  guard blocks is [Html(head), Table(table), Html(tail)] else {
    fail("expected html, a table and html")
  }
  inspect(
    head,
    content="<h1>結果</h1><p>ユーザーは <strong>3 人</strong> です。</p>",
  )
  json_inspect(table, content=[
    { "name": "Alice", "age": 34 },
    { "name": "Bob", "age": null },
  ])
  inspect(
    tail,
    content="<ul><li>一つ目</li><li><a href=\"https://example.com\">リンク</a></li></ul>",
  )
}

///|
test "mermaid code blocks are diagrams and other code is escaped" {
  let blocks = @markdown.split(
    (
      #|```mermaid
      #|graph TD
      #|  A --> B
      #|```
      #|```js
      #|a < b
      #|```
    ),
  )
  assert_eq(blocks, [
    Mermaid("graph TD\n  A --> B"),
    Html("<pre><code>a &lt; b</code></pre>"),
  ])
}

///|
test "inline markup allows only safe links" {
  assert_eq(
    @markdown.inline("a `<b>` *c* **d** [e](javascript:x) * f"),
    "a <code>&lt;b&gt;</code> <em>c</em> <strong>d</strong> [e](javascript:x) * f",
  )
}
