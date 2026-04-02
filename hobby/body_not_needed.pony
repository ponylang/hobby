primitive BodyNotNeeded
  """

  Returned by `RequestHandler.start_streaming()` when streaming cannot begin.

  This happens in two cases: the request is HEAD (the framework sends a
  headers-only response automatically), or `respond()` was already called.
  In either case, the handler should not start a producer — there is no
  stream to write to.
  """

