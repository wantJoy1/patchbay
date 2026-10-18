///|
pub(all) enum Layout {
  Table
  Tree
  Json
} derive(Eq, Debug)

///|
pub(all) enum UiAction {
  Gui(Int, @action.GuiAction)
  OpenMenu(Int, Int, Int)
  CloseMenu
  ToggleRow(Int, Int)
  SelectAllRows(Int)
  ClearSelection(Int)
  CopySelection(Int)
  CopyText(String)
  SetLayout(Int, Layout)
  SetCopyFormat(@lang.Format)
  ShowAllRows(Int)
  SelectProgram(Int)
  UseInput(String)
  Send(String)
  RemoveAttachment(Int)
} derive(Eq, Debug)

///|
priv struct Entry {
  program : Int
  input : @program.Input
  reply : @program.Reply
  blocks : Array[Int]
  steps : Array[Entry]
}

///|
pub struct App {
  priv programs : Array[@program.Program]
  priv mut current : Int
  priv entries : Array[Entry]
  priv blocks : Array[Block]
  priv pending : Array[@program.Attachment]
  priv history : Array[(Int, String)]
  priv mut history_cursor : Int?
  priv mut draft : String
  priv mut next_input : String?
  priv mut menu : (Int, Int, Int)?
  priv mut copy_format : @lang.Format
  priv mut clipboard : String
  priv mut notice : String
  priv mut scroll_to_end : Bool
  // Why not number actions globally: keys scoped to an entry keep its HTML
  // unchanged until it changes, so the page can leave it alone.
  priv actions : Map[String, UiAction]
  priv mut scope : String
  priv mut next_act : Int
}

///|
pub fn App::new(programs : Array[@program.Program]) -> App {
  {
    programs,
    current: 0,
    entries: [],
    blocks: [],
    pending: [],
    history: [],
    history_cursor: None,
    draft: "",
    next_input: None,
    menu: None,
    copy_format: Md,
    clipboard: "",
    notice: "",
    scroll_to_end: false,
    actions: {},
    scope: "",
    next_act: 0,
  }
}

///|
fn App::send(self : App, text : String) -> Unit {
  let text = text.trim().to_owned()
  if text == "" && self.pending.is_empty() {
    return
  }
  let input : @program.Input = { text, attachments: self.pending.copy(), }
  self.pending.clear()
  let unseen = if self.programs[self.current].kind is Agent {
    self.unseen_by(self.current)
  } else {
    []
  }
  self.entries.push(self.run(self.current, input, unseen))
  if text != "" && self.history.last() != Some((self.current, text)) {
    self.history.push((self.current, text))
  }
  self.history_cursor = None
  self.next_input = Some("")
  self.menu = None
  self.scroll_to_end = true
}

///|
/// The programs an agent runs become steps of its entry, drawn like any other
/// output.
fn App::run(
  self : App,
  p : Int,
  input : @program.Input,
  unseen : Array[@program.Exchange],
) -> Entry {
  let steps = []
  let session : @program.Session = {
    unseen,
    programs: self.programs.map(q => (q.name, q.kind)),
    run: (name, input) => {
      guard self.programs.search_by(q => q.name == name) is Some(q) else {
        return { parts: [], error: Some("unknown program: \{name}"), }
      }
      let step = self.run(q, input, [])
      steps.push(step)
      step.reply
    },
  }
  let reply = (self.programs[p].send)(input, session)
  let blocks = []
  for part in reply.parts {
    for block in blocks_of(part) {
      blocks.push(self.blocks.length())
      self.blocks.push(block)
    }
  }
  { program: p, input, reply, blocks, steps, }
}

///|
fn App::unseen_by(self : App, p : Int) -> Array[@program.Exchange] {
  let mut since = 0
  for i, e in self.entries {
    if e.program == p {
      since = i + 1
    }
  }
  self.entries[since:]
  .iter()
  .map(e => @program.Exchange::{
    program: self.programs[e.program].name,
    input: e.input,
    reply: e.reply,
  })
  .collect()
}

///|
fn App::history_step(self : App, delta : Int, text : String) -> Unit {
  let own = self.history.filter(h => h.0 == self.current).map(h => h.1)
  let next = match self.history_cursor {
    None if delta < 0 && !own.is_empty() => {
      self.draft = text
      own.length() - 1
    }
    None => return
    Some(i) => i + delta
  }
  if next < 0 {
    return
  }
  self.history_cursor = if next < own.length() { Some(next) } else { None }
  self.next_input = Some(own.get(next).unwrap_or(self.draft))
}

///|
fn App::close_menu_of(self : App, b : Int) -> Unit {
  if self.menu is Some((mb, _, _)) && mb == b {
    self.menu = None
  }
}

///|
fn App::set_view(self : App, b : Int, src : String) -> Unit {
  if self.blocks.get(b) is Some(block) && block.set_view_text(src) {
    self.close_menu_of(b)
  }
}

///|
fn App::apply(self : App, b : Int, action : @action.GuiAction) -> Unit {
  guard self.blocks.get(b) is Some(block) else { return }
  match block.apply(action) {
    Ok(true) => self.close_menu_of(b)
    Ok(false) => ()
    Err(msg) => self.notice = msg
  }
}

///|
fn App::dispatch(self : App, id : String, shift~ : Bool) -> Unit {
  guard self.actions.get(id) is Some(action) else { return }
  let with_block = (b, f : (Block) -> Unit) => {
    if self.blocks.get(b) is Some(block) {
      f(block)
    }
  }
  match action {
    Gui(b, a) => self.apply(b, a)
    OpenMenu(b, r, c) =>
      self.menu = if self.menu == Some((b, r, c)) {
        None
      } else {
        Some((b, r, c))
      }
    CloseMenu => self.menu = None
    ToggleRow(b, r) => with_block(b, blk => blk.toggle_row(r, shift~))
    SelectAllRows(b) =>
      with_block(b, blk => {
        blk.selected.clear()
        blk.selected.append(Array::makei(blk.row_count(), i => i))
      })
    ClearSelection(b) =>
      with_block(b, blk => {
        blk.selected.clear()
        blk.anchor = None
      })
    CopySelection(b) =>
      with_block(b, blk => {
        self.clipboard = blk.selection_text(self.copy_format)
        self.notice = "\{blk.selected.length()} 行を \{self.copy_format.name()} でコピーしました"
      })
    CopyText(text) => {
      self.clipboard = text
      self.menu = None
      self.notice = "コピーしました"
    }
    SetLayout(b, layout) => with_block(b, blk => blk.layout = layout)
    SetCopyFormat(format) => self.copy_format = format
    ShowAllRows(b) => with_block(b, blk => blk.show_all = true)
    SelectProgram(i) => {
      self.current = i
      self.history_cursor = None
    }
    UseInput(text) => self.next_input = Some(text)
    Send(text) => self.send(text)
    RemoveAttachment(i) => self.pending.remove(i) |> ignore
  }
}
