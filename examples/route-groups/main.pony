// in your code this `use` statement would be:
// use hobby = "hobby"
use hobby = "../../hobby"
use stallion = "stallion"
use lori = "lori"

actor Main
  """
  Route groups example.

  Demonstrates route grouping with shared prefixes and interceptors:
  - A `/api` group with an auth interceptor protects its routes.
  - A nested `/api/admin` group inherits the auth interceptor.
  - Routes registered directly on the Application have no group interceptors.

  Routes:
  - GET /              -> public, no interceptors
  - GET /health        -> public, no interceptors
  - GET /api/users     -> auth interceptor
  - GET /api/users/:id -> auth interceptor
  - GET /api/admin/dashboard -> auth interceptor (inherited from /api group)

  Try it:
    curl http://localhost:8080/
    curl http://localhost:8080/health
    curl http://localhost:8080/api/users                         # 401
    curl -H "Authorization: Bearer secret" http://localhost:8080/api/users
    curl -H "Authorization: Bearer secret" http://localhost:8080/api/users/42
    curl -H "Authorization: Bearer secret" http://localhost:8080/api/admin/dashboard
  """
  new create(env: Env) =>
    let auth = lori.TCPListenAuth(env.root)

    let auth_interceptor: Array[hobby.RequestInterceptor val] val =
      recover val [as hobby.RequestInterceptor val: AuthInterceptor] end

    match
      hobby.Application
        .>get("/", {(ctx) =>
          hobby.RequestHandler(consume ctx)
            .respond(stallion.StatusOK, "Hello from Hobby!")
        } val)
        .>get("/health", {(ctx) =>
          hobby.RequestHandler(consume ctx)
            .respond(stallion.StatusOK, "OK")
        } val)
        .>group(
          hobby.RouteGroup("/api" where interceptors = auth_interceptor)
            .>get("/users", {(ctx) =>
              hobby.RequestHandler(consume ctx)
                .respond(stallion.StatusOK, "User list")
            } val)
            .>get("/users/:id", {(ctx) =>
              let handler = hobby.RequestHandler(consume ctx)
              try
                let id = handler.param("id")?
                handler.respond(stallion.StatusOK, "User " + id)
              else
                handler.respond(stallion.StatusBadRequest, "Bad Request")
              end
            } val)
            .>group(
              hobby.RouteGroup("/admin")
                .>get("/dashboard", {(ctx) =>
                  hobby.RequestHandler(consume ctx)
                    .respond(stallion.StatusOK, "Admin dashboard")
                } val)))
        .serve(auth, stallion.ServerConfig("0.0.0.0", "8080"), env.out)
    | let err: hobby.ConfigError =>
      env.err.print(err.message)
    end

// --- Request interceptor ---

class val AuthInterceptor is hobby.RequestInterceptor
  """Rejects requests without an Authorization header."""
  fun apply(request: stallion.Request box): hobby.InterceptResult =>
    match request.headers.get("authorization")
    | let _: String => hobby.InterceptPass
    else
      hobby.InterceptRespond(stallion.StatusUnauthorized, "Unauthorized")
    end
