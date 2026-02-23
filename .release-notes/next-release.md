## Add streaming response support

Handlers can now send chunked HTTP responses by calling `ctx.start_streaming()`:

```pony
primitive StreamHandler is Handler
  fun apply(ctx: Context ref) ? =>
    match ctx.start_streaming(stallion.StatusOK)?
    | let sender: StreamSender tag =>
      MyProducer(sender)
    | stallion.ChunkedNotSupported =>
      ctx.respond(stallion.StatusOK, "Chunked encoding not supported.")
    end
```

`start_streaming()` returns `(StreamSender tag | ChunkedNotSupported)` — match on the result and pass the sender to a producer actor that calls `send_chunk()` to send data and `finish()` to close the stream. When the client doesn't support chunked encoding (e.g., HTTP/1.0), the handler can fall back to `ctx.respond()`. If the handler errors after starting a stream, the framework automatically sends the terminal chunk to prevent a hung connection.

## Buffer pipelined requests during streaming responses

When a client sends pipelined HTTP requests while a streaming response is in progress, the second request's handler could overwrite the connection's streaming state. This caused the first stream's chunks to be sent through the wrong responder and the second stream's chunks to be silently dropped.

Pipelined requests are now buffered during an active streaming response and processed after the stream finishes.

## Return typed result from start_streaming()

`Context.start_streaming()` now returns `(StreamSender tag | ChunkedNotSupported)` instead of `StreamSender tag`, and is partial (`?`). Handlers must match on the result to handle clients that don't support chunked encoding, and the `?` propagates when a response has already been sent.

Before:

```pony
primitive StreamHandler is Handler
  fun apply(ctx: Context ref) =>
    let sender = ctx.start_streaming(stallion.StatusOK)
    MyProducer(sender)
```

After:

```pony
primitive StreamHandler is Handler
  fun apply(ctx: Context ref) ? =>
    match ctx.start_streaming(stallion.StatusOK)?
    | let sender: StreamSender tag =>
      MyProducer(sender)
    | stallion.ChunkedNotSupported =>
      ctx.respond(stallion.StatusOK, "Chunked encoding not supported.")
    end
```
