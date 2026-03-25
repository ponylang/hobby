use stallion = "stallion"

class val SessionConfig
  """
  Configuration for server-side sessions.

  Validates cookie settings at construction time — invalid configurations
  fail at startup, not on the first request.

  Cookie security attributes are hardcoded: `Secure`, `HttpOnly`,
  `SameSite=Lax`, `__Host-` prefix. These are the only correct settings
  for session cookies. `Secure` and `__Host-` mean sessions require HTTPS —
  local development needs TLS (e.g., a self-signed cert).

  The cookie name is configurable (default `__Host-_hobby_session`).
  Developers who need plain HTTP for local testing can use a name without
  the `__Host-` prefix, accepting the reduced security.
  """
  let key: CookieSigningKey
  let store: MemorySessionStore tag
  let cookie_name: String val
  let cookie_path: String val
  let max_age: (I64 | None)

  new val create(
    key': CookieSigningKey,
    store': MemorySessionStore tag,
    cookie_name': String val = "__Host-_hobby_session",
    cookie_path': String val = "/",
    max_age': (I64 | None) = None) ?
  =>
    """
    Create a session configuration.

    Validates by building a test `SetCookieBuilder`. Errors if the name
    is not a valid RFC 2616 token or violates `__Host-` prefix constraints.

    `max_age` controls cookie lifetime: `None` for a session cookie (browser
    deletes on close), or seconds as `I64`.
    """
    match stallion.SetCookieBuilder(cookie_name', "x")
      .with_path(cookie_path')
      .build()
    | let _: stallion.SetCookieBuildError => error
    end
    key = key'
    store = store'
    cookie_name = cookie_name'
    cookie_path = cookie_path'
    max_age = max_age'
