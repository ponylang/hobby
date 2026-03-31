## Add request interceptors for synchronous request short-circuiting

Request interceptors are a new way to short-circuit requests before the handler is created. Interceptors run synchronously in the connection — if an interceptor responds, no handler actor is spawned.

An interceptor returns `InterceptPass` to let the request through or `InterceptRespond` to short-circuit with an HTTP response. The return type forces an explicit decision — the compiler won't accept an interceptor that forgets to decide.

```pony
class val AuthInterceptor is hobby.RequestInterceptor
  fun apply(request: stallion.Request box): hobby.InterceptResult =>
    match request.headers.get("authorization")
    | let _: String => hobby.InterceptPass
    else
      hobby.InterceptRespond(stallion.StatusUnauthorized, "Unauthorized")
    end
```

`InterceptRespond` also supports `set_header()` and `add_header()` for custom response headers.

Register interceptors on routes, groups, or the application:

```pony
let auth_interceptor: Array[hobby.RequestInterceptor val] val =
  recover val [as hobby.RequestInterceptor val: AuthInterceptor] end

hobby.Application
  .>get("/public", public_handler)
  .>get("/api/data", data_handler where interceptors = auth_interceptor)
```

Application-level interceptors run before group interceptors, which run before per-route interceptors. The first interceptor that returns `InterceptRespond` wins.

## Add response interceptors for synchronous response modification

Response interceptors run after the handler responds but before the response hits the wire. They're the outbound counterpart to request interceptors: where request interceptors gate incoming requests, response interceptors modify outgoing responses.

A response interceptor implements `ResponseInterceptor` and receives a `ResponseContext ref` with full read/write access to the response. You can read or change the status, headers, and body. All registered interceptors run in forward order, every time. There's no short-circuiting because there's no decision to make — the response is already committed.

```pony
class val SecurityHeadersInterceptor is hobby.ResponseInterceptor
  fun apply(ctx: hobby.ResponseContext ref) =>
    ctx.set_header("x-content-type-options", "nosniff")
    ctx.set_header("x-frame-options", "DENY")
```

Register at the application, group, or route level:

```pony
hobby.Application
  .>add_response_interceptor(SecurityHeadersInterceptor)
  .>get("/cached", handler
    where response_interceptors = cache_interceptors)
```

App-level response interceptors also run on 404 responses where no route matched, so security headers and CORS headers cover error responses too.

For streaming responses, all mutations (`set_status()`, `set_header()`, `add_header()`, `set_body()`) are silently ignored since headers and status are already on the wire. The interceptor still runs, so logging interceptors work regardless of response type.

Content-Length is now computed automatically at serialization time from the final body, after all interceptors have run. If an interceptor calls `set_body()`, the Content-Length updates to match. If a Content-Length header is already present (from explicit user headers), the framework doesn't override it.

## Remove middleware in favor of interceptors

Middleware (`Middleware`, `BeforeContext`, `AfterContext`) is gone. The before-phase was already replaced by request interceptors in the previous release. The after-phase is now replaced by response interceptors.

The `Map[String, Any val]` data map on `HandlerContext` and `RequestHandler.get[T]()` are also removed. The data map let before-middleware pass typed values to handlers through a string-keyed map, but it was type-unsafe and solved a problem that doesn't exist in an actor-per-request framework. Handlers embed their dependencies directly and call typed services with full compile-time safety.

**Before:**

```pony
// Middleware set data for the handler
class val AuthMiddleware is hobby.Middleware
  fun before(ctx: hobby.BeforeContext ref) =>
    ctx.set("auth_user", AuthenticatedUser("admin"))

// Handler read from the data map
let user = handler.get[AuthenticatedUser]("auth_user")?
```

**After:**

```pony
// Handler owns its dependencies directly
actor MyHandler is hobby.HandlerReceiver
  embed _handler: hobby.RequestHandler

  new create(ctx: hobby.HandlerContext iso, auth: AuthService tag) =>
    _handler = hobby.RequestHandler(consume ctx)
    auth.verify(_handler.request().headers.get("authorization"), this)

  be auth_verified(user: User val) =>
    _handler.respond(stallion.StatusOK, "Welcome, " + user.name)
```

Cheap synchronous checks (header presence, content type, body size) that were in before-middleware belong in request interceptors. Response header modification (CORS, security headers, logging) that was in after-middleware belongs in response interceptors.

The `middleware` parameter on route methods and `RouteGroup` is removed; use `interceptors` for request interceptors and `response_interceptors` for response interceptors.
