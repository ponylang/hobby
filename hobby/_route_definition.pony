use stallion = "stallion"

class val _RouteDefinition
  """
  A route registration captured by `Application` before the router is built.

  Stores the HTTP method, path pattern, handler, and optional middleware chain.
  `Application.serve()` iterates these definitions to populate the router.
  """
  let method: stallion.Method
  let path: String
  let handler: Handler
  let middleware: (Array[Middleware val] val | None)

  new val create(method': stallion.Method, path': String, handler': Handler,
    middleware': (Array[Middleware val] val | None))
  =>
    method = method'
    path = path'
    handler = handler'
    middleware = middleware'
