## Add streaming response support

Handlers can now send chunked HTTP responses by calling `ctx.start_streaming()`:

```pony
primitive StreamHandler is Handler
  fun apply(ctx: Context ref) =>
    let sender = ctx.start_streaming(stallion.StatusOK)
    MyProducer(sender)
```

`start_streaming()` returns a `StreamSender tag` — pass it to a producer actor that calls `send_chunk()` to send data and `finish()` to close the stream. If the handler errors after starting a stream, the framework automatically sends the terminal chunk to prevent a hung connection.
