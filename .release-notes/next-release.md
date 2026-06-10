## Fix truncated streaming responses to slow clients

Streaming a response to a slow client could silently truncate it. The client received a partial body with no closing chunk, and the connection then closed — for example, `curl` reported `transfer closed with N bytes remaining to read`.

This affected both streaming responses you build yourself with `RequestHandler.start_streaming()`, `send_chunk()`, and `finish()`, and large static files served by `ServeFiles`, which stream in chunks. The truncation happened when the network repeatedly applied backpressure while hobby was still flushing buffered chunks: chunks that had not yet been sent were dropped instead of being held back until the connection could write again. Finishing a response while backpressured could lose buffered data the same way. Both cases are fixed — buffered chunks now stay queued until they can actually be sent, and a response held back by backpressure completes once the connection drains.

