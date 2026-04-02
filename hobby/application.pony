use stallion = "stallion"
use lori = "lori"
use ssl_net = "ssl/net"

class iso Application
  """

  The public API for the Hobby web framework.

  Register routes via `.>` method chaining (`get`, `post`, etc.), then call
  `serve()` (HTTP) or `serve_ssl()` (HTTPS) to freeze the routes and start
  listening.

  ```pony
  use hobby = "hobby"
  use stallion = "stallion"
  use lori = "lori"

  actor Main
    new create(env: Env) =>
      let auth = lori.TCPListenAuth(env.root)
      match
        hobby.Application
          .> get("/", {(ctx) =>
            hobby.RequestHandler(consume ctx)
              .respond(stallion.StatusOK, "Hello!")
          } val)
          .> get("/greet/:name", {(ctx) =>
            let handler = hobby.RequestHandler(consume ctx)
            try
              handler.respond(stallion.StatusOK,
                "Hello, " + handler.param("name")? + "!")
            else
              handler.respond(stallion.StatusBadRequest, "Bad Request")
            end
          } val)
          .serve(auth, stallion.ServerConfig("localhost", "8080"), env.out)
      | let err: hobby.ConfigError =>
        env.err.print(err.message)
      end
  ```

  Route methods are `fun ref` — automatic receiver recovery allows calling
  them on an `iso` receiver since all arguments are `val`. Use `.>` to chain
  route calls (it discards the method's return and passes the receiver
  through). Call `.serve()` (HTTP) or `.serve_ssl()` (HTTPS) last — it
  consumes the Application and returns the routes.
  """

  embed _routes: Array[_RouteDefinition]
  embed _app_interceptors: Array[RequestInterceptor val]
  embed _app_response_interceptors: Array[ResponseInterceptor val]
  embed _group_infos: Array[_GroupInfo]

  new iso create() =>
    _routes = Array[_RouteDefinition]
    _app_interceptors = Array[RequestInterceptor val]
    _app_response_interceptors = Array[ResponseInterceptor val]
    _group_infos = Array[_GroupInfo]

  fun ref get(
    path: String,
    factory: HandlerFactory,
    interceptors:
      (Array[RequestInterceptor val] val | None) = None,
    response_interceptors:
      (Array[ResponseInterceptor val] val | None) = None)
  =>
    """
    Register a GET route.
    """
    _routes.push(
      _RouteDefinition(
        stallion.GET,
        path,
        factory,
        response_interceptors,
        interceptors))

  fun ref post(
    path: String,
    factory: HandlerFactory,
    interceptors:
      (Array[RequestInterceptor val] val | None) = None,
    response_interceptors:
      (Array[ResponseInterceptor val] val | None) = None)
  =>
    """
    Register a POST route.
    """
    _routes.push(
      _RouteDefinition(
        stallion.POST,
        path,
        factory,
        response_interceptors,
        interceptors))

  fun ref put(
    path: String,
    factory: HandlerFactory,
    interceptors:
      (Array[RequestInterceptor val] val | None) = None,
    response_interceptors:
      (Array[ResponseInterceptor val] val | None) = None)
  =>
    """
    Register a PUT route.
    """
    _routes.push(
      _RouteDefinition(
        stallion.PUT,
        path,
        factory,
        response_interceptors,
        interceptors))

  fun ref delete(
    path: String,
    factory: HandlerFactory,
    interceptors:
      (Array[RequestInterceptor val] val | None) = None,
    response_interceptors:
      (Array[ResponseInterceptor val] val | None) = None)
  =>
    """
    Register a DELETE route.
    """
    _routes.push(
      _RouteDefinition(
        stallion.DELETE,
        path,
        factory,
        response_interceptors,
        interceptors))

  fun ref patch(
    path: String,
    factory: HandlerFactory,
    interceptors:
      (Array[RequestInterceptor val] val | None) = None,
    response_interceptors:
      (Array[ResponseInterceptor val] val | None) = None)
  =>
    """
    Register a PATCH route.
    """
    _routes.push(
      _RouteDefinition(
        stallion.PATCH,
        path,
        factory,
        response_interceptors,
        interceptors))

  fun ref head(
    path: String,
    factory: HandlerFactory,
    interceptors:
      (Array[RequestInterceptor val] val | None) = None,
    response_interceptors:
      (Array[ResponseInterceptor val] val | None) = None)
  =>
    """
    Register a HEAD route.
    """
    _routes.push(
      _RouteDefinition(
        stallion.HEAD,
        path,
        factory,
        response_interceptors,
        interceptors))

  fun ref options(
    path: String,
    factory: HandlerFactory,
    interceptors:
      (Array[RequestInterceptor val] val | None) = None,
    response_interceptors:
      (Array[ResponseInterceptor val] val | None) = None)
  =>
    """
    Register an OPTIONS route.
    """
    _routes.push(
      _RouteDefinition(
        stallion.OPTIONS,
        path,
        factory,
        response_interceptors,
        interceptors))

  fun ref route(
    method: stallion.Method,
    path: String,
    factory: HandlerFactory,
    interceptors:
      (Array[RequestInterceptor val] val | None) = None,
    response_interceptors:
      (Array[ResponseInterceptor val] val | None) = None)
  =>
    """
    Register a route with an arbitrary HTTP method.
    """
    _routes.push(
      _RouteDefinition(
        method,
        path,
        factory,
        response_interceptors,
        interceptors))

  fun ref add_request_interceptor(interceptor: RequestInterceptor val) =>
    """

    Add an application-level request interceptor.

    Request interceptors run before the handler on every request. Application
    interceptors run before group interceptors, which run before per-route
    interceptors. The first interceptor that returns `InterceptRespond` rejects
    the request — the handler is never created.

    App-level interceptors also run on 404 responses where no route matched.
    """

    _app_interceptors.push(interceptor)

  fun ref add_response_interceptor(interceptor: ResponseInterceptor val) =>
    """

    Add an application-level response interceptor.

    Response interceptors run after the handler responds, before the response
    goes to the wire. Application interceptors run before group interceptors,
    which run before per-route interceptors. All interceptors run — there is
    no short-circuiting.

    App-level response interceptors also run on 404 responses where no route
    matched.
    """

    _app_response_interceptors.push(interceptor)

  fun ref group(g: RouteGroup iso) =>
    """

    Consume a route group, flattening its routes into this application.

    The group's prefix is applied to each of its routes. Group-level
    interceptors are preserved separately for tree building — they are
    registered on path nodes, not concatenated onto routes. The group is
    consumed — no further registration on it is possible.
    """

    (consume g)
      .> _collect_group_infos(_group_infos)
      .> _flatten_routes_into(_routes)

  fun iso serve(
    auth: lori.TCPListenAuth,
    config: stallion.ServerConfig,
    out: OutStream,
    handler_timeout: (U64 | None) = 30_000)
    : ServeResult
  =>
    """

    Freeze routes, validate configuration, and start listening over HTTP.

    Consumes the Application — no further route registration is possible
    after this call. Returns `Serving` on success or `ConfigError` if
    a configuration error was detected (overlapping group prefixes,
    invalid group prefix, conflicting param or wildcard names).

    `handler_timeout` is the handler inactivity timeout in milliseconds.
    Defaults to 30 seconds. Pass `None` to disable the timeout. When a
    handler fails to respond within the timeout, the framework sends 504
    Gateway Timeout (or closes the connection for active streams).

    For HTTPS, use `serve_ssl()` instead.
    """

    let self: Application ref = consume this
    match \exhaustive\ self._build(handler_timeout)
    | (let router: _Router val, let timeout_ns: U64) =>
      _Listener(auth, config, router, out, timeout_ns)
      Serving
    | let err: ConfigError => err
    end

  fun iso serve_ssl(
    auth: lori.TCPListenAuth,
    config: stallion.ServerConfig,
    out: OutStream,
    ssl_ctx: ssl_net.SSLContext val,
    handler_timeout: (U64 | None) = 30_000)
    : ServeResult
  =>
    """

    Freeze routes, validate configuration, and start listening over
    HTTPS.

    Identical to `serve()` except connections use TLS via the provided
    `SSLContext`. The context must be configured with a certificate and
    private key before calling this method. If the context is
    misconfigured (e.g., no certificate set), `serve_ssl()` still returns
    `Serving` but every connection will fail at TLS handshake time —
    these failures are logged as "Hobby: connection failed (SSL
    handshake)".

    Consumes the Application — no further route registration is possible
    after this call.
    """

    let self: Application ref = consume this
    match \exhaustive\ self._build(handler_timeout)
    | (let router: _Router val, let timeout_ns: U64) =>
      _Listener.ssl(
        auth, config, router, out, timeout_ns, ssl_ctx)
      Serving
    | let err: ConfigError => err
    end

  fun ref _build(
    handler_timeout: (U64 | None))
    : ((_Router val, U64) | ConfigError)
  =>
    // Validate group configuration before building
    match _ValidateGroups(_group_infos)
    | let err: ConfigError => return err
    end

    // Build app-level request interceptors as a val array (or None
    // if empty)
    let app_interceptors:
      (Array[RequestInterceptor val] val | None)
    =
      if _app_interceptors.size() > 0 then
        let gs_iso: Array[RequestInterceptor val] iso =
          recover iso Array[RequestInterceptor val] end
        for g in _app_interceptors.values() do
          gs_iso.push(g)
        end
        consume gs_iso
      else
        None
      end

    // Build app-level response interceptors as a val array (or None
    // if empty)
    let app_response_interceptors:
      (Array[ResponseInterceptor val] val | None)
    =
      if _app_response_interceptors.size() > 0 then
        let ri_iso: Array[ResponseInterceptor val] iso =
          recover iso Array[ResponseInterceptor val] end
        for ri in _app_response_interceptors.values() do
          ri_iso.push(ri)
        end
        consume ri_iso
      else
        None
      end

    let builder = _RouterBuilder

    // Register app-level interceptors on the root node
    builder.add_interceptors(
      "", app_interceptors, app_response_interceptors)

    // Register group-level interceptors on their prefix nodes
    for gi in _group_infos.values() do
      builder.add_interceptors(
        gi.prefix,
        gi.interceptors,
        gi.response_interceptors)
    end

    // Register routes with per-route interceptors only
    for r in _routes.values() do
      builder.add(
        r.method,
        r.path,
        r.factory,
        r.response_interceptors,
        r.interceptors)
    end

    // Check for tree-level errors (e.g., conflicting param or
    // wildcard names)
    match builder.first_error()
    | let err: ConfigError => return err
    end
    let router: _Router val = builder.build()

    // Convert millisecond timeout to nanoseconds
    let timeout_ns: U64 =
      match handler_timeout
      | let ms: U64 => ms * 1_000_000
      else
        0
      end

    (router, timeout_ns)
