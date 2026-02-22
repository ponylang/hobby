# Writing Middleware

This guide walks through writing middleware for Hobby. It assumes you're comfortable with Pony and have read the [Quick Start](../README.md#usage) section. For API reference, see the [API documentation](https://ponylang.github.io/hobby).

## The Middleware Interface

Hobby's `Middleware` interface has two methods:

```pony
interface val Middleware
  fun before(ctx: Context ref) ?
  fun after(ctx: Context ref) => None
```

`before` runs before the handler and is partial (`?`) — it can raise errors. `after` runs after the handler, has a default no-op implementation, and is not partial. Both are `val`, meaning middleware instances are immutable and shareable across connections. Middleware holds no per-request state; use `Context` for that.

A minimal no-op middleware looks like this:

```pony
primitive NoOpMiddleware is hobby.Middleware
  fun before(ctx: hobby.Context ref) => None
```

Since `after` has a default implementation, you only need to provide `before`. And since `before` is declared partial in the interface, your implementation can choose to be partial (`?`) or not — Pony allows non-partial implementations to satisfy partial interface methods.

## The Execution Model

When a request hits a route with middleware, the framework runs a three-phase pipeline:

1. **Forward phase**: each middleware's `before` runs in order.
2. **Handler phase**: the handler runs.
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
  fun before(ctx: hobby.Context ref) =>
    match ctx.request.headers.get("authorization")
    | let _: String =>
      None  // token present, continue the chain
    else
      ctx.respond(stallion.StatusUnauthorized, "Unauthorized")
    end
```

When `ctx.respond()` is called, it sets an internal "handled" flag. After `before` returns, the framework checks this flag. If set, the forward phase stops — no more middleware runs, and the handler is skipped. The chain proceeds directly to the `after` phases.

A few things to note:

**The current `before` runs to completion.** The chain stops *between* middleware invocations, not mid-execution. Calling `ctx.respond()` doesn't return or throw — your `before` body keeps executing until it returns normally or errors.

**First response wins.** `ctx.respond()` is idempotent: the first call sends the response, and subsequent calls are silently ignored. You can check `ctx.is_handled()` if you need to know whether a response has already been sent.

**Don't use `error` to reject requests.** If `before` errors without having called `ctx.respond()`, the framework treats it as an unexpected failure and sends a 500 Internal Server Error. Use `error` for genuine failures, not for intentional rejections.

## Passing Data to Handlers

Middleware often needs to pass data downstream — an authenticated user, a parsed request body, a rate limit counter. Hobby provides `ctx.set()` and `ctx.get()` for this, but the raw API is loosely typed. Here's how to build up to the idiomatic pattern.

### Step 1: Raw set/get

```pony
// In middleware:
ctx.set("auth_user", AuthenticatedUser("admin"))

// In handler:
let user = ctx.get("auth_user")? as AuthenticatedUser
```

This works, but it's fragile. The key `"auth_user"` is a magic string duplicated between middleware and handler. The `get()` return type is `Any val`, so you need an `as` cast that can fail at runtime.

### Step 2: Domain type

Define a proper type for the data:

```pony
class val AuthenticatedUser
  let name: String
  new val create(name': String) => name = name'
```

This is better — you have a named type instead of a raw string — but the lookup is still untyped.

### Step 3: Typed accessor primitive

The idiomatic convention is to provide a primitive that encapsulates the lookup and type recovery:

```pony
primitive AuthData
  fun user(ctx: hobby.Context box): AuthenticatedUser ? =>
    match ctx.get("auth_user")?
    | let u: AuthenticatedUser => u
    else
      error
    end
```

Note that the accessor takes `Context box` (read-only access), not `ref`. This is deliberate — reading context data doesn't require mutation, and `box` makes that explicit in the type signature.

Now handlers use `AuthData.user(ctx)?` — a single call with a clear name, type-safe return, and no magic strings at the call site. The key string and type recovery are centralized in one place.

The [middleware example](../examples/middleware/main.pony) demonstrates this complete pattern with `AuthMiddleware`, `AuthenticatedUser`, and `AuthData`.

## Error Handling

The framework handles errors differently depending on where they occur and whether a response has already been sent:

**`before` errors without responding**: the framework sends 500 Internal Server Error automatically. This is the "something genuinely went wrong" case — a database connection failed, a required header couldn't be parsed, etc.

**`before` errors after responding**: the response that was already sent stands. The framework moves to the `after` phase without sending a 500, since a response is already on the wire.

**Handler errors without responding**: same as middleware — the framework sends 500.

**`after` is not partial**: `after` cannot raise errors. If your `after` logic might fail (e.g., writing to a log file), handle the failure internally. This is a design choice — `after` is for cleanup and post-processing, and it must always complete.

The general rule: if `error` happens at any point and no response has been sent yet, the framework sends 500. If a response was already sent, the error is absorbed and the chain continues to `after` phases.

## Using `after` for Post-Processing

Some middleware only needs the reverse phase. A logging middleware, for example, has nothing to do before the handler — it just wants to record the request after handling completes:

```pony
class val LogMiddleware is hobby.Middleware
  let _out: OutStream
  new val create(out: OutStream) => _out = out

  fun before(ctx: hobby.Context ref) => None

  fun after(ctx: hobby.Context ref) =>
    _out.print(
      ctx.request.method.string() + " " + ctx.request.uri.path)
```

A few things about `after`:

**Reverse order.** If middleware is registered as `[MW-1, MW-2, MW-3]`, `after` runs as MW-3, MW-2, MW-1. The first middleware to set up context is the last to clean it up.

**Always runs.** `after` runs for every middleware whose `before` was invoked, regardless of whether the chain completed normally, short-circuited, or errored.

**Response is always sent by the time `after` runs.** Either the handler responded, middleware short-circuited with a response, or the framework sent a 500 fallback. This means `ctx.respond()` in `after` is always a no-op (first response wins). Use `after` for reading request data, logging, or cleanup — not for sending responses.

**Holding `tag` references.** `LogMiddleware` stores `OutStream` (which is `tag`) in its constructor. This is fine — `tag` references carry no read/write capability, so they don't violate the `val` guarantee on the middleware class.

## Registering Middleware on Routes

Middleware is attached per-route through the `middleware` parameter on route methods:

```pony
let auth_mw: Array[hobby.Middleware val] val =
  recover val [as hobby.Middleware val: AuthMiddleware] end

hobby.Application
  .>get("/public", PublicHandler)
  .>get("/private", PrivateHandler where middleware = auth_mw)
  .serve(auth, stallion.ServerConfig("localhost", "8080"), env.out)
```

The `recover val ... end` block is necessary because array literals are `ref` by default in Pony. Since middleware arrays are shared across connections, they must be `val` (immutable). The `recover val` block creates the array in a temporary mutable scope and lifts it to `val` at the boundary. The `as hobby.Middleware val:` inside the array literal sets the element type — without it, the compiler can't infer the interface type from concrete implementations.

When a route has multiple middleware, they execute in array order during the forward phase and reverse order during the `after` phase. Order matters — put auth checks before permission checks, and logging outermost if you want it to run regardless.

Middleware is per-route, not global. There is currently no built-in mechanism for applying middleware to all routes at once. To share middleware across routes, define the array once and pass it to each route registration.
