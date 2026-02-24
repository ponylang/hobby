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

Send chunked HTTP responses by calling `ctx.start_streaming()` and matching
on the result:

```pony
primitive StreamHandler is hobby.Handler
  fun apply(ctx: hobby.Context ref) ? =>
    match ctx.start_streaming(stallion.StatusOK)?
    | let sender: hobby.StreamSender tag =>
      MyProducer(sender)
    | stallion.ChunkedNotSupported =>
      ctx.respond(stallion.StatusOK, "Chunked encoding not supported.")
    | hobby.BodyNotNeeded => None
    end

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

`start_streaming()` is partial — it errors if a response has already been
sent. It returns `(StreamSender tag | ChunkedNotSupported | BodyNotNeeded)`
so handlers can fall back to a non-streaming response when the client doesn't
support chunked encoding (e.g., HTTP/1.0), or skip streaming entirely for
HEAD requests (`BodyNotNeeded`). Existing handlers that don't match on
`BodyNotNeeded` work correctly — in a statement-position match, unmatched
cases silently fall through. If the handler errors after a successful
`start_streaming()`, the framework automatically terminates the chunked
response to prevent a hung connection.

## Static File Serving

Serve files from a directory using the built-in `ServeFiles` handler. Small
files are served with `Content-Length`; large files use chunked streaming.
HEAD requests are optimized — `ServeFiles` responds with `Content-Type` and
`Content-Length` headers without reading the file, regardless of file size.
Path traversal is prevented by Pony's `FilePath` capability system.

```pony
use "files"
use hobby = "hobby"
use stallion = "stallion"
use lori = "lori"

actor Main
  new create(env: Env) =>
    let auth = lori.TCPListenAuth(env.root)
    let root = FilePath(FileAuth(env.root), "./public")
    hobby.Application
      .>get("/static/*filepath", hobby.ServeFiles(root))
      .serve(auth, stallion.ServerConfig("0.0.0.0", "8080"), env.out)
```

Routes must use `*filepath` as the wildcard parameter name. `ServeFiles`
detects content types from file extensions. When a request resolves to a
directory, `ServeFiles` automatically serves `index.html` from that
directory if it exists; otherwise the request returns 404. For HTTP/1.0
clients requesting files above the chunk threshold, it responds with 505
rather than loading the entire file into memory.

The `chunk_threshold` parameter (in kilobytes) controls the cutoff between
serving a file in one response vs chunked streaming. Default is 1024 (1 MB):

```pony
// Stream files at or above 256 KB instead of the default 1 MB
hobby.ServeFiles(root where chunk_threshold = 256)
```

## Imports

Users import three packages:

- **`hobby`**: Application, BodyNotNeeded, Context, Handler, Middleware,
  RouteGroup, ServeFiles, StreamSender
- **`stallion`**: HTTP vocabulary (Status codes, Method, Headers, ServerConfig,
  ChunkedNotSupported)
- **`lori`**: `TCPListenAuth(env.root)` for network access
- **`files`**: `FilePath`, `FileAuth` (only needed when using `ServeFiles`)
"""
