# Examples

Each subdirectory is a self-contained Pony program demonstrating a different part of the Hobby framework. Ordered from simplest to most involved.

## [hello](hello/)

Starts an HTTP server with two routes: a static greeting at `/` and a parameterized greeting at `/greet/:name`. Demonstrates `Application` route registration with `.>` chaining, `Handler` implementations, and route parameter extraction via `ctx.param()`. Start here if you're new to the library.

## [middleware](middleware/)

Starts an HTTP server with public and protected routes. Demonstrates two middleware patterns: an auth middleware that short-circuits with 401 in the `before` phase when a token is missing, and a logging middleware that records requests in the `after` phase. Also shows the typed accessor convention for inter-middleware communication — `AuthData.user()` extracts domain types (`AuthenticatedUser` or `NotAuthenticated`) from the context data map, avoiding raw string-key lookups.
