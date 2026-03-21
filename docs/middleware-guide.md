# Writing Middleware

This guide walks through writing middleware for Hobby. It assumes you're comfortable with Pony and have read the [Quick Start](../README.md#usage) section. For API reference, see the [API documentation](https://ponylang.github.io/hobby).

## The Middleware Interface

Hobby's `Middleware` interface has two methods:

```pony
interface val Middleware
  fun before(ctx: BeforeContext ref) ?
  fun after(ctx: AfterContext ref) => None
```

`before` runs before the handler and is partial (`?`) — it can raise errors. `after` runs after the handler, has a default no-op implementation, and is not partial. Both are `val`, meaning middleware instances are immutable and shareable across connections. Middleware holds no per-request state; use the context for that.

`BeforeContext` and `AfterContext` are separate types. `BeforeContext` provides `respond()` for short-circuiting and `set()` for storing data. `AfterContext` provides access to the response (status, body, headers) and the original request, with `set_header()` and `add_header()` for modifying response headers. Both provide `request()` to access the request.

A minimal no-op middleware looks like this:

```pony
primitive NoOpMiddleware is hobby.Middleware
  fun before(ctx: hobby.BeforeContext ref) => None
```

Since `after` has a default implementation, you only need to provide `before`. And since `before` is declared partial in the interface, your implementation can choose to be partial (`?`) or not — Pony allows non-partial implementations to satisfy partial interface methods.

## The Execution Model

When a request hits a route with middleware, the framework runs a three-phase pipeline:

1. **Forward phase**: each middleware's `before` runs in order.
2. **Handler phase**: the handler factory runs.
3. **Reverse phase**: each middleware's `after` runs in reverse order.

Here's the normal flow for a chain of three middleware:

```text
MW-1.before
    ↓
MW-2.before
    ↓
MW-3.before
    ↓
  Handler
    ↓
MW-3.after
    ↓
MW-2.after
    ↓
MW-1.after
    ↓
Response sent
```

If any middleware short-circuits (by calling `ctx.respond()`) or errors during `before`, the forward phase stops — remaining middleware and the handler are skipped. But `after` always runs for every middleware whose `before` was invoked:

```text
MW-1.before
    ↓
MW-2.before  ← responds (short-circuits)
    ↓          (MW-3 and handler skipped)
MW-2.after
    ↓
MW-1.after
    ↓
Response sent
```

This guarantee means cleanup logic in `after` is always reliable — it won't be skipped by short-circuits or errors upstream.

## Short-Circuiting: Rejecting Requests

The most common middleware pattern is checking a precondition and rejecting the request if it fails. Here's an auth middleware built step by step.

Start with the check:

```pony
class val AuthMiddleware is hobby.Middleware
  fun before(ctx: hobby.BeforeContext ref) =>
    match ctx.request().headers.get("authorization")
    | let _: String =>
      None  // token present, continue the chain
    else
      ctx.respond(stallion.StatusUnauthorized, "Unauthorized")
    end
```

When `ctx.respond()` is called, it sets an internal "handled" flag. After `before` returns, the framework checks this flag. If set, the forward phase stops — no more middleware runs, and the handler is skipped. The chain proceeds directly to the `after` phases.

A few things to note:

**The current `before` runs to completion.** The chain stops *between* middleware invocations, not mid-execution. Calling `ctx.respond()` doesn't return or throw — your `before` body keeps executing until it returns normally or errors.

**First response wins.** `ctx.respond()` is idempotent: the first call sends the response, and subsequent calls are silently ignored.

**Checking handling status.** Downstream middleware can call `ctx.is_handled()` to check whether a prior middleware already buffered a response — useful for conditionally skipping work.

**Don't use `error` to reject requests.** If `before` errors without having called `ctx.respond()`, the framework treats it as an unexpected failure and sends a 500 Internal Server Error. Use `error` for genuine failures, not for intentional rejections.

## Passing Data to Handlers

Middleware often needs to pass data downstream — an authenticated user, a parsed request body, a rate limit counter. Hobby provides `ctx.set()` in the `before` phase for storing data, and `handler.get[]()` in the handler for retrieving it with type safety.

### Step 1: Raw set/get

```pony
// In middleware before phase:
ctx.set("auth_user", AuthenticatedUser("admin"))

// In handler:
let handler = hobby.RequestHandler(consume ctx)
let user = handler.get[AuthenticatedUser]("auth_user")?
```

The `set()` call stores the value under a string key. The `get[]()` call retrieves it with a type parameter, returning the typed value directly or raising an error if the key is missing or the type doesn't match.

### Step 2: Domain type

Define a proper type for the data:

```pony
class val AuthenticatedUser
  let name: String
  new val create(name': String) => name = name'
```

With a named type and the typed `get[]()` accessor, the handler code reads clearly:

```pony
let handler = hobby.RequestHandler(consume ctx)
let user = handler.get[AuthenticatedUser]("auth_user")?
handler.respond(stallion.StatusOK, "Welcome, " + user.name + "!")
```

The [middleware example](../examples/middleware/main.pony) demonstrates this complete pattern with `AuthMiddleware` and `AuthenticatedUser`.

## Error Handling

The framework handles errors in the `before` phase. Handler factories are not partial — handler actors manage their own errors.

**`before` errors without responding**: the framework sends 500 Internal Server Error automatically. This is the "something genuinely went wrong" case — a database connection failed, a required header couldn't be parsed, etc.

**`before` errors after responding**: the response that was already sent stands. The framework moves to the `after` phase without sending a 500, since a response is already buffered.

**Handler timeout**: if a handler actor fails to respond within the configured timeout (default 30 seconds), the framework sends 504 Gateway Timeout. For active streaming responses, the framework closes the connection instead. Pass `handler_timeout = None` to `Application.serve()` to disable the timeout.

**`after` is not partial**: `after` cannot raise errors. If your `after` logic might fail (e.g., writing to a log file), handle the failure internally. This is a design choice — `after` is for cleanup and post-processing, and it must always complete.

## Using `after` for Post-Processing

Some middleware only needs the reverse phase. A logging middleware, for example, has nothing to do before the handler — it just wants to record the request after handling completes:

```pony
class val LogMiddleware is hobby.Middleware
  let _out: OutStream
  new val create(out: OutStream) => _out = out

  fun before(ctx: hobby.BeforeContext ref) => None

  fun after(ctx: hobby.AfterContext ref) =>
    _out.print(
      ctx.request().method.string() + " " + ctx.request().uri.path)
```

Here's a CORS middleware that adds headers in the `after` phase:

```pony
class val CORSMiddleware is hobby.Middleware
  let _origin: String
  new val create(origin: String) => _origin = origin

  fun before(ctx: hobby.BeforeContext ref) => None

  fun after(ctx: hobby.AfterContext ref) =>
    ctx.set_header("Access-Control-Allow-Origin", _origin)
    ctx.set_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
```

A few things about `after`:

**Reverse order.** If middleware is registered as `[MW-1, MW-2, MW-3]`, `after` runs as MW-3, MW-2, MW-1. The first middleware to set up context is the last to clean it up.

**Always runs (with one exception).** `after` runs for every middleware whose `before` was invoked, regardless of whether the chain completed normally, short-circuited, or errored. The exception is forced connection closures — a streaming timeout or client disconnect tears down the TCP connection without running `after`, since there is no response to post-process.

**Response is buffered, not yet sent.** When `after` runs, the response is buffered in memory — it hasn't been written to the wire yet. This is what allows after-middleware to modify headers via `set_header()` and `add_header()`. The exception is streaming responses: headers are already on the wire, so header modifications are silently ignored (but `after` still runs for logging and cleanup).

**Holding `tag` references.** `LogMiddleware` stores `OutStream` (which is `tag`) in its constructor. This is fine — `tag` references carry no read/write capability, so they don't violate the `val` guarantee on the middleware class.

## Registering Middleware on Routes

Middleware is attached per-route through the `middleware` parameter on route methods:

```pony
let auth_mw: Array[hobby.Middleware val] val =
  recover val [as hobby.Middleware val: AuthMiddleware] end

hobby.Application
  .>get("/public", {(ctx) =>
    hobby.RequestHandler(consume ctx)
      .respond(stallion.StatusOK, "Public")
  } val)
  .>get("/private", {(ctx) =>
    hobby.RequestHandler(consume ctx)
      .respond(stallion.StatusOK, "Private")
  } val where middleware = auth_mw)
  .serve(auth, stallion.ServerConfig("localhost", "8080"), env.out)
```

The `recover val ... end` block is necessary because array literals are `ref` by default in Pony. Since middleware arrays are shared across connections, they must be `val` (immutable). The `recover val` block creates the array in a temporary mutable scope and lifts it to `val` at the boundary. The `as hobby.Middleware val:` inside the array literal sets the element type — without it, the compiler can't infer the interface type from concrete implementations.

When a route has multiple middleware, they execute in array order during the forward phase and reverse order during the `after` phase. Order matters — put auth checks before permission checks, and logging outermost if you want it to run regardless.

Middleware can also be applied at the group or application level. `RouteGroup` attaches middleware to all routes in the group, and `Application.add_middleware()` applies middleware to every route in the application. The execution order is: application middleware first, then group middleware, then per-route middleware. See the [route-groups example](../examples/route-groups/main.pony) for a complete demonstration.
