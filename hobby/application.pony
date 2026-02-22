use stallion = "stallion"
use lori = "lori"

class iso Application
  """
  The public API for the Hobby web framework.

  Register routes via `.>` method chaining (`get`, `post`, etc.), then call
  `serve()` to freeze the routes and start listening for connections.

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

  new iso create() =>
    _routes = Array[_RouteDefinition]

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

  fun iso serve(auth: lori.TCPListenAuth, config: stallion.ServerConfig,
    out: OutStream)
  =>
    """
    Freeze routes and start listening for HTTP connections.

    Consumes the Application — no further route registration is possible
    after this call.
    """
    let self: Application ref = consume this
    let builder = _RouterBuilder
    for r in self._routes.values() do
      builder.add(r.method, r.path, r.handler, r.middleware)
    end
    let router: _Router val = builder.build()
    _Listener(auth, config, router, out)
