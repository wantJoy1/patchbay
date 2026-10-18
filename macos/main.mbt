///|
#borrow(page)
extern "C" fn run(page : Bytes, handler : FuncRef[(Bytes) -> Bytes]) -> Unit = "patchbay_run"

///|
#borrow(text)
extern "C" fn set_clipboard(text : Bytes) -> Unit = "patchbay_set_clipboard"

///|
#borrow(url)
extern "C" fn open_url(url : Bytes) -> Unit = "patchbay_open_url"

///|
let app : @app.App = @app.App::new([@nushell.nushell(), @mock.agent()])

///|
fn handle(request : Bytes) -> Bytes {
  let request : @app.Request = @json.from_json(
    @json.parse(@utf8.decode_lossy(request)),
  ) catch {
    _ => Init
  }
  if request is Open(url~) {
    open_url(@utf8.encode(url))
  }
  let frame = app.handle(request)
  if frame.clipboard != "" {
    set_clipboard(@utf8.encode(frame.clipboard))
  }
  @utf8.encode(frame.to_json().stringify())
}

///|
fn main {
  run(@utf8.encode(page_html), request => handle(request))
}
