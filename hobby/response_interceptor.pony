use stallion = "stallion"

interface val ResponseInterceptor
  """
  Synchronous response interceptor that runs after the handler responds but
  before the response goes to the wire.

  Interceptors inspect and modify the response — status, headers, body — or
  perform read-only side effects like logging. All registered interceptors
  run in registration order; there is no short-circuiting.

  Interceptors are `val` and must be stateless or capture only immutable
  configuration. They run synchronously in the connection actor, so they
  should do only cheap work. Expensive or async work belongs in the handler.

  For streaming responses, mutations (`set_status()`, `set_header()`,
  `add_header()`, `set_body()`) are silently ignored — headers and status
  are already on the wire. The interceptor still runs for logging and
  metrics; check `ctx.is_streaming()` to branch on streaming state.
  """
  fun apply(ctx: ResponseContext ref)
    """
    Process the response. Inspect or modify status, headers, and body
    via the provided `ResponseContext`.
    """

