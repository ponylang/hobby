type HandlerFactory is {(HandlerContext iso): (HandlerReceiver tag | None)} val
  """
  A handler factory creates request handlers for incoming HTTP requests.

  `HandlerFactory` is a `val` lambda that receives an iso handler context and
  optionally returns a handler actor reference. Inline handlers respond via
  `RequestHandler` and return `None`. Async handlers create an actor and return
  it as `HandlerReceiver tag` for lifecycle notifications (dispose, backpressure).
  """
