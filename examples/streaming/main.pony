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
      .>get("/", {(ctx) =>
        hobby.RequestHandler(consume ctx).respond(stallion.StatusOK,
          "Visit /stream to see a chunked streaming response.")
      } val)
      .>get("/stream", {(ctx) =>
        StreamHandler(consume ctx)
      } val)
      .serve(auth, stallion.ServerConfig("0.0.0.0", "8080"), env.out)

actor StreamHandler is hobby.HandlerReceiver
  """Starts streaming and sends 5 numbered chunks."""
  embed _handler: hobby.RequestHandler

  new create(ctx: hobby.HandlerContext iso) =>
    _handler = hobby.RequestHandler(consume ctx)
    match _handler.start_streaming(stallion.StatusOK)
    | hobby.StreamingStarted => _send()
    | stallion.ChunkedNotSupported =>
      _handler.respond(stallion.StatusOK,
        "Chunked encoding not supported — upgrade to HTTP/1.1.")
    | hobby.BodyNotNeeded => None
    end

  be _send() =>
    _handler.send_chunk("chunk 1 of 5\n")
    _handler.send_chunk("chunk 2 of 5\n")
    _handler.send_chunk("chunk 3 of 5\n")
    _handler.send_chunk("chunk 4 of 5\n")
    _handler.send_chunk("chunk 5 of 5\n")
    _handler.finish()

  be dispose() => None
  be throttled() => None
  be unthrottled() => None
