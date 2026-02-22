use "collections"

class val _RouteMatch
  """
  Result of a successful route lookup.

  Contains the handler, optional middleware chain, and extracted route
  parameters. Produced by `_Router.lookup()` when a request path matches
  a registered route.
  """
  let handler: Handler
  let middleware: (Array[Middleware val] val | None)
  let params: Map[String, String] val

  new val create(handler': Handler, middleware': (Array[Middleware val] val | None),
    params': Map[String, String] val)
  =>
    handler = handler'
    middleware = middleware'
    params = params'
