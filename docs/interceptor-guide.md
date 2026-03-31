# Writing Request Interceptors

Request interceptors short-circuit requests before the handler is created. If an interceptor responds, no handler actor is spawned — the response goes straight to the client. Use them for cheap synchronous checks: is the auth header present? Is the content type right? Is the body too large?

Anything that needs async work (verifying credentials against a database, loading session data) belongs in the handler actor, not an interceptor.

## The Interface

```pony
interface val RequestInterceptor
  fun apply(request: stallion.Request box): InterceptResult
```

An interceptor looks at the request and returns one of two things: `InterceptPass` to let it through, or `InterceptRespond` to short-circuit with a response. The return type is a union — `InterceptResult is (InterceptPass | InterceptRespond)` — so the compiler won't let you forget to decide.

Here's the simplest useful interceptor, an auth header check:

```pony
class val AuthInterceptor is hobby.RequestInterceptor
  fun apply(request: stallion.Request box): hobby.InterceptResult =>
    match request.headers.get("authorization")
    | let _: String => hobby.InterceptPass
    else
      hobby.InterceptRespond(stallion.StatusUnauthorized, "Unauthorized")
    end
```

Both paths are explicit method calls or constructor calls. There's no "do nothing to pass" — you return `InterceptPass` or you return `InterceptRespond`.

## Building Rejection Responses

`InterceptRespond` takes a status and body at construction. For most rejections, that's all you need:

```pony
hobby.InterceptRespond(stallion.StatusForbidden, "Forbidden")
```

When you need custom headers on the response, chain `set_header()` or `add_header()` calls:

```pony
hobby.InterceptRespond(stallion.StatusTooManyRequests, "Rate limited")
  .>set_header("retry-after", "60")
```

`set_header()` replaces any existing header with the same name (case-insensitive). `add_header()` appends without removing, which is what you want for multi-value headers like `Set-Cookie`. Both lowercase the header name.

If no custom headers are set, the framework auto-adds `Content-Length` from the body size. If you set any headers, you're responsible for `Content-Length` — same as `respond_with_headers()` on the handler.

## Interceptors Are `val`

Interceptors must be `val` — immutable and shareable across connections. They hold no per-request state. Configuration goes in constructor parameters:

```pony
class val ContentTypeInterceptor is hobby.RequestInterceptor
  let _expected: String

  new val create(expected: String) => _expected = expected

  fun apply(request: stallion.Request box): hobby.InterceptResult =>
    match request.headers.get("content-type")
    | let ct: String if ct == _expected => hobby.InterceptPass
    else
      hobby.InterceptRespond(stallion.StatusUnsupportedMediaType,
        "Unsupported Media Type")
    end
```

## Registering Interceptors

Interceptors attach to routes through the `interceptors` parameter:

```pony
let auth: Array[hobby.RequestInterceptor val] val =
  recover val [as hobby.RequestInterceptor val: AuthInterceptor] end

hobby.Application
  .>get("/public", public_handler)
  .>get("/private", private_handler where interceptors = auth)
```

The `recover val ... end` block lifts the array from `ref` to `val`. The `as hobby.RequestInterceptor val:` inside the literal sets the element type so the compiler knows the array holds interceptors, not concrete classes.

Multiple interceptors on the same route run in array order. The first one that returns `InterceptRespond` wins — the rest don't execute:

```pony
let upload_checks: Array[hobby.RequestInterceptor val] val =
  recover val
    [as hobby.RequestInterceptor val:
      AuthInterceptor
      ContentTypeInterceptor("application/json")
      MaxBodySizeInterceptor(1_048_576)]
  end

app.>post("/api/upload", upload_handler where interceptors = upload_checks)
```

If the auth check fails, the content type and body size checks never run.

### Route Groups

`RouteGroup` accepts interceptors in its constructor. Group interceptors run before per-route interceptors:

```pony
let api_interceptors: Array[hobby.RequestInterceptor val] val =
  recover val [as hobby.RequestInterceptor val: AuthInterceptor] end

let api = hobby.RouteGroup("/api" where interceptors = api_interceptors)
  .>get("/users", users_handler)
  .>get("/users/:id", user_handler)
app.>group(consume api)
```

Every route in the group gets the auth interceptor without repeating it.

### Application-Level Interceptors

`add_request_interceptor()` registers an interceptor that runs on every route:

```pony
app.>add_request_interceptor(RequiredHeadersInterceptor(
  recover val ["accept"] end))
```

The execution order is: application interceptors first, then group interceptors, then per-route interceptors.

## When to Use Interceptors vs. Handlers

Interceptors are for cheap, synchronous, stateless checks. The request either passes or it doesn't, and deciding shouldn't require talking to another actor.

If the check needs async work — querying a database, calling an external service, loading a session — it belongs in the handler actor. The handler can do async work, respond when it's ready, and has full type safety over its dependencies.

The dividing line: if you can decide by looking at the request headers alone, it's an interceptor. If you need to look anything up, it's handler logic.

See the [request-interceptors example](../examples/request-interceptors/main.pony) for a complete demonstration with four interceptor implementations.
