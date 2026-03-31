use "collections"

class val _RouteMatch
  """
  Result of a successful route lookup.

  Contains the handler factory, optional response interceptor and request
  interceptor chains, and extracted route parameters. Produced by
  `_Router.lookup()` when a request path matches a registered route.
  """
  let factory: HandlerFactory
  let response_interceptors: (Array[ResponseInterceptor val] val | None)
  let interceptors: (Array[RequestInterceptor val] val | None)
  let params: Map[String, String] val

  new val create(factory': HandlerFactory,
    response_interceptors': (Array[ResponseInterceptor val] val | None),
    interceptors': (Array[RequestInterceptor val] val | None),
    params': Map[String, String] val)
  =>
    factory = factory'
    response_interceptors = response_interceptors'
    interceptors = interceptors'
    params = params'
