# hobby

A simple HTTP web framework for Pony, inspired by [Jennet](https://github.com/Theodus/jennet) and powered by [Stallion](https://github.com/ponylang/stallion).

Design: https://github.com/ponylang/hobby/discussions/2
Static file serving design: https://github.com/ponylang/hobby/discussions/18
Actor-per-request design: https://github.com/ponylang/hobby/discussions/41

## Building and Testing

```bash
make ssl=3.0.x          # build tests + examples (release, OpenSSL 3.x)
make test ssl=3.0.x     # same as above
make test-one t=TestName ssl=3.0.x  # run a single test by name
make ssl=libressl       # use LibreSSL (CI uses this)
make config=debug       # debug build (combine with ssl=...)
make examples ssl=3.0.x # examples only
make clean              # clean build artifacts + corral cache
```

The `ssl` option is required — Stallion transitively depends on the `ssl` package. Valid values: `3.0.x` (OpenSSL 3.x), `1.1.x` (OpenSSL 1.1.x), `libressl` (LibreSSL).

`make test` runs unit tests, integration tests, and builds examples. `make unit-tests` and `make integration-tests` can be run individually.

## Dependencies

- **Stallion** (0.5.1): HTTP/1.x server built on lori. Provides `HTTPServerActor`, `HTTPServer`, `Responder`, `ResponseBuilder`, `Request`, `ServerConfig`, `Status`, `Method`, `Headers`, `Header`, `StartChunkedResponseResult`, `StreamingStarted`, `AlreadyResponded`, `ChunkedNotSupported`. Also provides cookie support (`RequestCookie`, `RequestCookies`, `ParseCookies`, `SetCookie`, `SetCookieBuilder`, `SetCookieBuildError`, `SameSite`/`SameSiteStrict`/`SameSiteLax`/`SameSiteNone`) and content negotiation (`MediaType`, `NoAcceptableType`, `ContentNegotiationResult`, `ContentNegotiation`).
- **lori** (transitive via Stallion): TCP layer. Provides `TCPListenerActor`, `TCPListener`, `TCPConnectionActor`, `TCPConnection`, auth types.
- **uri** (transitive via Stallion): URI parsing. Used to read `request.uri.path`.
- **ssl** (transitive via Stallion): SSL/TLS support. Requires an SSL version flag at build time (`ssl=3.0.x`, `ssl=1.1.x`, or `ssl=libressl`).

## Architecture

### Public API

Users interact with these types:

- **`Application`** (`class iso`): Route registration via `.>` chaining (`get`, `post`, etc.), `group()` for route groups, `add_middleware()` for app-level middleware. `serve()` consumes the Application, freezes routes into an immutable router, and starts listening. `handler_timeout` parameter on `serve()` controls inactivity timeout (default 30 seconds, `None` to disable).
- **`RouteGroup`** (`class iso`): Groups routes under a shared prefix and optional middleware. Supports nesting via `group()`. Consumed by `Application.group()` or outer `RouteGroup.group()`.
- **`HandlerFactory`** (type alias): `{(HandlerContext iso): (HandlerReceiver tag | None)} val`. Route handler entry point. Returns `None` for inline handlers, or a `HandlerReceiver tag` for async handlers that need lifecycle signals.
- **`HandlerContext`** (`class iso`): Request context consumed by the handler factory. Carries `request`, `params`, `body`, and `data` (from before-middleware). Created by `_Connection` and passed to the factory.
- **`RequestHandler`** (`class ref`): Embedded in handler actors. Created from a consumed `HandlerContext iso`. Provides `respond()`, `respond_with_headers()`, `start_streaming()`, `send_chunk()`, `finish()`, `param()`, `body()`, `get[T]()`, `request()`, `is_head()`.
- **`HandlerReceiver`** (`interface tag`): Lifecycle notifications from the connection to a handler actor. Behaviors: `dispose()`, `throttled()`, `unthrottled()`.
- **`Middleware`** (`interface val`): Two-phase processor. `before(ctx: BeforeContext ref) ?` runs before the handler; `after(ctx: AfterContext ref)` runs after, in reverse order.
- **`BeforeContext`** (`class ref`): Context for the `before` phase. Provides `respond()`, `respond_with_headers()`, `is_handled()`, `request()`, `param()`, `body()`, `set()`, `get()`.
- **`AfterContext`** (`class ref`): Context for the `after` phase. Provides `status()`, `body()`, `set_header()`, `add_header()`, `is_streaming()`, `request()`.
- **`StreamingStarted`** (`primitive`): Returned by `RequestHandler.start_streaming()` on success.
- **`BodyNotNeeded`** (`primitive`): Returned by `RequestHandler.start_streaming()` for HEAD requests.
- **`ContentTypes`** (`class val`): File extension to MIME content type mapping. Ships with 17 common defaults. Chain `.add()` calls to add or override mappings.
- **`ServeFiles`** (`class val`): Built-in handler factory for serving static files. Structurally matches `HandlerFactory`. Small files served inline; large files streamed via `_ServeFilesHandler` actor. Includes caching headers and conditional request support per RFC 7232.

### Internal layers

- **`_Listener`** (`actor`): Implements `lori.TCPListenerActor`. Accepts TCP connections and spawns `_Connection` actors. Creates a shared `Timers` actor for handler timeout management.
- **`_Connection`** (`actor`): Implements `stallion.HTTPServerActor` and `_ConnectionProtocol`. State machine: `_Idle` → `_HandlerInProgress` → `_Streaming`. Runs before-middleware synchronously, calls factory, receives handler responses via protocol behaviors (`_handler_respond`, `_handler_start_streaming`, `_handler_send_chunk`, `_handler_finish`). Buffers responses for after-middleware modification. Manages handler timeout via interval-based timer.
- **`_ConnectionProtocol`** (`trait tag`): Protocol behaviors that `RequestHandler` sends to `_Connection`.
- **`_BufferedResponse`** (`class ref`): Mutable response buffer for after-middleware. After-middleware modifies headers via `AfterContext`, then `_Connection` serializes to wire.
- **`_RunBeforeMiddleware`** (`primitive`): Runs middleware `before` phases on `BeforeContext ref`. Returns invoked count.
- **`_RunAfterMiddleware`** (`primitive`): Runs middleware `after` phases in reverse on `AfterContext ref`.
- **`_HandlerTimeoutNotify`** (`class iso is TimerNotify`): Sends `_handler_timeout(token)` to `_Connection` on each interval fire.
- **`_Router`** (`class val`): Immutable radix tree router. One tree per HTTP method.
- **`_FileStreamer`** (`actor`): Reads files in 64 KB chunks. Sends to `_FileTarget tag`. Supports backpressure via `pause()`/`resume()`.
- **`_ServeFilesHandler`** (`actor`): Handler actor for large file streaming. Implements `HandlerReceiver` and `_FileTarget`. Receives file chunks from `_FileStreamer` and forwards through `RequestHandler`. Forwards `throttled()`/`unthrottled()` to `_FileStreamer` as `pause()`/`resume()`.
- **`_FileTarget`** (`trait tag`): Internal interface for `_FileStreamer` to send to.

### Key design decisions

- **Actor-per-request handler model**: Each request's handler factory can spawn an actor that does async work and responds when ready. The connection waits for a response via protocol behaviors. This enables database queries, external service calls, and other async patterns without blocking the connection.
- **Factory returns `(HandlerReceiver tag | None)`**: Inline handlers return None; async handlers return the actor's tag for dispose/throttle signals. No timing gap for lifecycle signals.
- **Before-middleware data map → HandlerContext**: The mutable ref map is copied to a val map via `_freeze_data()`, which is sendable inside the `recover iso` block for `HandlerContext`.
- **Response buffering for after-middleware**: Responses are buffered in `_BufferedResponse` before going to the wire. After-middleware can modify headers. For streaming, after-middleware runs after `_handler_finish` with header writes as no-ops.
- **Route methods are `fun ref`**: Auto receiver recovery handles calling them on the `iso` Application since all arguments are `val`. `serve()` is `fun iso` and uses `consume this`.
- **Build/lookup separation**: Mutable `_BuildNode ref` trees for construction, frozen into immutable `_TreeNode val` trees for lookup.
- **Static priority**: Static children checked before param child during lookup.
- **Trailing slash normalization**: `/users/` and `/users` match the same route.
- **Flatten at registration time**: Route groups are flattened when consumed by `group()`.
- **Interval-based handler timeout**: Uses a repeating timer that checks a `_last_handler_activity` timestamp rather than cancel+recreate on every chunk. Avoids per-chunk timer allocation overhead during streaming.
- **Pipelined request buffering**: Requests arriving during `_HandlerInProgress` or `_Streaming` are buffered and drained when the handler completes.
- **HEAD via split handling**: `RequestHandler.start_streaming()` returns `BodyNotNeeded` for HEAD (local check). `_Connection` uses `is_head` when building buffered responses for the wire (suppresses body, preserves Content-Length).
- **HEAD→GET fallback**: When no explicit HEAD route is registered, `_Connection` retries the lookup with GET.
- **Backpressure forwarding**: `_Connection` forwards `on_throttled()`/`on_unthrottled()` to the handler actor when one is registered.
- **Directory index auto-serving**: When a request resolves to a directory, `ServeFiles` tries `index.html`. Content type is derived from the resolved filesystem path.

## File Layout

```
docs/
  middleware-guide.md         - Writing Middleware tutorial guide
hobby/
  hobby.pony                  - Package docstring
  handler_factory.pony        - HandlerFactory type alias (public)
  handler_context.pony        - HandlerContext class (public)
  request_handler.pony        - RequestHandler class (public)
  handler_receiver.pony       - HandlerReceiver interface (public)
  before_context.pony         - BeforeContext class (public)
  after_context.pony          - AfterContext class (public)
  streaming_started.pony      - StreamingStarted primitive (public)
  body_not_needed.pony        - BodyNotNeeded primitive (public)
  middleware.pony              - Middleware interface (public)
  application.pony            - Application class (public)
  route_group.pony            - RouteGroup class (public)
  serve_files.pony            - ServeFiles handler factory (public)
  content_types.pony          - ContentTypes class + defaults (public)
  _connection_protocol.pony   - Connection protocol trait (internal)
  _buffered_response.pony     - Response buffer for after-middleware (internal)
  _run_before_middleware.pony  - Before-phase execution (internal)
  _run_after_middleware.pony   - After-phase execution (internal)
  _handler_timeout.pony       - Handler timeout timer notify (internal)
  _connection.pony             - Connection actor (internal)
  _listener.pony               - Listener actor (internal)
  _router.pony                 - Router + radix tree (internal)
  _route_match.pony            - Route match result type (internal)
  _route_definition.pony       - Route definition for building (internal)
  _file_streamer.pony          - Chunked file reader actor (internal)
  _file_target.pony            - File target trait (internal)
  _serve_files_handler.pony    - ServeFiles handler actor (internal)
  _http_date.pony              - RFC 7231 HTTP-date formatting (internal)
  _etag.pony                   - Weak ETag computation and matching (internal)
  _flatten.pony                - Path joining + middleware concatenation (internal)
  _mort.pony                   - _Unreachable primitive (internal)
  _test.pony                   - Test runner
  _test_router.pony            - Router property-based + example tests
  _test_route_group.pony       - Route group unit + property tests
  _test_content_type.pony      - Content type mapping property + example tests
  _test_http_date.pony         - HTTP date formatting property + example tests
  _test_etag.pony              - ETag computation and matching property + example tests
  _test_request_handler.pony   - RequestHandler unit tests with mock connection
  _test_integration.pony       - HTTP round-trip integration tests
  _test_serve_files.pony       - ServeFiles integration tests
```

## Conventions

- Private types (`_` prefix) are package-private, accessible within `hobby/` but not externally.
- All public API elements have docstrings.
- `_Unreachable()` is used in `else` branches of `try` blocks where the error path is impossible due to prior bounds checks. Do not use it in `match` expressions — Pony's `match` performs exhaustiveness checking on union types, so an `else` branch on a fully-covered union is a compile error.
- All test classes, primitives, and actors have `\nodoc\` on the declaration line (e.g., `primitive \nodoc\ _TestFoo`).
- Integration tests use `label(): String => "integration"` for selective execution.
- WSL2 compatibility: integration tests use `127.0.0.2` on Linux to avoid the Hyper-V mirrored networking bug (see ponylang/lori#153).
