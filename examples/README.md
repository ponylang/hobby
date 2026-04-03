# Examples

Each subdirectory is a self-contained Pony program demonstrating a different part of the Hobby framework. Ordered from simplest to most involved.

## [hello](hello/)

Starts an HTTP server with two routes: a static greeting at `/` and a parameterized greeting at `/greet/:name`. Demonstrates `Application` route registration with `.>` chaining, inline handler factories using `RequestHandler`, and route parameter extraction via `handler.param()`. Start here if you're new to the library.

## [https](https/)

Starts an HTTPS server on 0.0.0.0:8443 with the same two routes as the hello example, served over TLS using a self-signed certificate from the project's `assets/` directory. Demonstrates `Application.serve_ssl()` with `SSLContext` setup including certificate loading, authority configuration, and the `recover val` pattern for creating an immutable context.

## [async-handler](async-handler/)

Demonstrates actor-based handlers that do async work before responding. A `SlowService` actor simulates an async operation (e.g., a database query or external API call). The handler actor creates a `RequestHandler`, sends a query to the service, and responds when the result arrives. Shows the `HandlerReceiver` interface for lifecycle notifications.

## [request-interceptors](request-interceptors/)

Demonstrates request interceptors for synchronous request short-circuiting. Includes four interceptor implementations: auth header presence check, content type validation, request body size limit, and required headers. Shows per-route interceptor registration and combining multiple interceptors on a single route. These are request interceptors — they run before the handler is created and can reject a request outright.

## [response-interceptors](response-interceptors/)

Demonstrates response interceptors for post-handler response modification. Shows how `ResponseInterceptor` and `ResponseContext` allow inspecting and modifying outgoing responses — adding headers, rewriting status codes, or augmenting the body — after the handler has run but before the response reaches the client.

## [signed-cookie](signed-cookie/)

Signs and verifies cookie values using HMAC-SHA256 to prevent tampering. A visit counter cookie is signed on each response and verified on each request using `CookieSigningKey` and `SignedCookie`. Demonstrates key generation, the sign/verify round-trip, and integration with Stallion's `SetCookieBuilder` for secure cookie attributes.

## [route-groups](route-groups/)

Starts an HTTP server with grouped routes sharing a common prefix. Demonstrates a `/api` group with an auth request interceptor applied to every route in the group, and a nested `/api/admin` group that inherits the auth interceptor from the parent group. Shows how route groups compose prefixes and interceptors.

## [serve-files](serve-files/)

Serves static files from a `public/` directory using the built-in `ServeFiles` handler factory. Demonstrates mounting a file-serving route with a `*filepath` wildcard parameter and creating the root `FilePath` from `FileAuth`. Includes sample HTML and CSS files plus a `docs/` subdirectory with an `index.html` that is served automatically when visiting `/static/docs/`. Responses include caching headers (ETag, Last-Modified, Cache-Control) and support conditional requests (304 Not Modified).

## [custom-content-types](custom-content-types/)

Serves static files with custom MIME type mappings for `.webp` and `.avif` image formats using `ContentTypes.add`. These extensions are not in the default set, so without overrides they would be served as `application/octet-stream`. Demonstrates how to extend the built-in content type mapping and pass it to `ServeFiles`.

## [streaming](streaming/)

Streaming responses with chunked transfer encoding. A handler actor starts a stream via `RequestHandler.start_streaming()` and sends chunks with `send_chunk()`. Demonstrates the `HandlerReceiver` interface, falling back to a non-streaming response for `ChunkedNotSupported`, and handling HEAD requests via `BodyNotNeeded`.
