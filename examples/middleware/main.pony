// in your code this `use` statement would be:
// use hobby = "hobby"
use hobby = "../../hobby"
use stallion = "stallion"
use lori = "lori"

actor Main
  """
  Middleware example.

  Demonstrates two middleware patterns:
  - **Logging**: `after` phase records the request after handling completes.
  - **Auth**: `before` phase short-circuits with 401 if the token is missing,
    or stores the authenticated user in context data for the handler to read.

  Routes:
  - GET /           -> public, no middleware
  - GET /dashboard  -> protected by AuthMiddleware, reads user from context
  - GET /health     -> public, logged by LogMiddleware

  Try it:
    curl http://localhost:8080/
    curl http://localhost:8080/dashboard                         # 401
    curl -H "Authorization: Bearer secret" http://localhost:8080/dashboard
    curl http://localhost:8080/health
  """
  new create(env: Env) =>
    let auth = lori.TCPListenAuth(env.root)
    let log_mw: Array[hobby.Middleware val] val =
      recover val [as hobby.Middleware val: LogMiddleware(env.out)] end
    let auth_mw: Array[hobby.Middleware val] val =
      recover val [as hobby.Middleware val: AuthMiddleware] end
    hobby.Application
      .>get("/", HelloHandler)
      .>get("/dashboard", DashboardHandler where middleware = auth_mw)
      .>get("/health", HealthHandler where middleware = log_mw)
      .serve(auth, stallion.ServerConfig("0.0.0.0", "8080"), env.out)

// --- Handlers ---

primitive HelloHandler is hobby.Handler
  fun apply(ctx: hobby.Context ref) =>
    ctx.respond(stallion.StatusOK, "Hello from Hobby!")

primitive HealthHandler is hobby.Handler
  fun apply(ctx: hobby.Context ref) =>
    ctx.respond(stallion.StatusOK, "OK")

primitive DashboardHandler is hobby.Handler
  """Reads the authenticated user set by AuthMiddleware."""
  fun apply(ctx: hobby.Context ref) ? =>
    let user = AuthData.user(ctx)?
    ctx.respond(stallion.StatusOK, "Welcome, " + user.name + "!")

// --- Auth middleware ---

class val AuthenticatedUser
  """Domain type representing an authenticated user."""
  let name: String
  new val create(name': String) => name = name'

primitive AuthData
  """
  Typed accessor for auth middleware context data.

  Middleware authors provide accessor primitives like this to give handlers
  type-safe access to context data via `match`, avoiding raw string-key
  lookups and `as` casts.
  """
  fun user(ctx: hobby.Context box): AuthenticatedUser ? =>
    match ctx.get("auth_user")?
    | let u: AuthenticatedUser => u
    else
      error
    end

class val AuthMiddleware is hobby.Middleware
  """
  Checks for a `Bearer` token in the Authorization header.

  If the token is present, stores an `AuthenticatedUser` in context data.
  If missing, short-circuits with 401 — the handler is never invoked, but
  `after` phases of preceding middleware still run.
  """
  fun before(ctx: hobby.Context ref) =>
    // In a real app, validate the token and look up the user
    match ctx.request.headers.get("authorization")
    | let _: String =>
      ctx.set("auth_user", AuthenticatedUser("admin"))
    else
      ctx.respond(stallion.StatusUnauthorized, "Unauthorized")
    end

// --- Logging middleware ---

class val LogMiddleware is hobby.Middleware
  """
  Logs the request method and path after handling completes.

  Demonstrates the `after` phase — it runs regardless of whether the handler
  succeeded, errored, or was short-circuited by earlier middleware.
  """
  let _out: OutStream
  new val create(out: OutStream) => _out = out

  fun before(ctx: hobby.Context ref) => None

  fun after(ctx: hobby.Context ref) =>
    _out.print(
      ctx.request.method.string() + " " + ctx.request.uri.path)
