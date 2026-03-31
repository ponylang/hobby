# hobby

An HTTP server framework for Pony, powered by [Stallion](https://github.com/ponylang/stallion).

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

- **Stallion** (0.5.2): HTTP/1.x server built on lori. Provides `HTTPServerActor`, `HTTPServer`, `Responder`, `ResponseBuilder`, `Request`, `ServerConfig`, `Status`, `Method`, `Headers`, `Header`, `StartChunkedResponseResult`, `StreamingStarted`, `AlreadyResponded`, `ChunkedNotSupported`. Also provides cookie support (`RequestCookie`, `RequestCookies`, `ParseCookies`, `SetCookie`, `SetCookieBuilder`, `SetCookieBuildError`, `SameSite`/`SameSiteStrict`/`SameSiteLax`/`SameSiteNone`) and content negotiation (`MediaType`, `NoAcceptableType`, `ContentNegotiationResult`, `ContentNegotiation`).
- **lori** (transitive via Stallion): TCP layer. Provides `TCPListenerActor`, `TCPListener`, `TCPConnectionActor`, `TCPConnection`, auth types.
- **uri** (transitive via Stallion): URI parsing. Used to read `request.uri.path`.
- **ssl** (2.0.1): SSL/TLS and cryptography. Also available transitively via Stallion. Direct dependency for signed cookie code — provides `ssl/crypto` subpackage (`HmacSha256`, `ConstantTimeCompare`, `RandBytes`). Requires an SSL version flag at build time (`ssl=3.0.x`, `ssl=1.1.x`, or `ssl=libressl`).

## Architecture

### Public API

Users interact with these types:

- **`Application`** (`class iso`): Route registration via `.>` chaining (`get`, `post`, etc.), `group()` for route groups, `add_request_interceptor()` for app-level request interceptors, `add_response_interceptor()` for app-level response interceptors. Route methods accept optional `response_interceptors` parameter. `serve()` consumes the Application, freezes routes into an immutable router, and starts listening. `handler_timeout` parameter on `serve()` controls inactivity timeout (default 30 seconds, `None` to disable).
- **`RouteGroup`** (`class iso`): Groups routes under a shared prefix and optional response interceptors. Constructor accepts `response_interceptors` parameter. Supports nesting via `group()`. Consumed by `Application.group()` or outer `RouteGroup.group()`.
- **`RequestInterceptor`** (`interface val`): Synchronous request gate. `apply(request: Request box): InterceptResult` returns `InterceptPass` or `InterceptRespond`. The return type forces an explicit decision — the compiler won't accept an interceptor that forgets to decide. The first interceptor that responds wins.
- **`InterceptResult`** (type alias): `(InterceptPass | InterceptRespond)`. Return type for request interceptors.
- **`InterceptPass`** (`primitive`): Returned by an interceptor to pass the request through.
- **`InterceptRespond`** (`class ref`): Returned by an interceptor to short-circuit with an HTTP response. The handler is not created. Constructed with `(status, body)`. Provides `set_header()` and `add_header()` for adding response headers.
- **`ResponseInterceptor`** (`interface val`): Synchronous response interceptor. `fun apply(ctx: ResponseContext ref)` runs after the handler responds. All interceptors run in forward order.
- **`ResponseContext`** (`class ref`): Context passed to response interceptors. Reads: `status()`, `body()`, `is_streaming()`, `request()`. Writes: `set_status()`, `set_header()`, `add_header()`, `set_body()`. All writes are no-ops for streaming responses. Package-private constructor.
- **`HandlerFactory`** (type alias): `{(HandlerContext iso): (HandlerReceiver tag | None)} val`. Route handler entry point. Returns `None` for inline handlers, or a `HandlerReceiver tag` for async handlers that need lifecycle signals.
- **`HandlerContext`** (`class iso`): Request context consumed by the handler factory. Carries `request`, `params`, and `body`. Created by `_Connection` and passed to the factory.
- **`RequestHandler`** (`class ref`): Embedded in handler actors. Created from a consumed `HandlerContext iso`. Provides `respond()`, `respond_with_headers()`, `start_streaming()`, `send_chunk()`, `finish()`, `param()`, `body()`, `request()`, `is_head()`.
- **`HandlerReceiver`** (`interface tag`): Lifecycle notifications from the connection to a handler actor. Behaviors: `dispose()`, `throttled()`, `unthrottled()`.
- **`StreamingStarted`** (`primitive`): Returned by `RequestHandler.start_streaming()` on success.
- **`BodyNotNeeded`** (`primitive`): Returned by `RequestHandler.start_streaming()` for HEAD requests.
- **`ContentTypes`** (`class val`): File extension to MIME content type mapping. Ships with 17 common defaults. Chain `.add()` calls to add or override mappings.
- **`ServeFiles`** (`class val`): Built-in handler factory for serving static files. Structurally matches `HandlerFactory`. Small files served inline; large files streamed via `_ServeFilesHandler` actor. Includes caching headers and conditional request support per RFC 7232.
- **`CookieSigningKey`** (`class val`): HMAC-SHA256 signing key for use with `SignedCookie`. 32-byte minimum. `create` wraps existing key bytes, `generate` creates a random key. `_bytes()` is package-private.
- **`SignedCookie`** (`primitive`): Signs and verifies cookie values using HMAC-SHA256. `sign` produces `value.base64url(hmac)` format. `verify` returns the original value or a `SignedCookieError`.
- **`SignedCookieError`** (type alias): `(MalformedSignedValue | InvalidSignature)`. Error union for `SignedCookie.verify`.
- **`MalformedSignedValue`** (`primitive`): Structurally invalid signed value (missing separator or invalid base64).
- **`InvalidSignature`** (`primitive`): Signature did not match (tampered or wrong key).

### Internal layers

- **`_Listener`** (`actor`): Implements `lori.TCPListenerActor`. Accepts TCP connections and spawns `_Connection` actors. Creates a shared `Timers` actor for handler timeout management.
- **`_Connection`** (`actor`): Implements `stallion.HTTPServerActor` and `_ConnectionProtocol`. State machine: `_Idle` → `_HandlerInProgress` → `_Streaming`. Runs request interceptors, calls factory, receives handler responses via protocol behaviors (`_handler_respond`, `_handler_start_streaming`, `_handler_send_chunk`, `_handler_finish`). Buffers responses for response interceptors → wire. Manages handler timeout via interval-based timer.
- **`_ConnectionProtocol`** (`trait tag`): Protocol behaviors that `RequestHandler` sends to `_Connection`.
- **`_BufferedResponse`** (`class ref`): Mutable response buffer for response interceptors. Response interceptors modify status, headers, and body via `ResponseContext`; `_build()` serializes to wire and auto-adds Content-Length from the final body.
- **`_RunRequestInterceptors`** (`primitive`): Runs request interceptors in order. Returns `InterceptRespond` on first short-circuit, `None` if all pass.
- **`_RunResponseInterceptors`** (`primitive`): Runs response interceptors in forward order on a `ResponseContext ref`.
- **`_HandlerTimeoutNotify`** (`class iso is TimerNotify`): Sends `_handler_timeout(token)` to `_Connection` on each interval fire.
- **`_Router`** (`class val`): Immutable radix tree router. One tree per HTTP method.
- **`_FileStreamer`** (`actor`): Reads files in 64 KB chunks. Sends to `_FileTarget tag`. Supports backpressure via `pause()`/`resume()`.
- **`_ServeFilesHandler`** (`actor`): Handler actor for large file streaming. Implements `HandlerReceiver` and `_FileTarget`. Receives file chunks from `_FileStreamer` and forwards through `RequestHandler`. Forwards `throttled()`/`unthrottled()` to `_FileStreamer` as `pause()`/`resume()`.
- **`_FileTarget`** (`trait tag`): Internal interface for `_FileStreamer` to send to.

### Key design decisions

- **Actor-per-request handler model**: Each request's handler factory can spawn an actor that does async work and responds when ready. The connection waits for a response via protocol behaviors. This enables database queries, external service calls, and other async patterns without blocking the connection.
- **Factory returns `(HandlerReceiver tag | None)`**: Inline handlers return None; async handlers return the actor's tag for dispose/throttle signals. No timing gap for lifecycle signals.
- **Response buffering for response interceptors**: Responses are buffered in `_BufferedResponse` before going to the wire. Response interceptors modify status, headers, and body via `ResponseContext`. Content-Length is computed automatically by `_build()` from the final body after all interceptors run. For streaming, interceptors run but mutations are no-ops (headers/status already on wire).
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
- **Request interceptors run before the handler**: Interceptors execute in `_Connection._dispatch` after route lookup. An interceptor short-circuit sends the response (with response interceptors applied) without creating the handler.
- **Response interceptors run on all response paths**: Response interceptors run after the handler responds and before the wire. For routed requests, the full concatenated array (app + group + route) from `_RouteMatch` is used. For 404s, app-level response interceptors (passed through `_Listener`) run. Exception: streaming timeout closes the connection directly.
- **Content-Length deferred to serialization**: `_BufferedResponse._build()` auto-adds Content-Length from the final body after all response interceptors have run. Interceptors that call `set_body()` get correct Content-Length automatically. If Content-Length is already present (from explicit user headers), `_build()` does not override it.
- **REVISIT: response interceptor mutators on streaming responses**: `set_body()`, `set_status()`, `set_header()`, and `add_header()` on `ResponseContext` are silent no-ops for streaming responses. The no-op behavior is correct (headers/status are already on the wire, body chunks are already sent), but `set_body()` being callable but silently ignored for streaming is a confusing API. Revisit whether the type system can make this a compile-time distinction rather than a runtime no-op.

## File Layout

```
docs/
  interceptor-guide.md        - Writing Request Interceptors tutorial guide
hobby/
  hobby.pony                  - Package docstring
  handler_factory.pony        - HandlerFactory type alias (public)
  handler_context.pony        - HandlerContext class (public)
  request_handler.pony        - RequestHandler class (public)
  handler_receiver.pony       - HandlerReceiver interface (public)
  streaming_started.pony      - StreamingStarted primitive (public)
  body_not_needed.pony        - BodyNotNeeded primitive (public)
  request_interceptor.pony     - RequestInterceptor interface (public)
  response_interceptor.pony    - ResponseInterceptor interface (public)
  response_context.pony        - ResponseContext class (public)
  intercept_response.pony      - InterceptRespond class + result types (public)
  application.pony            - Application class (public)
  route_group.pony            - RouteGroup class (public)
  serve_files.pony            - ServeFiles handler factory (public)
  content_types.pony          - ContentTypes class + defaults (public)
  cookie_signing_key.pony     - CookieSigningKey class (public)
  signed_cookie.pony          - SignedCookie primitive (public)
  signed_cookie_error.pony    - SignedCookieError union type (public)
  _connection_protocol.pony   - Connection protocol trait (internal)
  _buffered_response.pony     - Response buffer for response interceptors (internal)
  _run_request_interceptors.pony - Request interceptor execution (internal)
  _run_response_interceptors.pony - Response interceptor execution (internal)
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
  _flatten.pony                - Path joining + array concatenation (internal)
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
  _test_request_interceptor.pony - Request interceptor unit + integration tests
  _test_response_interceptor.pony - Response interceptor unit + integration tests
  _test_signed_cookie.pony     - Signed cookie unit + property tests
```

## Conventions

- Private types (`_` prefix) are package-private, accessible within `hobby/` but not externally.
- All public API elements have docstrings.
- `_Unreachable()` is used in `else` branches of `try` blocks where the error path is impossible due to prior bounds checks. Do not use it in `match` expressions — Pony's `match` performs exhaustiveness checking on union types, so an `else` branch on a fully-covered union is a compile error.
- All test classes, primitives, and actors have `\nodoc\` on the declaration line (e.g., `primitive \nodoc\ _TestFoo`).
- Integration tests use `label(): String => "integration"` for selective execution.
- WSL2 compatibility: integration tests use `127.0.0.2` on Linux to avoid the Hyper-V mirrored networking bug (see ponylang/lori#153).
