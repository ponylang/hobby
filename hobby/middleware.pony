interface val Middleware
  """
  A two-phase request processor that wraps handler execution.

  Middleware is `val` — shareable across connections and stateless between
  requests.

  **`before`** runs during the forward phase, before the handler factory is
  called. Use it for authentication, input validation, or request
  transformation. To short-circuit the chain (e.g., reject with 401), call
  `ctx.respond()` — the framework stops the forward phase and skips to after
  phases. The `?` allows genuine errors to propagate; if `before` errors
  without responding, the framework sends 500.

  **`after`** runs during the reverse phase, after the handler responds (or
  after any middleware that short-circuited). It always runs for every
  middleware whose `before` was invoked, regardless of how the forward phase
  ended. Use it for logging, cleanup, response header modification, or
  session persistence. `after` is not partial — middleware authors handle
  errors internally if needed.

  `after` receives an `AfterContext` with read access to the response status
  and body, and write access to response headers via `set_header()` and
  `add_header()`. For streaming responses, header modifications are no-ops
  (headers are already on the wire), but the `after` phase still runs.
  """
  fun before(ctx: BeforeContext ref) ?
  fun after(ctx: AfterContext ref) => None
