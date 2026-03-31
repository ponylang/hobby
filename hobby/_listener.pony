use "time"
use lori = "lori"
use stallion = "stallion"

actor _Listener is lori.TCPListenerActor
  """
  Internal TCP listener that accepts connections and spawns connection actors.

  Created by `Application.serve()` with a frozen `_Router val` and app-level
  response interceptors. Each accepted connection gets its own `_Connection`
  actor. A shared `Timers` actor is created once and passed to every connection
  for handler timeout management.

  App-level response interceptors are passed through to each connection so they
  can run on 404 responses (where no route matched and no per-route interceptors
  are available).
  """
  var _tcp_listener: lori.TCPListener = lori.TCPListener.none()
  let _server_auth: lori.TCPServerAuth
  let _config: stallion.ServerConfig
  let _router: _Router val
  let _out: OutStream
  let _timers: Timers tag
  let _timeout_ns: U64
  let _response_interceptors: (Array[ResponseInterceptor val] val | None)

  new create(auth: lori.TCPListenAuth, config: stallion.ServerConfig,
    router: _Router val, out: OutStream, timeout_ns: U64,
    response_interceptors: (Array[ResponseInterceptor val] val | None))
  =>
    _server_auth = lori.TCPServerAuth(auth)
    _config = config
    _router = router
    _out = out
    _timers = Timers
    _timeout_ns = timeout_ns
    _response_interceptors = response_interceptors
    _tcp_listener = lori.TCPListener(auth, config.host, config.port, this)

  fun ref _listener(): lori.TCPListener => _tcp_listener

  fun ref _on_accept(fd: U32): lori.TCPConnectionActor =>
    _Connection(_server_auth, fd, _config, _router, _timers, _timeout_ns,
      _response_interceptors)

  fun ref _on_listening() =>
    try
      (let host, let port) = _tcp_listener.local_address().name()?
      _out.print("Hobby listening on " + host + ":" + port)
    else
      _out.print("Hobby listening")
    end

  fun ref _on_listen_failure() =>
    _out.print("Hobby failed to start listener")

  fun ref _on_closed() =>
    _out.print("Hobby listener closed")
