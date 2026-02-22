use lori = "lori"
use stallion = "stallion"

actor _Listener is lori.TCPListenerActor
  """
  Internal TCP listener that accepts connections and spawns connection actors.

  Created by `Application.serve()` with a frozen `_Router val`. Each accepted
  connection gets its own `_Connection` actor.
  """
  var _tcp_listener: lori.TCPListener = lori.TCPListener.none()
  let _server_auth: lori.TCPServerAuth
  let _config: stallion.ServerConfig
  let _router: _Router val
  let _out: OutStream

  new create(auth: lori.TCPListenAuth, config: stallion.ServerConfig,
    router: _Router val, out: OutStream)
  =>
    _server_auth = lori.TCPServerAuth(auth)
    _config = config
    _router = router
    _out = out
    _tcp_listener = lori.TCPListener(auth, config.host, config.port, this
      where limit = config.max_concurrent_connections)

  fun ref _listener(): lori.TCPListener => _tcp_listener

  fun ref _on_accept(fd: U32): lori.TCPConnectionActor =>
    _Connection(_server_auth, fd, _config, _router)

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
