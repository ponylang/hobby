interface tag ServerNotify
  """
  Lifecycle event receiver for `Server`.

  Implement this interface to receive notifications about server state
  changes. All behaviors have default no-op implementations — override
  only what you need.

  Modeled after the notify pattern in ponylang/postgres.
  """

  be listening(server: Server, host: String, service: String) =>
    """
    The server is bound and accepting connections.

    `host` and `service` are the actual bound address and port, which
    is useful when binding to port 0 (OS-assigned).
    """
    None

  be listen_failed(server: Server, reason: String) =>
    """
    The server failed to bind (port in use, permission denied, etc.).
    """
    None

  be connection_failed(server: Server, reason: String) =>
    """
    A per-connection failure occurred (e.g., SSL handshake error).
    """
    None

  be closed(server: Server) =>
    """
    The server was closed externally (not via `dispose()`).
    """
    None
