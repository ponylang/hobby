// in your code this `use` statement would be:
// use hobby = "hobby"
use hobby = "../../hobby"
use stallion = "stallion"
use lori = "lori"

actor Main
  """
  Streaming response example.

  Starts an HTTP server on 0.0.0.0:8080 with two routes:
  - GET /        -> static page explaining the /stream endpoint
  - GET /stream  -> chunked streaming response with 5 numbered chunks

  HEAD requests are handled automatically — `start_streaming()` returns
  `BodyNotNeeded` and the handler skips starting a producer.

  Try it:
    curl http://localhost:8080/
    curl http://localhost:8080/stream
    curl --head http://localhost:8080/stream
  """
  new create(env: Env) =>
    let auth = lori.TCPListenAuth(env.root)
    hobby.Application
      .>get("/", IndexHandler)
      .>get("/stream", StreamHandler)
      .serve(auth, stallion.ServerConfig("0.0.0.0", "8080"), env.out)

primitive IndexHandler is hobby.Handler
  fun apply(ctx: hobby.Context ref) =>
    ctx.respond(stallion.StatusOK,
      "Visit /stream to see a chunked streaming response.")

primitive StreamHandler is hobby.Handler
  fun apply(ctx: hobby.Context ref) ? =>
    match \exhaustive\ ctx.start_streaming(stallion.StatusOK)?
    | let sender: hobby.StreamSender tag =>
      ChunkProducer(sender)
    | stallion.ChunkedNotSupported =>
      ctx.respond(stallion.StatusOK,
        "Chunked encoding not supported — upgrade to HTTP/1.1.")
    | hobby.BodyNotNeeded => None
    end

actor ChunkProducer
  """Sends 5 numbered chunks and finishes the stream."""
  let _sender: hobby.StreamSender tag

  new create(sender: hobby.StreamSender tag) =>
    _sender = sender
    _send()

  be _send() =>
    _sender.send_chunk("chunk 1 of 5\n")
    _sender.send_chunk("chunk 2 of 5\n")
    _sender.send_chunk("chunk 3 of 5\n")
    _sender.send_chunk("chunk 4 of 5\n")
    _sender.send_chunk("chunk 5 of 5\n")
    _sender.finish()
