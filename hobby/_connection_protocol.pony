use stallion = "stallion"

trait tag _ConnectionProtocol
  """
  Protocol behaviors that `RequestHandler` sends to `_Connection`.

  Package-private — users interact with `RequestHandler`, not this interface.
  """
  be _handler_respond(token: U64, status: stallion.Status,
    headers: (stallion.Headers val | None), body: ByteSeq)
  be _handler_start_streaming(token: U64, status: stallion.Status,
    headers: (stallion.Headers val | None))
  be _handler_send_chunk(token: U64, data: ByteSeq)
  be _handler_finish(token: U64)
