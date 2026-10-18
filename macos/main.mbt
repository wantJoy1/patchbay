///|
#borrow(page)
extern "C" fn open_window(page : Bytes) -> Unit = "patchbay_open"

///|
extern "C" fn poll_cocoa(timeout : Int32) -> Unit = "patchbay_poll"

///|
extern "C" fn wakeup() -> Unit = "patchbay_wakeup"

///|
extern "C" fn has_message() -> Bool = "patchbay_has_message"

///|
extern "C" fn take_message() -> Bytes = "patchbay_take_message"

///|
#borrow(frame)
extern "C" fn show(frame : Bytes) -> Unit = "patchbay_show"

///|
#borrow(text)
extern "C" fn set_clipboard(text : Bytes) -> Unit = "patchbay_set_clipboard"

///|
#borrow(url)
extern "C" fn open_url(url : Bytes) -> Unit = "patchbay_open_url"

///|
priv struct Cocoa {
  messages : @aqueue.Queue[Bytes]
}

///|
impl @external_loop_integration.ExternalEventLoop for Cocoa with fn poll(
  self,
  timeout?,
) {
  poll_cocoa(timeout.unwrap_or(-1))
  while has_message() {
    self.messages.try_put(take_message()) |> ignore
  }
}

///|
impl @external_loop_integration.ExternalEventLoop for Cocoa with fn get_wakeup_callback_for_foreign_thread(
  _,
) {
  () => wakeup()
}

///|
impl @external_loop_integration.ExternalEventLoop for Cocoa with fn terminate(_) {
  ()
}

///|
fn show_frame(frame : @app.Frame) -> Unit {
  if frame.clipboard != "" {
    set_clipboard(@utf8.encode(frame.clipboard))
  }
  show(@utf8.encode(frame.to_json().stringify()))
}

///|
fn unavailable(
  name : String,
  kind : @program.Kind,
  error : Error,
) -> @program.Program {
  {
    name,
    kind,
    settings: None,
    send: (_, _) => {
      raise @program.Failure("\{name} を起動できません: \{error}")
    },
  }
}

///|
/// Why not leave opencode its own tools: what it runs must go through
/// patchbay to be drawn, so every built-in tool that reads, writes or runs
/// anything is denied, leaving patchbay's tool.
let opencode_config : Json = {
  "permission": {
    "bash": "deny",
    "edit": "deny",
    "read": "deny",
    "glob": "deny",
    "grep": "deny",
    "list": "deny",
    "task": "deny",
    "skill": "deny",
    "lsp": "deny",
    "webfetch": "deny",
    "websearch": "deny",
  },
}

///|
/// Why not wait for opencode however long it takes: the window stays blank
/// until every program has started.
async fn opencode(
  group : @async.TaskGroup[Unit],
  interpreters : Array[@program.Program],
) -> @program.Program {
  let name = "opencode"
  @async.with_timeout(10000, () => {
    @acp.agent(
      group,
      name~,
      command="opencode",
      args=["acp"],
      env={ "OPENCODE_CONFIG_CONTENT": opencode_config.stringify() },
      interpreters=interpreters.map(p => (p.name, p.kind)),
    )
  }) catch {
    e => unavailable(name, Agent, e)
  }
}

///|
/// Why not opencode's own configuration: the model and other settings are
/// chosen in patchbay, and stay apart from how opencode is used elsewhere.
let settings_dir : String = "\{@env.get_env_var("HOME").unwrap_or(".")}/Library/Application Support/patchbay"

///|
async fn read_settings() -> Map[String, Map[String, String]] {
  let text = @fs.read_file("\{settings_dir}/settings.json").text() catch {
    _ => return {}
  }
  @json.from_json(@json.parse(text)) catch {
    _ => {}
  }
}

///|
/// Why not let each write run on its own: two writes would race, and an
/// older one could land last.
fn save_settings(
  group : @async.TaskGroup[Unit],
  lock : @async.Mutex,
) -> (Map[String, Map[String, String]]) -> Unit {
  chosen => {
    let text = Json(chosen).stringify(indent=2)
    group.spawn_bg(allow_failure=true, () => {
      lock.acquire()
      defer lock.release()
      @fs.mkdir(settings_dir, recursive=true, allow_exist=true)
      @fs.write_file("\{settings_dir}/settings.json", text)
    })
  }
}

///|
async fn main {
  let cocoa : Cocoa = { messages: @aqueue.Queue(kind=Unbounded), }
  @async.set_external_event_loop(cocoa)
  open_window(@utf8.encode(page_html))
  @async.with_task_group(group => {
    let nushell = @nushell.nushell(group) catch {
      e => unavailable("Nushell", Interpreter(language="nu"), e)
    }
    let app = @app.App::new(
      [nushell, opencode(group, [nushell])],
      group,
      changed=show_frame,
      chosen=read_settings(),
      remember=save_settings(group, @async.Mutex()),
    )
    for ;; {
      let message = @utf8.decode_lossy(cocoa.messages.get())
      let request : @app.Request = @json.from_json(@json.parse(message)) catch {
        e => {
          println(
            "patchbay: ignoring a request that does not decode: \{e}: \{message}",
          )
          continue
        }
      }
      if request is Open(url~) {
        open_url(@utf8.encode(url))
      }
      app.handle(request)
    }
  })
}
