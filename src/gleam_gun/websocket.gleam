import gleam/http.{Header}
import gleam/dynamic.{Dynamic}
import gleam/erlang/atom.{Atom}
import gleam/result
import gleam/string_builder.{StringBuilder}
import gleam/bit_builder.{BitBuilder}
import gleam_gun/gun.{ConnectionPid, StreamReference}

pub opaque type Connection {

  Connection(ref: StreamReference, pid: ConnectionPid)
}

pub type Frame {
  Close
  Text(String)
  Binary(BitString)
}

pub type ConnectionOptsTransportOpts {
  Verify(Atom)
}

pub type ConnectionOpts {
  Transport(Atom)
  TransportOpts(List(ConnectionOptsTransportOpts))
}

pub fn connect(
  hostname: String,
  path: String,
  port: Int,
  headers: List(Header),
  opts: List(ConnectionOpts),
) {
  use pid <- result.then(
    gun.open(hostname, port, map_from_list(opts))
    |> result.map_error(ConnectionFailed),
  )

  use _ <- result.then(
    gun.await_up(pid)
    |> result.map_error(ConnectionFailed),
  )

  // Upgrade to websockets
  let ref = gun.ws_upgrade(pid, path, headers)
  let conn = Connection(pid: pid, ref: ref)
  use _ <- result.then(
    await_upgrade(conn, 1000)
    |> result.map_error(ConnectionFailed),
  )

  // TODO: handle upgrade failure
  // https://ninenines.eu/docs/en/gun/2.0/guide/websocket/
  // https://ninenines.eu/docs/en/gun/1.2/manual/gun_error/
  // https://ninenines.eu/docs/en/gun/1.2/manual/gun_response/
  Ok(conn)
}

pub fn send(to conn: Connection, this message: String) -> Nil {
  gun.ws_send(conn.pid, gun.Text(message))
}

pub fn send_builder(to conn: Connection, this message: StringBuilder) -> Nil {
  gun.ws_send(conn.pid, gun.TextBuilder(message))
}

pub fn send_binary(to conn: Connection, this message: BitString) -> Nil {
  gun.ws_send(conn.pid, gun.Binary(message))
}

pub fn send_binary_builder(to conn: Connection, this message: BitBuilder) -> Nil {
  gun.ws_send(conn.pid, gun.BinaryBuilder(message))
}

pub external fn receive(from: Connection, within: Int) -> Result(Frame, Nil) =
  "ffi" "ws_receive"

external fn await_upgrade(from: Connection, within: Int) -> Result(Nil, Dynamic) =
  "ffi" "ws_await_upgrade"

external fn map_from_list(list: List(a)) -> m =
  "maps" "from_list"

// TODO: listen for close events
pub fn close(conn: Connection) -> Nil {
  gun.ws_send(conn.pid, gun.Close)
}

/// The URI of the websocket server to connect to
pub type ConnectError {
  ConnectionRefused(status: Int, headers: List(Header))
  ConnectionFailed(reason: Dynamic)
}