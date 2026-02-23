interface tag StreamSender
  """
  Send response chunks and signal completion.

  Returned by `Context.start_streaming()` on success. `start_streaming()` may
  also return `ChunkedNotSupported` when the client doesn't support chunked
  encoding — callers should `match` on the result before using the sender.

  Pass this to a producer actor that sends chunks asynchronously via
  `send_chunk()` and signals completion with `finish()`. Both methods are
  behaviors — they execute asynchronously in the connection actor's message
  queue.

  The sender silently drops chunks after `finish()` is called or if the
  underlying connection closes.
  """
  be send_chunk(data: ByteSeq)
  be finish()
