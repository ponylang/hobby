// in your code this `use` statement would be:
// use hobby = "hobby"
use hobby = "../../hobby"
use stallion = "stallion"
use lori = "lori"

actor Main
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
  new create(env: Env) =>
    let auth = lori.TCPListenAuth(env.root)
    let slow = SlowService
    hobby.Application
      .>get("/", {(ctx) =>
        hobby.RequestHandler(consume ctx)
          .respond(stallion.StatusOK, "Hello from Hobby!")
      } val)
      .>get("/slow", {(ctx)(slow) =>
        SlowHandler(consume ctx, slow)
      } val)
      .serve(auth, stallion.ServerConfig("0.0.0.0", "8080"), env.out)

actor SlowService
  """Simulates an async service via self-directed message."""
  be query(requester: SlowHandler tag) =>
    requester.result("done after async work")

actor SlowHandler is hobby.HandlerReceiver
  embed _handler: hobby.RequestHandler

  new create(ctx: hobby.HandlerContext iso, service: SlowService tag) =>
    _handler = hobby.RequestHandler(consume ctx)
    service.query(this)

  be result(data: String) =>
    _handler.respond(stallion.StatusOK, data)

  be dispose() => None
  be throttled() => None
  be unthrottled() => None
