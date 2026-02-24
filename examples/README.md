# Examples

Each subdirectory is a self-contained Pony program demonstrating a different part of the Hobby framework. Ordered from simplest to most involved.

## [hello](hello/)

Starts an HTTP server with two routes: a static greeting at `/` and a parameterized greeting at `/greet/:name`. Demonstrates `Application` route registration with `.>` chaining, `Handler` implementations, and route parameter extraction via `ctx.param()`. Start here if you're new to the library.

## [middleware](middleware/)

Starts an HTTP server with public and protected routes. Demonstrates two middleware patterns: an auth middleware that short-circuits with 401 in the `before` phase when a token is missing, and a logging middleware that records requests in the `after` phase. Also shows the typed accessor convention for inter-middleware communication — `AuthData.user()` extracts domain types (`AuthenticatedUser` or `NotAuthenticated`) from the context data map, avoiding raw string-key lookups.

## [route-groups](route-groups/)

Starts an HTTP server with grouped routes sharing prefixes and middleware. Demonstrates application-level middleware (logging on every route), a `/api` group with auth middleware, and a nested `/api/admin` group that adds admin middleware on top. Shows the complete middleware composition order: application middleware runs first, then group middleware, then per-route middleware.

## [serve-files](serve-files/)

Serves static files from a `public/` directory using the built-in `ServeFiles` handler. Demonstrates mounting a file-serving route with a `*filepath` wildcard parameter and creating the root `FilePath` from `FileAuth`. Includes sample HTML and CSS files. Responses include caching headers (ETag, Last-Modified, Cache-Control) and support conditional requests (304 Not Modified).

## [streaming](streaming/)

Streaming responses with chunked transfer encoding. A handler starts a stream and passes the sender to a producer actor that sends chunks asynchronously. Also demonstrates falling back to a non-streaming response when the client doesn't support chunked encoding (`ChunkedNotSupported`) and handling HEAD requests via `BodyNotNeeded`.
