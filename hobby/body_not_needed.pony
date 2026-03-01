primitive BodyNotNeeded
  """
  Returned by `Context.start_streaming()` when the request is HEAD.

  The framework has already sent a headers-only response. The handler should
  not start a producer -- there is no stream to write to.
  """
