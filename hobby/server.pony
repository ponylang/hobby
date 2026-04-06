use "time"
use lori = "lori"
use stallion = "stallion"
use ssl_net = "ssl/net"

actor Server is lori.TCPListenerActor
  """
  HTTP/HTTPS server that accepts connections and dispatches requests
  through a compiled routing tree.

  Created with a `BuiltApplication` (from `Application.build()`) and a
  `ServerNotify` for lifecycle events. Two constructors prevent
  accidentally serving HTTP when HTTPS is intended.

  ```pony
  actor Main is hobby.ServerNotify
    let _env: Env

    new create(env: Env) =>
      _env = env
      let auth = lori.TCPListenAuth(env.root)
      let app = hobby.Application
        .> get("/", {(ctx) =>
          hobby.RequestHandler(consume ctx)
            .respond(stallion.StatusOK, "Hello!")
        } val)

      match app.build()
      | let built: hobby.BuiltApplication =>
        hobby.Server(auth, built, this
          where host = "0.0.0.0", port = "8080")
      | let err: hobby.ConfigError =>
        env.err.print(err.message)
      end

    be listening(server: hobby.Server,
      host: String, service: String)
    =>
      _env.out.print(
        "Listening on " + host + ":" + service)
  ```

  Call `dispose()` to shut down. In-flight connections drain naturally.
  """
  var _tcp_listener: lori.TCPListener =
    lori.TCPListener.none()
  let _server_auth: lori.TCPServerAuth
  let _config: stallion.ServerConfig
  let _router: _Router val
  let _notify: ServerNotify
  let _timers: Timers tag
  let _timeout_ns: U64
  let _ssl_ctx: (ssl_net.SSLContext val | None)
  var _state: _ServerState =
    _ServerStarting

  new create(
    auth: lori.TCPListenAuth,
    app: BuiltApplication,
    notify: ServerNotify,
    host: String = "localhost",
    port: String = "0",
    handler_timeout: (HandlerTimeout | None) =
      DefaultHandlerTimeout(),
    config: stallion.ServerConfig =
      stallion.ServerConfig("localhost", "0"))
  =>
    """
    Start an HTTP server.

    `host` and `port` control the listener bind address. `config` is
    passed through to Stallion for parser limits (max body size, idle
    timeout, etc.) — the host/port in `config` are not used for
    binding.
    """
    _server_auth = lori.TCPServerAuth(auth)
    _config = config
    _router = app._get_router()
    _notify = notify
    _timers = Timers
    _timeout_ns =
      _HandlerTimeoutToNs(handler_timeout)
    _ssl_ctx = None
    _tcp_listener =
      lori.TCPListener(auth, host, port, this)

  new ssl(
    auth: lori.TCPListenAuth,
    app: BuiltApplication,
    notify: ServerNotify,
    ssl_ctx: ssl_net.SSLContext val,
    host: String = "localhost",
    port: String = "0",
    handler_timeout: (HandlerTimeout | None) =
      DefaultHandlerTimeout(),
    config: stallion.ServerConfig =
      stallion.ServerConfig("localhost", "0"))
  =>
    """
    Start an HTTPS server.

    Identical to `create` except connections use TLS via the provided
    `SSLContext`. The context must be configured with a certificate and
    private key.
    """
    _server_auth = lori.TCPServerAuth(auth)
    _config = config
    _router = app._get_router()
    _notify = notify
    _timers = Timers
    _timeout_ns =
      _HandlerTimeoutToNs(handler_timeout)
    _ssl_ctx = ssl_ctx
    _tcp_listener =
      lori.TCPListener(auth, host, port, this)

  be dispose() =>
    """
    Shut down the server. Closes the listener and disposes the shared
    timer actor. In-flight connections drain naturally. Idempotent.
    """
    _state = _state.dispose(this)

  be _connection_failed(reason: String) =>
    """
    Called by `_Connection` on per-connection failures (e.g., SSL
    handshake errors). Forwards to `ServerNotify`.
    """
    _state.connection_failed(this, reason)

  fun ref _listener(): lori.TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32)
    : lori.TCPConnectionActor
  =>
    _state.on_accept(this, fd)

  fun ref _on_listening() =>
    _state = _state.on_listening(this)

  fun ref _on_listen_failure() =>
    _state = _state.on_listen_failure(this)

  fun ref _on_closed() =>
    _state = _state.on_closed(this)

  // --- Helper methods called by state objects ---
  fun ref _do_dispose() =>
    _tcp_listener.close()
    _timers.dispose()

  fun ref _do_accept(fd: U32)
    : lori.TCPConnectionActor
  =>
    _Connection(
      _server_auth,
      fd,
      _config,
      _router,
      _timers,
      _timeout_ns,
      this,
      _ssl_ctx)

  fun ref _do_listening() =>
    try
      (let host, let port) =
        _tcp_listener.local_address().name()?
      _notify.listening(this, host, port)
    else
      _notify.listening(this, "", "")
    end

  fun ref _do_listen_failed() =>
    _timers.dispose()
    _notify.listen_failed(
      this, "failed to start listener")

  fun ref _do_closed() =>
    _timers.dispose()
    _notify.closed(this)

  fun ref _do_connection_failed(reason: String) =>
    _notify.connection_failed(this, reason)

primitive _HandlerTimeoutToNs
  fun apply(
    handler_timeout: (HandlerTimeout | None))
    : U64
  =>
    match handler_timeout
    | let t: HandlerTimeout => t() * 1_000_000
    else
      0
    end
