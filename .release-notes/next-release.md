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

