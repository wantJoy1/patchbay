///|
/// Why not bytes for `data`: the page reads a file as text or as a data URL,
/// and either goes into HTML as it is.
pub(all) struct Attachment {
  name : String
  media_type : String
  data : String
} derive(Eq, Debug)

///|
pub fn Attachment::is_text(self : Attachment) -> Bool {
  !self.data.has_prefix("data:")
}

///|
pub(all) struct Input {
  text : String
  attachments : Array[Attachment]
} derive(Eq, Debug)

///|
pub(all) enum Part {
  Markdown(String)
  Mermaid(String)
  Html(String)
  Data(Json)
  Text(String)
  Image(String)
  Audio(String)
  File(Attachment)
} derive(Eq, Debug)

///|
pub(all) struct Reply {
  parts : Array[Part]
  error : String?
} derive(Eq, Debug)

///|
pub(all) enum Kind {
  Agent
  Interpreter(language~ : String)
} derive(Eq, Debug)

///|
pub(all) struct Exchange {
  program : String
  input : Input
  reply : Reply
} derive(Eq, Debug)

///|
pub(all) suberror Failure {
  Failure(String)
} derive(Debug)

///|
/// Why not return the parts at the end: agents and long commands produce
/// output over time, and it should be drawn as it comes. Why not give a
/// program only its own input: an agent works on the same programs as the
/// human, so it must see their exchanges and run them itself.
pub(all) struct Session {
  unseen : Array[Exchange]
  programs : Array[(String, Kind)]
  emit : (Part) -> Unit
  run : async (String, Input) -> Reply
}

///|
pub(all) struct Choice {
  value : String
  name : String
} derive(Eq, Debug)

///|
pub(all) struct Setting {
  id : String
  name : String
  value : String
  choices : Array[Choice]
} derive(Eq, Debug)

///|
/// Why not a fixed list: a program can change its settings itself, as an
/// agent falling back to another model does, so they are read when drawn.
pub(all) struct Settings {
  current : () -> Array[Setting]
  change : async (String, String) -> Unit
}

///|
/// Why not methods for the session: what carries over between inputs differs
/// by program, so it stays in the closure behind `send`.
pub(all) struct Program {
  name : String
  kind : Kind
  send : async (Input, Session) -> Unit
  settings : Settings?
}
