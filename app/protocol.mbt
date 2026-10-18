///|
pub(all) enum Request {
  Init
  Send(text~ : String)
  Act(id~ : String, shift~ : Bool)
  View(block~ : Int, text~ : String)
  Copy(block~ : Int, rows~ : Array[Int], cols~ : Array[Int])
  Attach(name~ : String, media_type~ : String, data~ : String)
  History(delta~ : Int, text~ : String)
  Escape
  Open(url~ : String)
} derive(FromJson, Debug)

///|
/// Why not send only what changed: a whole frame leaves the page no state of
/// its own.
pub(all) struct Frame {
  html : String
  controls : String
  placeholder : String
  input : String?
  clipboard : String
  notice : String
  scroll : Bool
} derive(ToJson)

///|
pub fn App::handle(self : App, request : Request) -> Frame {
  self.notice = ""
  self.clipboard = ""
  match request {
    Send(text~) => self.send(text)
    Act(id~, shift~) => self.dispatch(id, shift~)
    View(block~, text~) => self.set_view(block, text)
    Copy(block~, rows~, cols~) =>
      if self.blocks.get(block) is Some(b) {
        self.clipboard = b.copy_cells(rows, cols, self.copy_format)
        self.notice = "\{rows.length() * cols.length()} セルをデータとしてコピーしました"
      }
    Attach(name~, media_type~, data~) =>
      self.pending.push({ name, media_type, data, })
    History(delta~, text~) => self.history_step(delta, text)
    Escape => self.menu = None
    Init | Open(_) => ()
  }
  let (html, controls) = self.render()
  let frame = {
    html,
    controls,
    placeholder: self.placeholder(),
    input: self.next_input,
    clipboard: self.clipboard,
    notice: self.notice,
    scroll: self.scroll_to_end,
  }
  self.next_input = None
  self.scroll_to_end = false
  frame
}
