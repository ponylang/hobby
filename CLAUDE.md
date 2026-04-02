# hobby

An HTTP server framework for Pony, powered by [Stallion](https://github.com/ponylang/stallion).

Design: https://github.com/ponylang/hobby/discussions/2
Static file serving design: https://github.com/ponylang/hobby/discussions/18
Actor-per-request design: https://github.com/ponylang/hobby/discussions/41
Shared path tree design: https://github.com/ponylang/hobby/discussions/58

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

- **`Application`** (`class iso`): Route registration via `.>` chaining (`get`, `post`, etc.), `group()` for route groups, `add_request_interceptor()` for app-level request interceptors, `add_response_interceptor()` for app-level response interceptors. Route methods accept optional `response_interceptors` parameter. `serve()` consumes the Application, validates configuration, freezes routes into an immutable router, and starts listening. Returns `ServeResult` — `Serving` on success or `ConfigError` with a description of the problem. `handler_timeout` parameter on `serve()` controls inactivity timeout (default 30 seconds, `None` to disable).
- **`Serving`** (`primitive`): Returned by `serve()` when the server started successfully.
- **`ConfigError`** (`class val`): Returned by `serve()` when a configuration error prevented startup. Carries a `message: String` describing the error. Detected errors: overlapping group prefixes, empty group prefix, special characters in group prefix, conflicting param names.
- **`ServeResult`** (type alias): `(Serving | ConfigError)`. Return type of `serve()`.
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
- **`_Connection`** (`actor`): Implements `stallion.HTTPServerActor` and `_ConnectionProtocol`. State machine: `_Idle` → `_HandlerInProgress` → `_Streaming`. Matches on `(_RouteMatch | _RouteMiss | _MethodNotAllowed)` from router lookup. On match: runs request interceptors, calls factory, receives handler responses via protocol behaviors. On miss: runs accumulated request interceptors (may short-circuit), then sends 404 with accumulated response interceptors. On method-not-allowed: runs accumulated interceptors, then sends 405 with `Allow` header. Manages handler timeout via interval-based timer.
- **`_ConnectionProtocol`** (`trait tag`): Protocol behaviors that `RequestHandler` sends to `_Connection`.
- **`_BufferedResponse`** (`class ref`): Mutable response buffer for response interceptors. Response interceptors modify status, headers, and body via `ResponseContext`; `_build()` serializes to wire and auto-adds Content-Length from the final body.
- **`_RunRequestInterceptors`** (`primitive`): Runs request interceptors in order. Returns `InterceptRespond` on first short-circuit, `None` if all pass.
- **`_RunResponseInterceptors`** (`primitive`): Runs response interceptors in forward order on a `ResponseContext ref`.
- **`_HandlerTimeoutNotify`** (`class iso is TimerNotify`): Sends `_handler_timeout(token)` to `_Connection` on each interval fire.
- **`_Router`** (`class val`): Immutable single shared path tree router. Handlers are keyed by HTTP method at leaf nodes. Interceptors are path-scoped on shared nodes.
- **`_RouterBuilder`** (`class ref`): Mutable builder. `add()` registers routes, `add_interceptors()` tags path nodes with group/app interceptors. `build()` freezes into `_Router`.
- **`_BuildNode`** / **`_TreeNode`** (`class ref` / `class val`): Mutable build-time and immutable lookup-time segment trie nodes. Each node represents one path segment. Children are keyed by full segment name (`Map[String, ...]`). Each node carries path-level interceptors and method-keyed handler entries.
- **`_MethodEntry`** (`class val`): Handler factory + final pre-computed interceptor arrays for a specific HTTP method at a path node.
- **`_BuildMethodEntry`** (`class ref`): Mutable method entry during construction, before freeze-time interceptor concatenation.
- **`_RouteMatch`** (`class val`): Successful lookup result — factory, interceptors, params.
- **`_RouteMiss`** (`class val`): Failed lookup result (path doesn't exist) — carries accumulated interceptors from deepest reached node for 404 interceptor execution.
- **`_MethodNotAllowed`** (`class val`): Path exists but method doesn't match — carries allowed methods list and accumulated interceptors for 405 response with `Allow` header.
- **`_GroupInfo`** (`class val`): Group metadata (prefix + interceptors) preserved for tree building. Created during `group()`, consumed by `serve()`.
- **`_FileStreamer`** (`actor`): Reads files in 64 KB chunks. Sends to `_FileTarget tag`. Supports backpressure via `pause()`/`resume()`.
- **`_ServeFilesHandler`** (`actor`): Handler actor for large file streaming. Implements `HandlerReceiver` and `_FileTarget`. Receives file chunks from `_FileStreamer` and forwards through `RequestHandler`. Forwards `throttled()`/`unthrottled()` to `_FileStreamer` as `pause()`/`resume()`.
- **`_FileTarget`** (`trait tag`): Internal interface for `_FileStreamer` to send to.

### Key design decisions

- **Actor-per-request handler model**: Each request's handler factory can spawn an actor that does async work and responds when ready. The connection waits for a response via protocol behaviors. This enables database queries, external service calls, and other async patterns without blocking the connection.
- **Factory returns `(HandlerReceiver tag | None)`**: Inline handlers return None; async handlers return the actor's tag for dispose/throttle signals. No timing gap for lifecycle signals.
- **Response buffering for response interceptors**: Responses are buffered in `_BufferedResponse` before going to the wire. Response interceptors modify status, headers, and body via `ResponseContext`. Content-Length is computed automatically by `_build()` from the final body after all interceptors run. For streaming, interceptors run but mutations are no-ops (headers/status already on wire).
- **Route methods are `fun ref`**: Auto receiver recovery handles calling them on the `iso` Application since all arguments are `val`. `serve()` is `fun iso` and uses `consume this`.
- **Single shared path tree**: One segment trie for all HTTP methods. Handlers are keyed by method at leaf nodes. Interceptors live on shared path nodes and are method-independent.
- **Eager segment splitting**: `_SplitSegments` splits the normalized path into an `Array[String] val` once, and the trie walks it by index. Skips empty segments, normalizing double slashes.
- **Build/lookup separation**: Mutable `_BuildNode ref` tree for construction, frozen into immutable `_TreeNode val` tree for lookup. `freeze()` pre-computes accumulated interceptor arrays from root to each node, so lookup is zero-allocation.
- **Lookup priority: static > param > wildcard**: During lookup, static children are tried first, then the param child, then the wildcard. If a higher-priority branch fails (returns miss or method-not-allowed), lookup falls back to the next branch. A match from any branch is returned immediately. This priority means `/users/new` (static) beats `/users/:id` (param), and `/files/:id` (param) beats `/files/*path` (wildcard).
- **Trailing slash normalization**: `/users/` and `/users` match the same route.
- **Double slash normalization**: `_SplitSegments` skips empty segments, so `//` collapses to `/`. Matches the security consensus (nginx, Apache, Go, Rails, Phoenix all normalize).
- **Group info preservation**: Route groups are flattened into routes when consumed by `group()`, but group metadata (prefix + interceptors) is preserved separately as `_GroupInfo` entries. `Application.serve()` registers group interceptors on tree path nodes via `add_interceptors()`, and registers routes with per-route interceptors only via `add()`.
- **Overlapping group prefix rejection**: Two groups registering interceptors on the same prefix is a configuration error detected at `serve()` time via `_ValidateGroups`, returned as `ConfigError`.
- **Segment-level interceptor scoping**: In a segment trie, every child is at a segment boundary. Interceptors propagate unconditionally from parent to all children. `/api` and `/api-docs` are distinct children of the root — no leakage possible by construction.
- **Interval-based handler timeout**: Uses a repeating timer that checks a `_last_handler_activity` timestamp rather than cancel+recreate on every chunk. Avoids per-chunk timer allocation overhead during streaming.
- **Pipelined request buffering**: Requests arriving during `_HandlerInProgress` or `_Streaming` are buffered and drained when the handler completes.
- **HEAD via split handling**: `RequestHandler.start_streaming()` returns `BodyNotNeeded` for HEAD (local check). `_Connection` uses `is_head` when building buffered responses for the wire (suppresses body, preserves Content-Length).
- **HEAD→GET fallback**: When no explicit HEAD handler exists at a leaf, `_resolve_or_405` in `_TreeNode` checks the HEAD key first then falls back to GET — single traversal, no second lookup.
- **Backpressure forwarding**: `_Connection` forwards `on_throttled()`/`on_unthrottled()` to the handler actor when one is registered.
- **Directory index auto-serving**: When a request resolves to a directory, `ServeFiles` tries `index.html`. Content type is derived from the resolved filesystem path.
- **Request interceptors run before the handler**: Interceptors execute in `_Connection._dispatch` after route lookup. An interceptor short-circuit sends the response (with response interceptors applied) without creating the handler.
- **Interceptors run on 404s and 405s**: On a failed lookup, `_RouteMiss` carries accumulated interceptors from the deepest reached tree node. `_Connection` runs request interceptors (may short-circuit with 401/403) then sends 404 with response interceptors applied. `_MethodNotAllowed` carries interceptors and the allowed methods list — `_Connection` sends 405 with `Allow` header. App-level interceptors run on all error responses; group-level interceptors run on errors under their prefix.
- **Response interceptors run on all response paths**: Response interceptors run after the handler responds and before the wire. For routed requests, the pre-computed array from `_RouteMatch` is used. For 404s, the accumulated array from `_RouteMiss` is used. Exception: streaming timeout closes the connection directly.
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
  serve_result.pony           - Serving, ConfigError, ServeResult types (public)
  serve_files.pony            - ServeFiles handler factory (public)
  content_types.pony          - ContentTypes class + defaults (public)
  cookie_signing_key.pony     - CookieSigningKey class (public)
  signed_cookie.pony          - SignedCookie primitive (public)
  signed_cookie_error.pony    - SignedCookieError union type (public)
  _connection_protocol.pony   - Connection protocol trait (internal)
  _buffered_response.pony     - Response buffer for response interceptors (internal)
  _run_request_interceptors.pony - Request interceptor execution (internal)
  _run_response_interceptors.pony - Response interceptor execution (internal)
  _handler_timeout_notify.pony - Handler timeout timer notify (internal)
  _connection.pony             - Connection actor (internal)
  _listener.pony               - Listener actor (internal)
  _router.pony                 - Router + segment trie (internal)
  _route_match.pony            - Route match + route miss result types (internal)
  _route_definition.pony       - Route definition for building (internal)
  _method_entry.pony           - Per-method handler entry at tree leaf (internal)
  _group_info.pony             - Group metadata for tree building (internal)
  _file_streamer.pony          - Chunked file reader actor (internal)
  _file_target.pony            - File target trait (internal)
  _serve_files_handler.pony    - ServeFiles handler actor (internal)
  _http_date.pony              - RFC 7231 HTTP-date formatting (internal)
  _e_tag.pony                  - Weak ETag computation and matching (internal)
  _flatten.pony                - Segment splitting, path joining, array concatenation, overlap detection, prefix validation (internal)
  _unreachable.pony            - _Unreachable primitive (internal)
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
