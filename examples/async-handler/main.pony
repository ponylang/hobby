// in your code this `use` statement would be:
// use hobby = "hobby"
use hobby = "../../hobby"
use stallion = "stallion"
use lori = "lori"

actor Main is hobby.ServerNotify
  """

  Async handler example.

  Demonstrates actor-based handlers that do async work before responding.
  A `SlowService` actor simulates an async operation (e.g., a database
  query). The handler actor creates a `RequestHandler`, sends a query to
  the service, and responds when the result arrives.

  Routes:
  - GET /      -> inline handler (immediate response)
  - GET /slow  -> async handler (responds after service callback)

  Try it:
    curl http://localhost:8080/
    curl http://localhost:8080/slow
  """

  let _env: Env

  new create(env: Env) =>
    _env = env
    let auth = lori.TCPListenAuth(env.root)
    let slow = SlowService
    let app = hobby.Application
      .> get(
        "/",
        {(ctx) =>
          hobby.RequestHandler(consume ctx)
            .respond(stallion.StatusOK, "Hello from Hobby!")
        } val)
      .> get(
        "/slow",
        {(ctx)(slow) =>
          SlowHandler(consume ctx, slow)
        } val)

    match \exhaustive\ app.build()
    | let built: hobby.BuiltApplication =>
      hobby.Server(
        auth, built, this
        where host = "0.0.0.0", port = "8080")
    | let err: hobby.ConfigError =>
      env.err.print(err.message)
    end

  be listening(
    server: hobby.Server,
    host: String,
    service: String)
  =>
    _env.out.print(
      "Listening on " + host + ":" + service)

  be listen_failed(
    server: hobby.Server,
    reason: String)
  =>
    _env.err.print(reason)

actor SlowService
  """
  Simulates an async service via self-directed message.
  """
  be query(requester: SlowHandler tag) =>
    requester.result("done after async work")

actor SlowHandler is hobby.HandlerReceiver
  """
  Handles a request by delegating to a SlowService for async work.
  """
  embed _handler: hobby.RequestHandler

  new create(ctx: hobby.HandlerContext iso, service: SlowService tag) =>
    _handler = hobby.RequestHandler(consume ctx)
    service.query(this)

  be result(data: String) =>
    _handler.respond(stallion.StatusOK, data)

  be dispose() => None
  be throttled() => None
  be unthrottled() => None
