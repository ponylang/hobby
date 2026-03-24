# Examples

Each subdirectory is a self-contained Pony program demonstrating a different part of the Hobby framework. Ordered from simplest to most involved.

## [hello](hello/)

Starts an HTTP server with two routes: a static greeting at `/` and a parameterized greeting at `/greet/:name`. Demonstrates `Application` route registration with `.>` chaining, inline handler factories using `RequestHandler`, and route parameter extraction via `handler.param()`. Start here if you're new to the library.

## [async-handler](async-handler/)

Demonstrates actor-based handlers that do async work before responding. A `SlowService` actor simulates an async operation (e.g., a database query or external API call). The handler actor creates a `RequestHandler`, sends a query to the service, and responds when the result arrives. Shows the `HandlerReceiver` interface for lifecycle notifications.

## [middleware](middleware/)

Starts an HTTP server with public and protected routes. Demonstrates two middleware patterns: an auth middleware that short-circuits with 401 in the `before` phase when a token is missing, and a logging middleware that records requests in the `after` phase. Also shows the typed accessor pattern for inter-middleware communication — `handler.get[AuthenticatedUser]()` extracts domain types from the data map.

## [signed-cookie](signed-cookie/)

Signs and verifies cookie values using HMAC-SHA256 to prevent tampering. A visit counter cookie is signed on each response and verified on each request using `CookieSigningKey` and `SignedCookie`. Demonstrates key generation, the sign/verify round-trip, and integration with Stallion's `SetCookieBuilder` for secure cookie attributes.

## [route-groups](route-groups/)

Starts an HTTP server with grouped routes sharing prefixes and middleware. Demonstrates application-level middleware (logging on every route), a `/api` group with auth middleware, and a nested `/api/admin` group that adds admin middleware on top. Shows the complete middleware composition order: application middleware runs first, then group middleware, then per-route middleware.

## [serve-files](serve-files/)

Serves static files from a `public/` directory using the built-in `ServeFiles` handler factory. Demonstrates mounting a file-serving route with a `*filepath` wildcard parameter and creating the root `FilePath` from `FileAuth`. Includes sample HTML and CSS files plus a `docs/` subdirectory with an `index.html` that is served automatically when visiting `/static/docs/`. Responses include caching headers (ETag, Last-Modified, Cache-Control) and support conditional requests (304 Not Modified).

## [custom-content-types](custom-content-types/)

Serves static files with custom MIME type mappings for `.webp` and `.avif` image formats using `ContentTypes.add`. These extensions are not in the default set, so without overrides they would be served as `application/octet-stream`. Demonstrates how to extend the built-in content type mapping and pass it to `ServeFiles`.

## [streaming](streaming/)

Streaming responses with chunked transfer encoding. A handler actor starts a stream via `RequestHandler.start_streaming()` and sends chunks with `send_chunk()`. Demonstrates the `HandlerReceiver` interface, falling back to a non-streaming response for `ChunkedNotSupported`, and handling HEAD requests via `BodyNotNeeded`.
