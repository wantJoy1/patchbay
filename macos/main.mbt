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
  messages : Array[Bytes]
  arrived : @cond_var.Cond
}

///|
impl @external_loop_integration.ExternalEventLoop for Cocoa with fn poll(
  self,
  timeout?,
) {
  poll_cocoa(timeout.unwrap_or(-1))
  while has_message() {
    self.messages.push(take_message())
  }
  if !self.messages.is_empty() {
    self.arrived.signal()
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
fn unavailable(name : String, error : Error) -> @program.Program {
  {
    name,
    kind: Agent,
    send: (_, _) => {
      raise @program.Failure("\{name} を起動できません: \{error}")
    },
  }
}

///|
async fn main {
  let cocoa : Cocoa = { messages: [], arrived: @cond_var.Cond(), }
  @async.set_external_event_loop(cocoa)
  open_window(@utf8.encode(page_html))
  @async.with_task_group(group => {
    let nushell = @nushell.nushell(group) catch {
      e => unavailable("Nushell", e)
    }
    let app = @app.App::new(
      [nushell, @mock.agent()],
      spawn=job => {
        let task = group.spawn(job, allow_failure=true)
        () => task.cancel()
      },
      changed=show_frame,
    )
    for ;; {
      while cocoa.messages.is_empty() {
        cocoa.arrived.wait()
      }
      let request : @app.Request = @json.from_json(
        @json.parse(@utf8.decode_lossy(cocoa.messages.remove(0))),
      ) catch {
        _ => Init
      }
      if request is Open(url~) {
        open_url(@utf8.encode(url))
      }
      show_frame(app.handle(request))
    }
  })
}
