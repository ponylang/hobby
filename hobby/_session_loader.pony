primitive _SessionLoader
  """
  Extract and verify a session ID from a request cookie.

  Returns either a session ID (needs store lookup) or a `SessionData val`
  (new session, no lookup needed). Extracted for testability.
  """

  fun apply(
    cookie_value: (String val | None),
    config: SessionConfig)
    : (String val | SessionData val)
  =>
    """
    Returns `String val` (session ID for store lookup) if the cookie is
    valid, or `SessionData val` (new empty session) if the cookie is
    missing, tampered, or malformed.

    If CSPRNG fails during new-ID generation, returns `SessionData` with
    an empty ID string. The caller must check for this and respond 500.
    """
    match cookie_value
    | let raw: String val =>
      match SignedCookie.verify(config.key, raw)
      | let session_id: String val => session_id
      | let _: SignedCookieError =>
        _new_session()
      end
    else
      _new_session()
    end

  fun _new_session(): SessionData val =>
    try
      SessionData._empty(SessionId.generate()?)
    else
      SessionData._empty("")  // CSPRNG failure sentinel
    end
