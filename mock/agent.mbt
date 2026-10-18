///|
pub fn agent() -> @program.Program {
  let mut turn = 0
  {
    name: "エージェント (モック)",
    kind: Agent,
    send: (input, session) => {
      turn += 1
      let emit = session.emit
      let mut said = false
      let say = part => {
        said = true
        emit(part)
      }
      if !session.unseen.is_empty() {
        say(Markdown(describe_unseen(session.unseen)))
      }
      if !input.attachments.is_empty() {
        say(Markdown(describe_attachments(input.attachments)))
      }
      if session.programs.iter().find_first(p => p.1 is Interpreter(_))
        is Some((shell, _)) {
        for i, code in input.text.split("`").collect() {
          guard i % 2 == 1 else { continue }
          let reply = (session.run)(shell, {
            text: code.to_owned(),
            attachments: [],
          })
          say(
            Markdown(
              "`\{code}` を \{shell} で実行しました（\{summary(reply)}）。",
            ),
          )
        }
      }
      let lower = input.text.to_lower()
      for r in replies {
        if r.0.iter().any(w => lower.contains(w)) {
          say((r.1)())
        }
      }
      if !said {
        emit(Markdown(help_reply(turn)))
      }
    },
  }
}

///|
fn summary(reply : @program.Reply) -> String {
  if reply.error is Some(msg) {
    return "エラー: \{msg}"
  }
  reply.parts
  .map(p => {
    match p {
      Data(Array(rows)) => "\{rows.length()} 行"
      Data(_) => "値"
      Text(s) => "テキスト \{s.length()} 文字"
      _ => "出力"
    }
  })
  .join("、")
}

///|
fn describe_unseen(exchanges : Array[@program.Exchange]) -> String {
  let rows = exchanges.map(e => {
    let input = e.input.text.replace_all(old="|", new="\\|")
    "| \{e.program} | `\{input}` | \{summary(e.reply)} |\n"
  })
  "前回から \{exchanges.length()} 件のやり取りを受け取りました。\n\n| program | input | output |\n| --- | --- | --- |\n\{rows.join("")}"
}

///|
let replies : Array[(Array[String], () -> @program.Part)] = [
  (["表", "table"], () => Markdown(table_reply)),
  (["図", "mermaid", "diagram"], () => Markdown(diagram_reply)),
  (["html", "ページ"], () => Html(html_reply)),
  (["画像", "image", "グラフ"], () => Image(svg_data_url())),
  (["音", "audio"], () => Audio(wav_data_url())),
  (
    ["ファイル", "file", "csv"],
    () => {
      File({
        name: "tasks.csv",
        media_type: "text/csv",
        data: "task,owner,estimate\nlogin,Alice,3\nexport,Bob,5\n",
      })
    },
  ),
]

///|
fn help_reply(turn : Int32) -> String {
  (
    $|これはエージェントのモックです（このセッションで \{turn} 回目の入力）。
    $|
    $|次の言葉を含めると、それぞれの形式で答えます。組み合わせることもできます。
    $|
    $|- **表**：Markdown の表（並べ替えや絞り込みができます）
    $|- **図**：Mermaid の図
    $|- **HTML**：HTML のページ
    $|- **画像**：SVG の画像
    $|- **音**：WAV の音声
    $|- **ファイル**：CSV ファイル
    $|
    $|ファイルを添付すると、その内容の要約を返します。
    $|`ls` のようにバッククォートで囲むと、そのコマンドを処理系で実行します。
  )
}

///|
let table_reply : String =
  #|タスクの見積もりを表にしました。
  #|
  #|| task | owner | priority | estimate |
  #|| --- | --- | --- | ---: |
  #|| ログイン画面 | Alice | high | 3 |
  #|| CSV 書き出し | Bob | low | 5 |
  #|| 検索 | 佐藤 | high | 8 |
  #|| 設定画面 | Alice | medium | 2 |
  #|| 通知 | Carol | medium | 4 |
  #|
  #|見積もりの単位は日です。

///|
let diagram_reply : String =
  #|入力から出力までの流れは次のとおりです。
  #|
  #|```mermaid
  #|flowchart LR
  #|  U[受け手] -->|テキスト・ファイル・GUI操作| O[patchbay]
  #|  O -->|入力| P[処理プログラム]
  #|  P -->|型付きの出力| O
  #|  O -->|表・図・HTML| U
  #|```

///|
let html_reply : String =
  #|<!doctype html>
  #|<style>
  #|  body { font: 14px system-ui; margin: 16px; }
  #|  .card { border: 1px solid #8884; border-radius: 8px; padding: 12px; }
  #|  button { font: inherit; }
  #|</style>
  #|<div class="card">
  #|  <h3>カウンター</h3>
  #|  <p>この HTML は隔離された枠の中で動いています。</p>
  #|  <button onclick="n.textContent = +n.textContent + 1">+1</button>
  #|  <span id="n">0</span>
  #|</div>

///|
fn describe_attachments(attachments : Array[@program.Attachment]) -> String {
  let rows = attachments.map(a => {
    "| \{a.name.replace_all(old="|", new="\\|")} | \{a.media_type} | \{a.data.length()} |\n"
  })
  let head = match attachments.iter().find_first(a => a.is_text()) {
    Some(a) => {
      let lines = a.data.split("\n").take(3).map(l => l.to_owned()).collect()
      "\n`\{a.name}` の先頭:\n\n```\n\{lines.join("\n")}\n```\n"
    }
    None => ""
  }
  "\{attachments.length()} 個の添付を受け取りました。\n\n| name | type | size |\n| --- | --- | ---: |\n\{rows.join("")}\{head}"
}

///|
fn svg_data_url() -> String {
  let values = [3.0, 5.0, 8.0, 2.0, 4.0]
  let labels = ["login", "export", "search", "settings", "notify"]
  let sb = StringBuilder()
  sb.write_string(
    "<svg xmlns='http://www.w3.org/2000/svg' width='360' height='180' font-family='sans-serif' font-size='11'>",
  )
  for i, v in values {
    let h = v * 18.0
    let x = 20 + i * 66
    sb.write_string(
      "<rect x='\{x}' y='\{150.0 - h}' width='44' height='\{h}' fill='#4a7dd8'/><text x='\{x + 22}' y='166' text-anchor='middle'>\{labels[i]}</text><text x='\{x + 22}' y='\{145.0 - h}' text-anchor='middle'>\{v.to_int()}</text>",
    )
  }
  sb.write_string("</svg>")
  "data:image/svg+xml;base64," + @base64.encode(@utf8.encode(sb.to_string()))
}

///|
fn wav_data_url() -> String {
  let rate = 8000
  let n = rate / 2
  let buf = Buffer()
  let u32 = x => buf.write_int_le(x)
  let u16 = (x : Int32) => buf.write_int16_le(Int16::from_int(x))
  buf.write_string_utf8("RIFF")
  u32(36 + n)
  buf.write_string_utf8("WAVEfmt ")
  u32(16)
  u16(1)
  u16(1)
  u32(rate)
  u32(rate)
  u16(1)
  u16(8)
  buf.write_string_utf8("data")
  u32(n)
  for i in 0..<n {
    let t = i.to_double() / rate.to_double()
    let fade = 1.0 - i.to_double() / n.to_double()
    let s = 128.0 + 90.0 * fade * @math.sin(2.0 * @math.PI * 440.0 * t)
    buf.write_byte(s.to_int().to_byte())
  }
  "data:audio/wav;base64," + @base64.encode(buf.to_bytes())
}
