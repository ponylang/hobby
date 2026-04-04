## Reject segments after wildcard in route registration

Registering a route with segments after a wildcard (e.g., `/files/*path/extra`) previously dropped the trailing segments silently — the route would behave as if only `/files/*path` had been registered. This now produces a `ConfigError` at startup, so you'll see the misconfiguration immediately instead of getting surprising routing behavior at runtime.

## Reject empty param and wildcard names in route registration

Registering a route with a bare `:` or `*` (no name after the prefix character, e.g., `/users/:` or `/files/*`) previously accepted the route silently with an empty name. This caused the conflict detection to miss cases where a later route registered a named param or wildcard at the same position. Both bare `:` and bare `*` now produce a `ConfigError` at startup.

## Separate route compilation from server startup

Route validation and server startup are now separate steps. `Application.serve()` and `serve_ssl()` have been replaced by `Application.build()`, which validates routes and returns a `BuiltApplication`, and `Server`/`Server.ssl()`, which accepts the validated routes and starts listening. Lifecycle events (listening, bind failure, connection errors) are delivered through a `ServerNotify` interface instead of printing to an `OutStream`.

`Application` is now `class ref` instead of `class iso` — it's a builder that produces independent snapshots. You can add routes, call `build()`, add more routes, and build again.

The handler timeout parameter is now a `HandlerTimeout` constrained type (constructed via `MakeHandlerTimeout`) instead of a raw `U64`. Invalid values (zero, overflow) are caught at construction time. `DefaultHandlerTimeout()` provides the default 30-second timeout.

Before:

```pony
actor Main
  new create(env: Env) =>
    let auth = lori.TCPListenAuth(env.root)
    match
      hobby.Application
        .> get("/", handler)
        .serve(
          auth,
          stallion.ServerConfig("0.0.0.0", "8080"),
          env.out)
    | let err: hobby.ConfigError =>
      env.err.print(err.message)
    end
```

After:

```pony
actor Main is hobby.ServerNotify
  let _env: Env

  new create(env: Env) =>
    _env = env
    let auth = lori.TCPListenAuth(env.root)
    let app = hobby.Application
      .> get("/", handler)

    match \exhaustive\ app.build()
    | let built: hobby.BuiltApplication =>
      hobby.Server(
        auth, built, this
        where host = "0.0.0.0", port = "8080")
    | let err: hobby.ConfigError =>
      env.err.print(err.message)
    end

  be listening(
    server: hobby.Server,
    host: String,
    service: String)
  =>
    _env.out.print(
      "Listening on " + host + ":" + service)
```

For HTTPS, use `Server.ssl(auth, built, notify, sslctx where ...)` instead of `serve_ssl()`.

