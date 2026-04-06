"""
# Hobby

A simple HTTP web framework for Pony, powered by
[Stallion](https://github.com/ponylang/stallion).

## Quick Start

Create an `Application`, register routes with `.>` chaining, call
`build()` to compile the routes, and pass the result to `Server`:

```pony
use hobby = "hobby"
use stallion = "stallion"
use lori = "lori"

actor Main is hobby.ServerNotify
  let _env: Env

  new create(env: Env) =>
    _env = env
    let auth = lori.TCPListenAuth(env.root)
    let app = hobby.Application
      .> get("/", {(ctx) =>
        hobby.RequestHandler(consume ctx)
          .respond(stallion.StatusOK, "Hello!")
      } val)
      .> get("/greet/:name", {(ctx) =>
        let handler = hobby.RequestHandler(consume ctx)
        try
          handler.respond(stallion.StatusOK,
            "Hello, " + handler.param("name")? + "!")
        else
          handler.respond(
            stallion.StatusBadRequest, "Bad Request")
        end
      } val)

    match app.build()
    | let built: hobby.BuiltApplication =>
      hobby.Server(auth, built, this
        where host = "localhost", port = "8080")
    | let err: hobby.ConfigError =>
      env.err.print(err.message)
    end

  be listening(server: hobby.Server,
    host: String, service: String)
  =>
    _env.out.print(
      "Listening on " + host + ":" + service)
```

## Handler Factories

Routes are registered with a `HandlerFactory` — a `val` lambda that receives
an iso `HandlerContext` and returns an optional `HandlerReceiver tag`.

**Inline handlers** consume the context into a `RequestHandler`, respond
immediately, and return `None`:

```pony
{(ctx) =>
  hobby.RequestHandler(consume ctx)
    .respond(stallion.StatusOK, "Hello!")
} val
```

**Async handlers** create an actor that holds the `RequestHandler` and
responds later (e.g., after a database query). The actor implements
`HandlerReceiver` for lifecycle signals:

```pony
actor MyHandler is hobby.HandlerReceiver
  embed _handler: hobby.RequestHandler

  new create(ctx: hobby.HandlerContext iso, db: Database tag) =>
    _handler = hobby.RequestHandler(consume ctx)
    db.query(this)

  be result(value: String) =>
    _handler.respond(stallion.StatusOK, value)

  be dispose() => None
  be throttled() => None
  be unthrottled() => None
```

Register the factory:
`.> get("/data", {(ctx)(db) => MyHandler(consume ctx, db)} val)`

## Routing

Routes use a segment trie with two kinds of dynamic segments:

- **Named parameters** (`:name`): match a single path segment.
  `/users/:id` matches `/users/42` but not `/users/42/posts`.
- **Wildcard parameters** (`*name`): match everything from that point forward,
  must be the last segment. `/files/*path` matches `/files/css/style.css`.

Static routes have priority over parameter routes at the same position.
Trailing slashes are normalized — `/users/` and `/users` match the same route.

## Request Interceptors

Request interceptors short-circuit requests before the handler is created.
An interceptor returns `InterceptPass` to let the request through or
`InterceptRespond` to reject it — the compiler forces an explicit decision.

```pony
let auth: Array[hobby.RequestInterceptor val] val =
  recover val [as hobby.RequestInterceptor val: AuthInterceptor] end
app.> get("/private", private_factory where interceptors = auth)
```

Application-level interceptors run on every request, including 404s:

```pony
app.> add_request_interceptor(RequiredHeadersInterceptor(
  recover val ["accept"] end))
```

## Response Interceptors

Response interceptors run after the handler responds, before the response
goes to the wire. They can modify status, headers, and body — or perform
read-only side effects like logging. All registered interceptors run in
registration order; there is no short-circuiting.

```pony
class val CorsInterceptor is hobby.ResponseInterceptor
  fun apply(ctx: hobby.ResponseContext ref) =>
    ctx.set_header("access-control-allow-origin", "*")
```

Register at the application, group, or route level:

```pony
app.> add_response_interceptor(CorsInterceptor)
app.> get("/cached", handler
  where response_interceptors = cache_interceptors)
```

For streaming responses, mutations are silently ignored (headers and status
are already on the wire), but the interceptor still runs for logging.

## Route Groups

Group related routes under a shared prefix and interceptors with `RouteGroup`:

```pony
let auth: Array[hobby.RequestInterceptor val] val =
  recover val [as hobby.RequestInterceptor val: AuthInterceptor] end
let api = hobby.RouteGroup("/api" where interceptors = auth)
api.> get("/users", users_factory)
api.> get("/users/:id", user_factory)
app.> group(consume api)
```

Groups can be nested — inner groups inherit the outer group's prefix and
interceptors, with outer interceptors running first.

## Streaming Responses

Send chunked HTTP responses using `RequestHandler.start_streaming()`:

```pony
actor StreamHandler is hobby.HandlerReceiver
  embed _handler: hobby.RequestHandler

  new create(ctx: hobby.HandlerContext iso) =>
    _handler = hobby.RequestHandler(consume ctx)
    match _handler.start_streaming(stallion.StatusOK)
    | hobby.StreamingStarted => _send()
    | stallion.ChunkedNotSupported =>
      _handler.respond(stallion.StatusOK, "Chunked not supported.")
    | hobby.BodyNotNeeded => None
    end

  be _send() =>
    _handler.send_chunk("Hello, ")
    _handler.send_chunk("streaming world!")
    _handler.finish()

  be dispose() => None
  be throttled() => None
  be unthrottled() => None
```

`start_streaming()` returns `StreamingStarted` on success,
`ChunkedNotSupported` for HTTP/1.0 clients, or `BodyNotNeeded` for HEAD
requests. After `StreamingStarted`, call `send_chunk()` to send data and
`finish()` to complete the stream.

## Handler Timeout

`Server` accepts an optional `handler_timeout` parameter (a
`HandlerTimeout` constrained type or `None`). The default is 30 seconds
via `DefaultHandlerTimeout()`. When a handler fails to respond within the
timeout, the framework sends 504 Gateway Timeout. Pass `None` to
disable the timeout.

Construct a custom timeout with `MakeHandlerTimeout(milliseconds)`, which
validates the value (must be > 0, must not overflow when converted to
nanoseconds).

## HTTPS

Use `Server.ssl()` instead of `Server` to listen over TLS. Pass an
`SSLContext val` configured with a certificate and private key:

```pony
use "files"
use hobby = "hobby"
use stallion = "stallion"
use lori = "lori"
use ssl_net = "ssl/net"

actor Main is hobby.ServerNotify
  let _env: Env

  new create(env: Env) =>
    _env = env
    let auth = lori.TCPListenAuth(env.root)
    let file_auth = FileAuth(env.root)
    let sslctx =
      try
        recover val
          ssl_net.SSLContext
            .> set_authority(
              FilePath(file_auth, "cert.pem"))?
            .> set_cert(
              FilePath(file_auth, "cert.pem"),
              FilePath(file_auth, "key.pem"))?
            .> set_client_verify(false)
            .> set_server_verify(false)
        end
      else
        env.err.print("Unable to set up SSL context")
        return
      end

    let app = hobby.Application
      .> get("/", {(ctx) =>
        hobby.RequestHandler(consume ctx)
          .respond(
            stallion.StatusOK,
            "Hello over HTTPS!")
      } val)

    match app.build()
    | let built: hobby.BuiltApplication =>
      hobby.Server.ssl(auth, built, this, sslctx
        where host = "0.0.0.0", port = "8443")
    | let err: hobby.ConfigError =>
      env.err.print(err.message)
    end

  be listening(server: hobby.Server,
    host: String, service: String)
  =>
    _env.out.print(
      "Listening on " + host + ":" + service)
```

If the `SSLContext` is misconfigured (e.g., no certificate set),
`Server.ssl()` starts but every connection fails at TLS handshake
time. These failures are reported via
`ServerNotify.connection_failed()`.

## Static File Serving

Serve files from a directory using the built-in `ServeFiles` handler factory.
Small files are served with `Content-Length`; large files use chunked
streaming. HEAD requests are optimized — `ServeFiles` responds with
`Content-Type` and `Content-Length` headers without reading the file.
Path traversal is prevented by Pony's `FilePath` capability system.

```pony
use "files"
use hobby = "hobby"
use stallion = "stallion"
use lori = "lori"

actor Main is hobby.ServerNotify
  new create(env: Env) =>
    let auth = lori.TCPListenAuth(env.root)
    let root =
      FilePath(FileAuth(env.root), "./public")
    let app = hobby.Application
      .> get(
        "/static/*filepath",
        hobby.ServeFiles(root))

    match app.build()
    | let built: hobby.BuiltApplication =>
      hobby.Server(auth, built, this
        where host = "0.0.0.0", port = "8080")
    | let err: hobby.ConfigError =>
      env.err.print(err.message)
    end
```

Routes must use `*filepath` as the wildcard parameter name. When a request
resolves to a directory, `ServeFiles` automatically serves `index.html`.

## Imports

Users import up to five packages:

- **`hobby`**: Application, BodyNotNeeded, BuildResult, BuiltApplication,
  ConfigError, ContentTypes, CookieSigningKey, DefaultHandlerTimeout,
  HandlerContext, HandlerFactory, HandlerReceiver, HandlerTimeout,
  HandlerTimeoutValidator, InterceptPass, InterceptRespond, InterceptResult,
  InvalidSignature, MakeHandlerTimeout, MalformedSignedValue,
  RequestHandler, RequestInterceptor, ResponseContext, ResponseInterceptor,
  RouteGroup, ServeFiles, Server, ServerNotify, SignedCookie,
  SignedCookieError, StreamingStarted
- **`stallion`**: HTTP vocabulary (Status codes, Method, Headers, ServerConfig,
  ChunkedNotSupported)
- **`lori`**: `TCPListenAuth(env.root)` for network access
- **`ssl/net`**: `SSLContext` (only needed when using `Server.ssl()`)
- **`files`**: `FilePath`, `FileAuth` (needed for `ServeFiles` and
  `Server.ssl()` certificate loading)
"""

