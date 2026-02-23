"""
# Hobby

A simple HTTP web framework for Pony, powered by
[Stallion](https://github.com/ponylang/stallion).

## Quick Start

Create an `Application`, register routes with `.>` chaining, and call
`serve()` to start listening:

```pony
use hobby = "hobby"
use stallion = "stallion"
use lori = "lori"

actor Main
  new create(env: Env) =>
    let auth = lori.TCPListenAuth(env.root)
    hobby.Application
      .>get("/", HelloHandler)
      .>get("/greet/:name", GreetHandler)
      .serve(auth, stallion.ServerConfig("localhost", "8080"), env.out)

primitive HelloHandler is hobby.Handler
  fun apply(ctx: hobby.Context ref) =>
    ctx.respond(stallion.StatusOK, "Hello!")

class val GreetHandler is hobby.Handler
  fun apply(ctx: hobby.Context ref) ? =>
    ctx.respond(stallion.StatusOK, "Hello, " + ctx.param("name")? + "!")
```

## Routing

Routes use a radix tree with two kinds of dynamic segments:

- **Named parameters** (`:name`): match a single path segment.
  `/users/:id` matches `/users/42` but not `/users/42/posts`.
- **Wildcard parameters** (`*name`): match everything from that point forward,
  must be the last segment. `/files/*path` matches `/files/css/style.css`.

Static routes have priority over parameter routes at the same position.
Trailing slashes are normalized — `/users/` and `/users` match the same route.

## Middleware

Attach middleware to individual routes via the `middleware` parameter:

```pony
let mw: Array[hobby.Middleware val] val =
  recover val [as hobby.Middleware val: AuthMiddleware] end
app.>get("/private", PrivateHandler where middleware = mw)
```

Middleware has two phases:

- **`before`**: runs before the handler. Short-circuit a request by calling
  `ctx.respond()` — the handler is skipped, but `after` phases still run.
- **`after`**: runs after the handler in reverse order. Always runs for every
  middleware whose `before` was invoked, regardless of how the chain ended.

## Route Groups

Group related routes under a shared prefix and middleware with `RouteGroup`:

```pony
let auth_mw: Array[hobby.Middleware val] val =
  recover val [as hobby.Middleware val: AuthMiddleware] end
let api = hobby.RouteGroup("/api" where middleware = auth_mw)
api.>get("/users", UsersHandler)
api.>get("/users/:id", UserHandler)
app.>group(consume api)
```

Groups can be nested — inner groups inherit the outer group's prefix and
middleware, with outer middleware running first:

```pony
let admin = hobby.RouteGroup("/admin" where middleware = admin_mw)
admin.get("/dashboard", DashboardHandler)
api.>group(consume admin)
// Registers /api/admin/dashboard with [auth_mw, admin_mw]
```

## Application Middleware

Apply middleware to every route with `Application.add_middleware()`:

```pony
let log_mw: Array[hobby.Middleware val] val =
  recover val [as hobby.Middleware val: LogMiddleware(env.out)] end
hobby.Application
  .>add_middleware(log_mw)
  .>get("/", HelloHandler)
  .>group(consume api)
  .serve(auth, config, env.out)
```

Application middleware runs before group middleware, which runs before
per-route middleware. Can be called multiple times — middleware accumulates
in registration order.

## Context Data

Middleware communicates with handlers through `ctx.set()` / `ctx.get()`.
The data map stores `Any val` values. Middleware authors should provide typed
accessor primitives that use `match` to recover domain types, following the
convention demonstrated in the middleware example.

## Streaming Responses

Send chunked HTTP responses by calling `ctx.start_streaming()` to get a
`StreamSender`:

```pony
primitive StreamHandler is hobby.Handler
  fun apply(ctx: hobby.Context ref) =>
    let sender = ctx.start_streaming(stallion.StatusOK)
    MyProducer(sender)

actor MyProducer
  let _sender: hobby.StreamSender tag

  new create(sender: hobby.StreamSender tag) =>
    _sender = sender
    _send()

  be _send() =>
    _sender.send_chunk("Hello, ")
    _sender.send_chunk("streaming world!")
    _sender.finish()
```

If the handler errors after starting a stream, the framework automatically
terminates the chunked response to prevent a hung connection.

## Imports

Users import three packages:

- **`hobby`**: Application, Context, Handler, Middleware, RouteGroup, StreamSender
- **`stallion`**: HTTP vocabulary (Status codes, Method, Headers, ServerConfig)
- **`lori`**: `TCPListenAuth(env.root)` for network access
"""
