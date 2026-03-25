use stallion = "stallion"

primitive _SessionCookieWriter
  """
  Build `Set-Cookie` header values for session cookies. Extracted for
  testability. Security attributes are hardcoded.
  """

  fun set_cookie(config: SessionConfig, session_id: String val)
    : String val
  =>
    """Build a Set-Cookie header value for establishing a session."""
    let signed = SignedCookie.sign(config.key, session_id)
    let builder = stallion.SetCookieBuilder(config.cookie_name, signed)
      .with_path(config.cookie_path)
      .with_secure(true)
      .with_http_only(true)
      .with_same_site(stallion.SameSiteLax)
    match config.max_age
    | let ma: I64 => builder.with_max_age(ma)
    end
    match builder.build()
    | let sc: stallion.SetCookie val => sc.header_value()
    else
      ""  // Should never happen — validated at config construction time
    end

  fun clear_cookie(config: SessionConfig): String val =>
    """Build a Set-Cookie header value that clears the cookie (Max-Age=0)."""
    match stallion.SetCookieBuilder(config.cookie_name, "")
      .with_path(config.cookie_path)
      .with_secure(true)
      .with_http_only(true)
      .with_same_site(stallion.SameSiteLax)
      .with_max_age(0)
      .build()
    | let sc: stallion.SetCookie val => sc.header_value()
    else
      ""
    end
