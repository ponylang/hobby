// in your code this `use` statement would be:
// use hobby = "hobby"
use hobby = "../../hobby"
use stallion = "stallion"
use lori = "lori"

actor Main is hobby.ServerNotify
  """
  Response interceptors example.

  Demonstrates three response interceptor patterns:
  - **CORS**: adds Access-Control-Allow-Origin and related headers.
  - **Security headers**: adds X-Content-Type-Options, X-Frame-Options, and
    Strict-Transport-Security.
  - **Logging**: prints the request method, path, and response status after
    handling completes. Read-only — no header modification.

  All three are registered at the application level so they run on every
  response, including 404s.

  Routes:
  - GET /              -> public greeting
  - GET /api/:id       -> requires Authorization header (request interceptor)

  Try it:
    curl -v http://localhost:8080/
    curl -v http://localhost:8080/api/42
    curl -v http://localhost:8080/api/42 -H "Authorization: Bearer secret"
    curl -v http://localhost:8080/nonexistent
  """
  let _env: Env

  new create(env: Env) =>
    _env = env
    let auth = lori.TCPListenAuth(env.root)

    let auth_interceptor: Array[hobby.RequestInterceptor val] val =
      recover val [as hobby.RequestInterceptor val: AuthInterceptor] end

    let app = hobby.Application
      .> add_response_interceptor(CorsResponseInterceptor("*"))
      .> add_response_interceptor(SecurityHeadersInterceptor)
      .> add_response_interceptor(LogResponseInterceptor(env.out))
      .> get(
        "/",
        {(ctx) =>
          hobby.RequestHandler(consume ctx)
            .respond(stallion.StatusOK, "Hello from Hobby!")
        } val)
      .> get(
        "/api/:id",
        {(ctx) =>
          let handler = hobby.RequestHandler(consume ctx)
          try
            let id = handler.param("id")?
            handler.respond(
              stallion.StatusOK, "Resource: " + id)
          else
            handler.respond(
              stallion.StatusBadRequest, "Bad Request")
          end
        } val
        where interceptors = auth_interceptor)

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

  be listen_failed(
    server: hobby.Server,
    reason: String)
  =>
    _env.err.print(reason)

// --- Response interceptors ---
class val CorsResponseInterceptor is hobby.ResponseInterceptor
  """
  Adds CORS headers to every response.

  Captures the allowed origin at construction time. The interceptor is `val`
  and shareable across connections.
  """
  let _origin: String

  new val create(origin: String) => _origin = origin

  fun apply(ctx: hobby.ResponseContext ref) =>
    ctx.set_header("access-control-allow-origin", _origin)
    ctx.set_header(
      "access-control-allow-methods",
      "GET, POST, PUT, DELETE, OPTIONS")
    ctx.set_header(
      "access-control-allow-headers",
      "Content-Type, Authorization")

primitive SecurityHeadersInterceptor is hobby.ResponseInterceptor
  """
  Adds common security headers to every response.
  """
  fun apply(ctx: hobby.ResponseContext ref) =>
    ctx.set_header("x-content-type-options", "nosniff")
    ctx.set_header("x-frame-options", "DENY")
    ctx.set_header(
      "strict-transport-security",
      "max-age=31536000; includeSubDomains")

class val LogResponseInterceptor is hobby.ResponseInterceptor
  """
  Logs the request method, path, and response status after handling.

  A read-only interceptor — it doesn't modify the response. For streaming
  responses, the status is still available for logging even though header
  modifications would be no-ops.
  """
  let _out: OutStream

  new val create(out: OutStream) => _out = out

  fun apply(ctx: hobby.ResponseContext ref) =>
    _out.print(
      ctx.request().method.string() + " " + ctx.request().uri.path
        + " -> " + ctx.status().string())

// --- Request interceptor ---
class val AuthInterceptor is hobby.RequestInterceptor
  """
  Rejects requests that lack an Authorization header.
  """
  fun apply(request: stallion.Request box): hobby.InterceptResult =>
    match request.headers.get("authorization")
    | let _: String => hobby.InterceptPass
    else
      hobby.InterceptRespond(stallion.StatusUnauthorized, "Unauthorized")
    end
