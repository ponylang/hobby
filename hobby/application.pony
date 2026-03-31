use stallion = "stallion"
use lori = "lori"

class iso Application
  """
  The public API for the Hobby web framework.

  Register routes via `.>` method chaining (`get`, `post`, etc.), then call
  `serve()` to freeze the routes and start listening.

  ```pony
  use hobby = "hobby"
  use stallion = "stallion"
  use lori = "lori"

  actor Main
    new create(env: Env) =>
      let auth = lori.TCPListenAuth(env.root)
      hobby.Application
        .>get("/", {(ctx) =>
          hobby.RequestHandler(consume ctx)
            .respond(stallion.StatusOK, "Hello!")
        } val)
        .>get("/greet/:name", {(ctx) =>
          let handler = hobby.RequestHandler(consume ctx)
          try
            handler.respond(stallion.StatusOK,
              "Hello, " + handler.param("name")? + "!")
          else
            handler.respond(stallion.StatusBadRequest, "Bad Request")
          end
        } val)
        .serve(auth, stallion.ServerConfig("localhost", "8080"), env.out)
  ```

  Route methods are `fun ref` — automatic receiver recovery allows calling
  them on an `iso` receiver since all arguments are `val`. Use `.>` to chain
  route calls (it discards the method's return and passes the receiver
  through). Call `.serve()` last — it consumes the Application and freezes
  the routes.
  """
  embed _routes: Array[_RouteDefinition]
  embed _app_interceptors: Array[RequestInterceptor val]
  embed _app_response_interceptors: Array[ResponseInterceptor val]

  new iso create() =>
    _routes = Array[_RouteDefinition]
    _app_interceptors = Array[RequestInterceptor val]
    _app_response_interceptors = Array[ResponseInterceptor val]

  fun ref get(path: String, factory: HandlerFactory,
    interceptors: (Array[RequestInterceptor val] val | None) = None,
    response_interceptors: (Array[ResponseInterceptor val] val | None) = None)
  =>
    """Register a GET route."""
    _routes.push(
      _RouteDefinition(stallion.GET, path, factory, response_interceptors,
        interceptors))

  fun ref post(path: String, factory: HandlerFactory,
    interceptors: (Array[RequestInterceptor val] val | None) = None,
    response_interceptors: (Array[ResponseInterceptor val] val | None) = None)
  =>
    """Register a POST route."""
    _routes.push(
      _RouteDefinition(stallion.POST, path, factory, response_interceptors,
        interceptors))

  fun ref put(path: String, factory: HandlerFactory,
    interceptors: (Array[RequestInterceptor val] val | None) = None,
    response_interceptors: (Array[ResponseInterceptor val] val | None) = None)
  =>
    """Register a PUT route."""
    _routes.push(
      _RouteDefinition(stallion.PUT, path, factory, response_interceptors,
        interceptors))

  fun ref delete(path: String, factory: HandlerFactory,
    interceptors: (Array[RequestInterceptor val] val | None) = None,
    response_interceptors: (Array[ResponseInterceptor val] val | None) = None)
  =>
    """Register a DELETE route."""
    _routes.push(
      _RouteDefinition(stallion.DELETE, path, factory, response_interceptors,
        interceptors))

  fun ref patch(path: String, factory: HandlerFactory,
    interceptors: (Array[RequestInterceptor val] val | None) = None,
    response_interceptors: (Array[ResponseInterceptor val] val | None) = None)
  =>
    """Register a PATCH route."""
    _routes.push(
      _RouteDefinition(stallion.PATCH, path, factory, response_interceptors,
        interceptors))

  fun ref head(path: String, factory: HandlerFactory,
    interceptors: (Array[RequestInterceptor val] val | None) = None,
    response_interceptors: (Array[ResponseInterceptor val] val | None) = None)
  =>
    """Register a HEAD route."""
    _routes.push(
      _RouteDefinition(stallion.HEAD, path, factory, response_interceptors,
        interceptors))

  fun ref options(path: String, factory: HandlerFactory,
    interceptors: (Array[RequestInterceptor val] val | None) = None,
    response_interceptors: (Array[ResponseInterceptor val] val | None) = None)
  =>
    """Register an OPTIONS route."""
    _routes.push(
      _RouteDefinition(stallion.OPTIONS, path, factory, response_interceptors,
        interceptors))

  fun ref route(method: stallion.Method, path: String,
    factory: HandlerFactory,
    interceptors: (Array[RequestInterceptor val] val | None) = None,
    response_interceptors: (Array[ResponseInterceptor val] val | None) = None)
  =>
    """Register a route with an arbitrary HTTP method."""
    _routes.push(
      _RouteDefinition(method, path, factory, response_interceptors,
        interceptors))

  fun ref add_request_interceptor(interceptor: RequestInterceptor val) =>
    """
    Add an application-level request interceptor.

    Request interceptors run before the handler on every route. Application
    interceptors run before group interceptors, which run before per-route
    interceptors. The first interceptor that returns `InterceptRespond` rejects
    the request — the handler is never created.
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

    The group's prefix, interceptors, and response interceptors are applied to
    each of its routes. The group is consumed — no further registration on it
    is possible.
    """
    let g_ref: RouteGroup ref = consume g
    g_ref._flatten_into(_routes)

  fun iso serve(auth: lori.TCPListenAuth, config: stallion.ServerConfig,
    out: OutStream,
    handler_timeout: (U64 | None) = 30_000)
  =>
    """
    Freeze routes and start listening for HTTP connections.

    Consumes the Application — no further route registration is possible
    after this call.

    `handler_timeout` is the handler inactivity timeout in milliseconds.
    Defaults to 30 seconds. Pass `None` to disable the timeout. When a
    handler fails to respond within the timeout, the framework sends 504
    Gateway Timeout (or closes the connection for active streams).
    """
    let self: Application ref = consume this

    // Build app-level request interceptors as a val array (or None if empty)
    let app_interceptors: (Array[RequestInterceptor val] val | None) =
      if self._app_interceptors.size() > 0 then
        let gs_iso: Array[RequestInterceptor val] iso =
          recover iso Array[RequestInterceptor val] end
        for g in self._app_interceptors.values() do
          gs_iso.push(g)
        end
        consume gs_iso
      else
        None
      end

    // Build app-level response interceptors as a val array (or None if empty)
    let app_response_interceptors:
      (Array[ResponseInterceptor val] val | None) =
      if self._app_response_interceptors.size() > 0 then
        let ri_iso: Array[ResponseInterceptor val] iso =
          recover iso Array[ResponseInterceptor val] end
        for ri in self._app_response_interceptors.values() do
          ri_iso.push(ri)
        end
        consume ri_iso
      else
        None
      end

    let builder = _RouterBuilder
    for r in self._routes.values() do
      let combined_interceptors =
        _ConcatInterceptors(app_interceptors, r.interceptors)
      let combined_response_interceptors =
        _ConcatResponseInterceptors(app_response_interceptors,
          r.response_interceptors)
      builder.add(r.method, r.path, r.factory, combined_response_interceptors,
        combined_interceptors)
    end
    let router: _Router val = builder.build()

    // Convert millisecond timeout to nanoseconds
    let timeout_ns: U64 = match handler_timeout
    | let ms: U64 => ms * 1_000_000
    else
      0
    end

    _Listener(auth, config, router, out, timeout_ns,
      app_response_interceptors)
