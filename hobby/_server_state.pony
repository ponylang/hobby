use lori = "lori"

trait _ServerState
  """
  State object for the Server lifecycle. Each state handles all
  events — the state machine is the single place to understand
  what happens in each state.
  """
  fun ref dispose(server: Server ref): _ServerState

  fun ref on_accept(
    server: Server ref,
    fd: U32)
    : lori.TCPConnectionActor

  fun ref on_listening(
    server: Server ref)
    : _ServerState

  fun ref on_listen_failure(
    server: Server ref)
    : _ServerState

  fun ref on_closed(
    server: Server ref)
    : _ServerState

  fun ref connection_failed(
    server: Server ref,
    reason: String)

class _ServerStarting is _ServerState
  """
  Server constructed, waiting for bind result from lori.
  """
  fun ref dispose(server: Server ref): _ServerState =>
    server._do_dispose()
    _ServerDisposed

  fun ref on_accept(
    server: Server ref,
    fd: U32)
    : lori.TCPConnectionActor
  =>
    // Should not happen before _on_listening, but lori
    // requires a return value.
    server._do_accept(fd)

  fun ref on_listening(
    server: Server ref)
    : _ServerState
  =>
    server._do_listening()
    _ServerListening

  fun ref on_listen_failure(
    server: Server ref)
    : _ServerState
  =>
    server._do_listen_failed()
    _ServerDisposed

  fun ref on_closed(
    server: Server ref)
    : _ServerState
  =>
    server._do_closed()
    _ServerDisposed

  fun ref connection_failed(
    server: Server ref,
    reason: String)
  =>
    server._do_connection_failed(reason)

class _ServerListening is _ServerState
  """
  Server bound and accepting connections.
  """
  fun ref dispose(server: Server ref): _ServerState =>
    server._do_dispose()
    _ServerDisposed

  fun ref on_accept(
    server: Server ref,
    fd: U32)
    : lori.TCPConnectionActor
  =>
    server._do_accept(fd)

  fun ref on_listening(
    server: Server ref)
    : _ServerState
  =>
    // Already listening — should not happen.
    this

  fun ref on_listen_failure(
    server: Server ref)
    : _ServerState
  =>
    // Already listening — should not happen.
    this

  fun ref on_closed(
    server: Server ref)
    : _ServerState
  =>
    server._do_closed()
    _ServerDisposed

  fun ref connection_failed(
    server: Server ref,
    reason: String)
  =>
    server._do_connection_failed(reason)

class _ServerDisposed is _ServerState
  """
  Server shut down. All events are no-ops.
  """
  fun ref dispose(server: Server ref): _ServerState =>
    this

  fun ref on_accept(
    server: Server ref,
    fd: U32)
    : lori.TCPConnectionActor
  =>
    // Disposed but lori requires a return value.
    // The connection will close when the listener
    // finishes shutting down.
    server._do_accept(fd)

  fun ref on_listening(
    server: Server ref)
    : _ServerState
  =>
    this

  fun ref on_listen_failure(
    server: Server ref)
    : _ServerState
  =>
    this

  fun ref on_closed(
    server: Server ref)
    : _ServerState
  =>
    this

  fun ref connection_failed(
    server: Server ref,
    reason: String)
  =>
    None
