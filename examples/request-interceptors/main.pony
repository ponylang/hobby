// in your code this `use` statement would be:
// use hobby = "hobby"
use hobby = "../../hobby"
use stallion = "stallion"
use lori = "lori"

actor Main is hobby.ServerNotify
  """
  Demonstrates request interceptors for synchronous request short-circuiting.

  Interceptors run before the handler is created. An interceptor returns
  `InterceptPass` to let the request through or `InterceptRespond` to
  short-circuit with a response — the compiler forces an explicit decision.

  Routes:
  - GET /              → always succeeds (no interceptors)
  - GET /api/:id       → requires Authorization header
  - POST /api/upload   → requires JSON content type, body under 1 MB
  - GET /admin         → requires X-Admin and Authorization headers

  """
  let _env: Env

  new create(env: Env) =>
    _env = env
    let auth = lori.TCPListenAuth(env.root)

    let auth_interceptor: Array[hobby.RequestInterceptor val] val =
      recover val [as hobby.RequestInterceptor val: AuthInterceptor] end

    let upload_interceptors: Array[hobby.RequestInterceptor val] val =
      recover val
        [ as hobby.RequestInterceptor val:
          AuthInterceptor
          ContentTypeInterceptor("application/json")
          MaxBodySizeInterceptor(1_048_576)]
      end

    let admin_interceptors: Array[hobby.RequestInterceptor val] val =
      recover val
        [ as hobby.RequestInterceptor val:
          AuthInterceptor
          RequiredHeadersInterceptor(
            recover val ["x-admin"] end)]
      end

    let app = hobby.Application
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
      .> post(
        "/api/upload",
        {(ctx) =>
          hobby.RequestHandler(consume ctx)
            .respond(stallion.StatusOK, "Upload accepted")
        } val
        where interceptors = upload_interceptors)
      .> get(
        "/admin",
        {(ctx) =>
          hobby.RequestHandler(consume ctx)
            .respond(stallion.StatusOK, "Admin dashboard")
        } val
        where interceptors = admin_interceptors)

    match \exhaustive\ app.build()
    | let built: hobby.BuiltApplication =>
      hobby.Server(
        auth, built, this
        where host = "localhost", port = "8080")
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

class val AuthInterceptor is hobby.RequestInterceptor
  """
  Rejects requests that lack an Authorization header.

  This is a cheap synchronous check — it only verifies the header is present,
  not that the credentials are valid. Real credential validation requires
  async work and belongs in the handler actor.
  """
  fun apply(request: stallion.Request box): hobby.InterceptResult =>
    match request.headers.get("authorization")
    | let _: String => hobby.InterceptPass
    else
      hobby.InterceptRespond(stallion.StatusUnauthorized, "Unauthorized")
    end

class val ContentTypeInterceptor is hobby.RequestInterceptor
  """
  Rejects requests whose Content-Type header doesn't match the expected value.
  """
  let _expected: String

  new val create(expected: String) => _expected = expected

  fun apply(request: stallion.Request box): hobby.InterceptResult =>
    match request.headers.get("content-type")
    | let ct: String if ct == _expected => hobby.InterceptPass
    else
      hobby.InterceptRespond(
        stallion.StatusUnsupportedMediaType,
        "Unsupported Media Type")
    end

class val MaxBodySizeInterceptor is hobby.RequestInterceptor
  """
  Rejects requests whose Content-Length exceeds a maximum size in bytes.
  """
  let _max: USize

  new val create(max: USize) => _max = max

  fun apply(request: stallion.Request box): hobby.InterceptResult =>
    match request.headers.get("content-length")
    | let cl: String =>
      try
        if cl.usize()? > _max then
          return hobby.InterceptRespond(
            stallion.StatusPayloadTooLarge,
            "Payload Too Large")
        end
      end
    end
    hobby.InterceptPass

class val RequiredHeadersInterceptor is hobby.RequestInterceptor
  """
  Rejects requests that are missing any of the required headers.
  """
  let _headers: Array[String] val

  new val create(headers: Array[String] val) => _headers = headers

  fun apply(request: stallion.Request box): hobby.InterceptResult =>
    for h in _headers.values() do
      if request.headers.get(h) is None then
        return hobby.InterceptRespond(
          stallion.StatusBadRequest,
          "Missing required header: " + h)
      end
    end
    hobby.InterceptPass
