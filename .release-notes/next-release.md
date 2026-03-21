## Redesign handler model to actor-per-request

hobby's handler model has been redesigned from synchronous `Handler val` executing inside the connection actor to an actor-per-request model where each request's handler can do async work and respond when ready.

The old `Handler` interface with `fun apply(ctx: Context ref) ?` is replaced by `HandlerFactory` — a `val` lambda that receives an iso `HandlerContext` and returns an optional `HandlerReceiver tag`. Inline handlers consume the context into a `RequestHandler` and respond immediately. Async handlers create an actor that holds the `RequestHandler` and responds later (e.g., after a database query or external service call).

Before:

```pony
primitive HelloHandler is hobby.Handler
  fun apply(ctx: hobby.Context ref) =>
    ctx.respond(stallion.StatusOK, "Hello!")

hobby.Application
  .>get("/", HelloHandler)
  .serve(auth, config, env.out)
```

After (inline):

```pony
hobby.Application
  .>get("/", {(ctx) =>
    hobby.RequestHandler(consume ctx)
      .respond(stallion.StatusOK, "Hello!")
  } val)
  .serve(auth, config, env.out)
```

After (async):

```pony
actor MyHandler is hobby.HandlerReceiver
  embed _handler: hobby.RequestHandler

  new create(ctx: hobby.HandlerContext iso, db: Database tag) =>
    _handler = hobby.RequestHandler(consume ctx)
    db.query(this)

  be result(data: String) =>
    _handler.respond(stallion.StatusOK, data)

  be dispose() => None
  be throttled() => None
  be unthrottled() => None

hobby.Application
  .>get("/data", {(ctx)(db) => MyHandler(consume ctx, db)} val)
  .serve(auth, config, env.out)
```

Middleware has also changed. The single `Context ref` is replaced by separate `BeforeContext ref` (for the `before` phase) and `AfterContext ref` (for the `after` phase). `AfterContext` can modify response headers via `set_header()` and `add_header()` before they hit the wire.

Before:

```pony
class val LogMiddleware is hobby.Middleware
  let _out: OutStream
  new val create(out: OutStream) => _out = out
  fun before(ctx: hobby.Context ref) => None
  fun after(ctx: hobby.Context ref) =>
    _out.print(ctx.request.method.string() + " " + ctx.request.uri.path)
```

After:

```pony
class val LogMiddleware is hobby.Middleware
  let _out: OutStream
  new val create(out: OutStream) => _out = out
  fun before(ctx: hobby.BeforeContext ref) => None
  fun after(ctx: hobby.AfterContext ref) =>
    _out.print(
      ctx.request().method.string() + " " + ctx.request().uri.path)
```

Streaming also changed. Instead of receiving a `StreamSender tag` from `Context.start_streaming()`, handler actors call `RequestHandler.start_streaming()`, `send_chunk()`, and `finish()` directly. See the [streaming example](https://github.com/ponylang/hobby/tree/main/examples/streaming/) for the full pattern.

`Application.serve()` now accepts an optional `handler_timeout` parameter (milliseconds, default 30 seconds). When a handler fails to respond within the timeout, the framework sends 504 Gateway Timeout. Pass `None` to disable.

### Removed types

- `Handler` — replaced by `HandlerFactory`
- `Context` — replaced by `HandlerContext` + `BeforeContext` + `AfterContext` + `RequestHandler`
- `StreamSender` — handler actors call `RequestHandler.send_chunk`/`finish` directly

### New types

- `HandlerFactory` — type alias for the handler factory lambda
- `HandlerContext` — iso context consumed by factories
- `RequestHandler` — embedded in handler actors, hides the connection protocol
- `HandlerReceiver` — lifecycle interface for handler actors (dispose, throttled, unthrottled)
- `BeforeContext` — context for middleware `before` phase
- `AfterContext` — context for middleware `after` phase with header modification
- `StreamingStarted` — returned by `RequestHandler.start_streaming()` on success

