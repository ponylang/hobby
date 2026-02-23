interface val Middleware
  """
  A two-phase request processor that wraps handler execution.

  Middleware is `val` — shareable across connections and stateless between
  requests.

  **`before`** runs during the forward phase, before the handler. Use it for
  authentication, input validation, or request transformation. To short-circuit
  the chain (e.g., reject with 401), call `ctx.respond()` — the framework stops
  the forward phase and skips to after phases. The `?` allows genuine errors to
  propagate; if `before` errors without responding, the framework sends 500. If
  `before` errors after calling `ctx.start_streaming()`, the framework sends the
  terminal chunk to close the stream instead of sending 500.

  **`after`** runs during the reverse phase, after the handler (or after any
  middleware that short-circuited). It always runs for every middleware whose
  `before` was invoked, regardless of whether the chain completed normally,
  short-circuited, or errored. Use it for logging, cleanup, or response
  modification. `after` is not partial — middleware authors handle errors
  internally if needed.
  """
  fun before(ctx: Context ref) ?
  fun after(ctx: Context ref) => None
