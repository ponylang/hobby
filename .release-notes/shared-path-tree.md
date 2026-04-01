## Interceptors now run on 404 and 405 responses under their path

Group-level and application-level interceptors now run on 404 and 405 responses when the request path traverses through their prefix. Previously, only app-level response interceptors ran on 404s — group interceptors were skipped because the per-method tree had no path context for failed lookups, and 405 was not distinguished from 404.

This enables the auth use case: an auth request interceptor on `/api` now rejects unauthenticated requests to `/api/nonexistent` with 401/403 instead of leaking API structure with 404. A CORS response interceptor on `/api` now adds headers to error responses under `/api`.

The router now distinguishes 404 (path doesn't exist) from 405 (path exists, method not allowed). A 405 response includes an `Allow` header listing the methods the path supports. HEAD is implicitly allowed when GET is registered.

The router uses a single shared path tree instead of per-method trees. Interceptors are path-scoped and accumulate from root to leaf during traversal. On a 404, the deepest reached node's accumulated interceptors run — the same ones that would run on a successful match at that depth.

Per-method group interceptors (two groups with the same prefix but different methods and different interceptors) are no longer possible. This was an accidental capability of per-method trees, never a designed feature. Use per-route interceptors instead:

```pony
let api = hobby.RouteGroup("/api")
api.>get("/users", users_factory
  where interceptors = recover val [as hobby.RequestInterceptor val: CacheInterceptor] end)
api.>post("/users", create_user_factory
  where interceptors = recover val [as hobby.RequestInterceptor val: CsrfInterceptor] end)
```

`Application.serve()` now returns `ServeResult` — either `Serving` on success or `ConfigError` with a message describing the problem. Configuration errors (overlapping group prefixes, empty group prefix, special characters in group prefix, conflicting param names) are detected at `serve()` time and reported as data instead of panicking:

```pony
match
  hobby.Application
    .>get("/", handler)
    .serve(auth, config, env.out)
| let err: hobby.ConfigError =>
  env.err.print(err.message)
end
```

Registering two groups with the same prefix, or using an empty or parameterized group prefix, produces a `ConfigError`.
