use "collections"

class val _RouteMatch
  """
  Result of a successful route lookup.

  Contains the handler factory, optional middleware chain, and extracted route
  parameters. Produced by `_Router.lookup()` when a request path matches
  a registered route.
  """
  let factory: HandlerFactory
  let middleware: (Array[Middleware val] val | None)
  let params: Map[String, String] val

  new val create(factory': HandlerFactory,
    middleware': (Array[Middleware val] val | None),
    params': Map[String, String] val)
  =>
    factory = factory'
    middleware = middleware'
    params = params'
