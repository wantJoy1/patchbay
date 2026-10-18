///|
enum Layout {
  Table
  Tree
  Json
} derive(Eq, Debug)

///|
enum Menu {
  Cell(Int32, Int32, Int32)
  Copy(Int32)
  Setting(Int32, String)
} derive(Eq)

///|
enum UiAction {
  Gui(Int32, @view.GuiAction)
  OpenMenu(Int32, Int32, Int32)
  ToggleRow(Int32, Int32)
  SelectAllRows(Int32)
  ClearSelection(Int32)
  CopySelection(Int32)
  CopyAll(Int32)
  CopyAs(Int32, @view.Format)
  OpenCopy(Int32)
  EditView(Int32)
  CopyText(String)
  SetLayout(Int32, Layout)
  ShowAllRows(Int32)
  SelectProgram(Int32)
  UseInput(String)
  Send(String)
  RemoveAttachment(Int32)
  Cancel(Int32)
  ToggleStep(Int32, Int32)
  OpenSetting(Int32, String)
  ChangeSetting(Int32, String, String)
} derive(Eq, Debug)

///|
priv struct Output {
  program : Int32
  input : @program.Input
  parts : Array[@program.Part]
  mut error : String?
  blocks : Array[Int32]
  mut open : Bool
}

///|
fn Output::new(program : Int32, input : @program.Input) -> Output {
  { program, input, parts: [], error: None, blocks: [], open: false, }
}

///|
fn Output::reply(self : Output) -> @program.Reply {
  { parts: self.parts, error: self.error, }
}

///|
/// Why not one output per entry: the programs an agent runs are steps of
/// its entry, drawn with it.
priv struct Entry {
  output : Output
  steps : Array[Output]
  seen_by : Array[Int32]
  mut running : Bool
  mut cancel : () -> Unit
}

///|
pub struct App {
  priv programs : Array[@program.Program]
  priv group : @async.TaskGroup[Unit]
  priv changed : (Frame) -> Unit
  priv mut current : Int32
  priv entries : Array[Entry]
  priv blocks : Array[Block]
  priv pending : Array[@program.Attachment]
  priv history : Array[(Int32, String)]
  priv mut history_cursor : Int32?
  priv mut draft : String
  priv mut next_input : String?
  priv mut menu : Menu?
  priv mut copy_format : @view.Format
  priv mut clipboard : String
  priv mut notice : String
  priv mut scroll_to_end : Bool
  priv actions : Map[String, UiAction]
  priv mut scope : String
  priv mut next_act : Int32
  priv chosen : Map[String, Map[String, String]]
  priv remember : (Map[String, Map[String, String]]) -> Unit
}

///|

///|
/// Why not keep the settings a program starts with: the user chose others
/// before, and is to find them again. Why not keep a choice the program no
/// longer offers: the program would refuse it.
pub fn App::new(
  programs : Array[@program.Program],
  group : @async.TaskGroup[Unit],
  changed~ : (Frame) -> Unit,
  chosen~ : Map[String, Map[String, String]] = {},
  remember~ : (Map[String, Map[String, String]]) -> Unit = _ => (),
) -> App {
  let app = {
    programs,
    group,
    changed,
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
    chosen,
    remember,
  }
  for i, p in programs {
    guard p.settings is Some(settings) && chosen.get(p.name) is Some(values) else {
      continue
    }
    for setting in (settings.current)() {
      if values.get(setting.id) is Some(value) &&
        value != setting.value &&
        setting.choices.iter().any(c => c.value == value) {
        app.change_setting(i, setting.id, value)
      }
    }
  }
  app
}

///|
fn App::change_setting(
  self : App,
  p : Int32,
  id : String,
  value : String,
) -> Unit {
  guard self.programs[p].settings is Some(settings) else { return }
  self.group.spawn_bg(allow_failure=true, () => {
    (settings.change)(id, value) catch {
      e =>
        self.notice = "\{self.programs[p].name} の設定を変えられません: \{e}"
    }
    self.notify()
  })
}

///|
fn App::notify(self : App) -> Unit {
  (self.changed)(self.frame())
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
  let entry : Entry = {
    output: Output::new(self.current, input),
    steps: [],
    seen_by: [],
    running: true,
    cancel: () => (),
  }
  self.entries.push(entry)
  let task = self.group.spawn(allow_failure=true, () => {
    self.execute(entry.output, unseen, entry.steps)
    entry.running = false
    self.notify()
  })
  entry.cancel = () => task.cancel()
  if text != "" && self.history.last() != Some((self.current, text)) {
    self.history.push((self.current, text))
  }
  self.history_cursor = None
  self.next_input = Some("")
  self.menu = None
  self.scroll_to_end = true
}

///|
async fn App::execute(
  self : App,
  output : Output,
  unseen : Array[@program.Exchange],
  steps : Array[Output],
) -> Unit {
  let session : @program.Session = {
    unseen,
    programs: self.programs.map(q => (q.name, q.kind)),
    emit: part => {
      output.parts.push(part)
      for block in blocks_of(part) {
        output.blocks.push(self.blocks.length())
        self.blocks.push(block)
      }
      self.notify()
    },
    run: (name, input) => {
      guard self.programs.search_by(q => q.name == name) is Some(q) else {
        return { parts: [], error: Some("unknown program: \{name}"), }
      }
      let step = Output::new(q, input)
      steps.push(step)
      self.execute(step, [], steps)
      step.reply()
    },
  }
  (self.programs[output.program].send)(output.input, session) catch {
    @program.Failure(msg) => output.error = Some(msg)
    e => output.error = Some(e.to_string())
  }
}

///|
fn App::unseen_by(self : App, p : Int32) -> Array[@program.Exchange] {
  let unseen = []
  for e in self.entries {
    if e.output.program != p && !e.running && !e.seen_by.contains(p) {
      e.seen_by.push(p)
      unseen.push(@program.Exchange::{
        program: self.programs[e.output.program].name,
        input: e.output.input,
        reply: e.output.reply(),
      })
    }
  }
  unseen
}

///|
fn App::history_step(self : App, delta : Int32, text : String) -> Unit {
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
fn App::close_menu_of(self : App, b : Int32) -> Unit {
  if self.menu is Some(Cell(mb, _, _) | Copy(mb)) && mb == b {
    self.menu = None
  }
}

///|
fn App::set_view(self : App, b : Int32, src : String) -> Unit {
  if self.blocks.get(b) is Some(block) && block.set_view_text(src) {
    self.close_menu_of(b)
  }
}

///|
fn App::apply(self : App, b : Int32, action : @view.GuiAction) -> Unit {
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
      self.menu = if self.menu == Some(Cell(b, r, c)) {
        None
      } else {
        Some(Cell(b, r, c))
      }
    OpenCopy(b) =>
      self.menu = if self.menu == Some(Copy(b)) { None } else { Some(Copy(b)) }
    EditView(b) => with_block(b, blk => blk.editing = !blk.editing)
    ToggleStep(i, s) =>
      if self.entries.get(i).bind(e => e.steps.get(s)) is Some(step) {
        step.open = !step.open
      }
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
    CopyAll(b) =>
      with_block(b, blk => {
        self.clipboard = @view.serialize(blk.shown, self.copy_format)
        self.notice = "\{self.copy_format.name()} でコピーしました"
      })
    CopyAs(b, format) => {
      self.copy_format = format
      self.menu = None
      with_block(b, blk => {
        self.clipboard = @view.serialize(blk.shown, format)
        self.notice = "\{format.name()} でコピーしました"
      })
    }
    CopyText(text) => {
      self.clipboard = text
      self.menu = None
      self.notice = "コピーしました"
    }
    SetLayout(b, layout) => with_block(b, blk => blk.layout = layout)
    ShowAllRows(b) => with_block(b, blk => blk.show_all = true)
    OpenSetting(p, id) =>
      self.menu = if self.menu == Some(Setting(p, id)) {
        None
      } else {
        Some(Setting(p, id))
      }
    ChangeSetting(p, id, value) => {
      self.menu = None
      let name = self.programs[p].name
      let values = self.chosen.get(name).unwrap_or({})
      values[id] = value
      self.chosen[name] = values
      (self.remember)(self.chosen)
      self.change_setting(p, id, value)
    }
    SelectProgram(i) => {
      self.current = i
      self.history_cursor = None
    }
    UseInput(text) => self.next_input = Some(text)
    Send(text) => self.send(text)
    RemoveAttachment(i) => self.pending.remove(i) |> ignore
    Cancel(i) =>
      if self.entries.get(i) is Some({ running: true, .. } as entry) {
        entry.output.error = Some("中断しました")
        entry.running = false
        (entry.cancel)()
      }
  }
}
