// in your code this `use` statement would be:
// use hobby = "hobby"
use hobby = "../../hobby"
use stallion = "stallion"
use lori = "lori"

actor Main
  """
  Route groups example.

  Demonstrates route grouping with shared prefixes and middleware:
  - Application-level middleware (logging) runs on every route.
  - A `/api` group with auth middleware protects its routes.
  - A nested `/api/admin` group adds admin middleware on top of auth.
  - Routes registered directly on the Application have no group middleware.

  Routes:
  - GET /              -> public, app middleware only
  - GET /health        -> public, app middleware only
  - GET /api/users     -> auth middleware
  - GET /api/users/:id -> auth middleware
  - GET /api/admin/dashboard -> auth + admin middleware

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

    let log_mw: Array[hobby.Middleware val] val =
      recover val [as hobby.Middleware val: LogMiddleware(env.out)] end
    let auth_mw: Array[hobby.Middleware val] val =
      recover val [as hobby.Middleware val: AuthMiddleware] end
    let admin_mw: Array[hobby.Middleware val] val =
      recover val [as hobby.Middleware val: AdminMiddleware] end

    hobby.Application
      .>add_middleware(log_mw)
      .>get("/", {(ctx) =>
        hobby.RequestHandler(consume ctx)
          .respond(stallion.StatusOK, "Hello from Hobby!")
      } val)
      .>get("/health", {(ctx) =>
        hobby.RequestHandler(consume ctx)
          .respond(stallion.StatusOK, "OK")
      } val)
      .>group(
        hobby.RouteGroup("/api" where middleware = auth_mw)
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
            hobby.RouteGroup("/admin" where middleware = admin_mw)
              .>get("/dashboard", {(ctx) =>
                hobby.RequestHandler(consume ctx)
                  .respond(stallion.StatusOK, "Admin dashboard")
              } val)))
      .serve(auth, stallion.ServerConfig("0.0.0.0", "8080"), env.out)

// --- Middleware ---

class val AuthMiddleware is hobby.Middleware
  """Rejects requests without an Authorization header."""
  fun before(ctx: hobby.BeforeContext ref) =>
    match ctx.request().headers.get("authorization")
    | let _: String => None
    else
      ctx.respond(stallion.StatusUnauthorized, "Unauthorized")
    end

primitive AdminMiddleware is hobby.Middleware
  """Placeholder admin check — always passes."""
  fun before(ctx: hobby.BeforeContext ref) => None

class val LogMiddleware is hobby.Middleware
  """Logs the request method and path after handling."""
  let _out: OutStream
  new val create(out: OutStream) => _out = out

  fun before(ctx: hobby.BeforeContext ref) => None

  fun after(ctx: hobby.AfterContext ref) =>
    _out.print(
      ctx.request().method.string() + " " + ctx.request().uri.path)
