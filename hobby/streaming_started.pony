primitive StreamingStarted
  """
  Returned by `RequestHandler.start_streaming()` on success.

  Indicates that chunked streaming has begun. The handler should proceed to
  send chunks via `RequestHandler.send_chunk()` and signal completion with
  `RequestHandler.finish()`.
  """

