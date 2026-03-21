use stallion = "stallion"

class val _RouteDefinition
  """
  A route registration captured during route setup.

  Stores the HTTP method, path pattern, handler factory, and optional
  middleware chain. Created by `Application` and `RouteGroup` route methods,
  then iterated by `Application.serve()` to populate the router.
  """
  let method: stallion.Method
  let path: String
  let factory: HandlerFactory
  let middleware: (Array[Middleware val] val | None)

  new val create(method': stallion.Method, path': String,
    factory': HandlerFactory,
    middleware': (Array[Middleware val] val | None))
  =>
    method = method'
    path = path'
    factory = factory'
    middleware = middleware'
