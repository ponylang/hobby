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

class val _RouteMiss
  """
  Result of a failed route lookup.

  Carries accumulated request and response interceptors from the deepest
  node reached during traversal. This allows interceptors registered on
  group prefixes to run on 404 responses — e.g., an auth interceptor on
  `/api` can reject unauthenticated requests to `/api/nonexistent`.
  """
  let response_interceptors: (Array[ResponseInterceptor val] val | None)
  let interceptors: (Array[RequestInterceptor val] val | None)

  new val create(
    response_interceptors': (Array[ResponseInterceptor val] val | None),
    interceptors': (Array[RequestInterceptor val] val | None))
  =>
    response_interceptors = response_interceptors'
    interceptors = interceptors'

  fun _interceptor_count(): USize =>
    """
    Total interceptor count — used to compare miss depth.
    """
    let req_count =
      match interceptors
      | let a: Array[RequestInterceptor val] val => a.size()
      else
        0
      end
    let resp_count =
      match response_interceptors
      | let a: Array[ResponseInterceptor val] val => a.size()
      else
        0
      end
    req_count + resp_count

class val _MethodNotAllowed
  """
  Result of a lookup where the path exists but no handler matches the
  requested method.

  Carries the list of allowed methods (for the `Allow` response header)
  and accumulated interceptors from the matched path node. Interceptors
  still run on 405 responses — an auth interceptor should reject before
  revealing which methods are allowed.
  """
  let allowed_methods: Array[String] val
  let response_interceptors: (Array[ResponseInterceptor val] val | None)
  let interceptors: (Array[RequestInterceptor val] val | None)

  new val create(allowed_methods': Array[String] val,
    response_interceptors': (Array[ResponseInterceptor val] val | None),
    interceptors': (Array[RequestInterceptor val] val | None))
  =>
    allowed_methods = allowed_methods'
    response_interceptors = response_interceptors'
    interceptors = interceptors'
