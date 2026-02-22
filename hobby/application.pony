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
        .>get("/", HelloHandler)
        .>get("/greet/:name", GreetHandler)
        .serve(auth, stallion.ServerConfig("localhost", "8080"), env.out)
  ```

  Route methods are `fun ref` — automatic receiver recovery allows calling
  them on an `iso` receiver since all arguments are `val`. Use `.>` to chain
  route calls (it discards the method's return and passes the receiver
  through). Call `.serve()` last — it consumes the Application and freezes
  the routes.
  """
  embed _routes: Array[_RouteDefinition]
  embed _app_middleware: Array[Middleware val]

  new iso create() =>
    _routes = Array[_RouteDefinition]
    _app_middleware = Array[Middleware val]

  fun ref get(path: String, handler: Handler,
    middleware: (Array[Middleware val] val | None) = None)
  =>
    """Register a GET route."""
    _routes.push(_RouteDefinition(stallion.GET, path, handler, middleware))

  fun ref post(path: String, handler: Handler,
    middleware: (Array[Middleware val] val | None) = None)
  =>
    """Register a POST route."""
    _routes.push(_RouteDefinition(stallion.POST, path, handler, middleware))

  fun ref put(path: String, handler: Handler,
    middleware: (Array[Middleware val] val | None) = None)
  =>
    """Register a PUT route."""
    _routes.push(_RouteDefinition(stallion.PUT, path, handler, middleware))

  fun ref delete(path: String, handler: Handler,
    middleware: (Array[Middleware val] val | None) = None)
  =>
    """Register a DELETE route."""
    _routes.push(_RouteDefinition(stallion.DELETE, path, handler, middleware))

  fun ref patch(path: String, handler: Handler,
    middleware: (Array[Middleware val] val | None) = None)
  =>
    """Register a PATCH route."""
    _routes.push(_RouteDefinition(stallion.PATCH, path, handler, middleware))

  fun ref head(path: String, handler: Handler,
    middleware: (Array[Middleware val] val | None) = None)
  =>
    """Register a HEAD route."""
    _routes.push(_RouteDefinition(stallion.HEAD, path, handler, middleware))

  fun ref options(path: String, handler: Handler,
    middleware: (Array[Middleware val] val | None) = None)
  =>
    """Register an OPTIONS route."""
    _routes.push(_RouteDefinition(stallion.OPTIONS, path, handler, middleware))

  fun ref route(method: stallion.Method, path: String, handler: Handler,
    middleware: (Array[Middleware val] val | None) = None)
  =>
    """Register a route with an arbitrary HTTP method."""
    _routes.push(_RouteDefinition(method, path, handler, middleware))

  fun ref add_middleware(middleware: Array[Middleware val] val) =>
    """
    Add application-level middleware that runs before every route's middleware.

    Can be called multiple times — middleware accumulates in registration order.
    Application middleware runs before group middleware, which runs before
    per-route middleware.
    """
    for m in middleware.values() do
      _app_middleware.push(m)
    end

  fun ref group(g: RouteGroup iso) =>
    """
    Consume a route group, flattening its routes into this application.

    The group's prefix and middleware are applied to each of its routes. The
    group is consumed — no further registration on it is possible.
    """
    let g_ref: RouteGroup ref = consume g
    g_ref._flatten_into(_routes)

  fun iso serve(auth: lori.TCPListenAuth, config: stallion.ServerConfig,
    out: OutStream)
  =>
    """
    Freeze routes and start listening for HTTP connections.

    Consumes the Application — no further route registration is possible
    after this call.
    """
    let self: Application ref = consume this

    // Build app-level middleware as a val array (or None if empty)
    let app_mw: (Array[Middleware val] val | None) =
      if self._app_middleware.size() > 0 then
        let mw_iso: Array[Middleware val] iso =
          recover iso Array[Middleware val] end
        for m in self._app_middleware.values() do
          mw_iso.push(m)
        end
        consume mw_iso
      else
        None
      end

    let builder = _RouterBuilder
    for r in self._routes.values() do
      let combined_mw = _ConcatMiddleware(app_mw, r.middleware)
      builder.add(r.method, r.path, r.handler, combined_mw)
    end
    let router: _Router val = builder.build()
    _Listener(auth, config, router, out)
