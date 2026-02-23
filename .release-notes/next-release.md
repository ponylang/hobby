## Buffer pipelined requests during streaming responses

When a client sends pipelined HTTP requests while a streaming response is in progress, the second request's handler could overwrite the connection's streaming state. This caused the first stream's chunks to be sent through the wrong responder and the second stream's chunks to be silently dropped.

Pipelined requests are now buffered during an active streaming response and processed after the stream finishes.

