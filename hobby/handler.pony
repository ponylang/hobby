interface val Handler
  """
  A request handler that processes an HTTP request and produces a response.

  Handlers are `val` — shareable across connections and stateless between
  requests. They receive `ref` access to the `Context` because they execute
  synchronously inside the connection actor's behavior.

  Call `ctx.respond()` or `ctx.respond_with_headers()` to send a complete
  response, or `ctx.start_streaming()` to begin a chunked streaming response.
  `start_streaming()` is partial — it errors if a response has already been
  sent, and returns `(StreamSender tag | ChunkedNotSupported | BodyNotNeeded)`
  so handlers can fall back to a non-streaming response when the client doesn't
  support chunked encoding, or skip streaming entirely for HEAD requests.

  If the handler returns without responding, the framework sends 500 Internal
  Server Error. The `?` allows genuine errors to propagate — if the handler
  errors without having called `respond`, the framework also sends 500. If the
  handler errors after a successful `start_streaming()`, the framework sends
  the terminal chunk to close the stream instead of sending 500.
  """
  fun apply(ctx: Context ref) ?
