primitive Serving
  """
  Returned by `Application.serve()` or `Application.serve_ssl()` when
  the server started successfully.

  The listener is running and accepting connections.
  """
class val ConfigError
  """
  Returned by `Application.serve()` or `Application.serve_ssl()` when
  a configuration error prevented the server from starting.

  Contains a human-readable description of the error. Common causes:
  - Overlapping group prefixes (two groups with the same prefix)
  - Empty group prefix (use `add_request_interceptor()` instead)
  - Special characters in group prefix (`:` or `*`)
  - Conflicting param names at the same path position across methods
  - Conflicting wildcard names at the same path position across methods
  """
  let message: String

  new val create(message': String) =>
    message = message'

type ServeResult is (Serving | ConfigError)
  """
  The result of `Application.serve()` or `Application.serve_ssl()`:
  either the server started (`Serving`) or a configuration error was
  detected (`ConfigError`).
  """
