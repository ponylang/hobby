use stallion = "stallion"

class val _RouteDefinition
  """
  A route registration captured during route setup.

  Stores the HTTP method, path pattern, handler factory, and optional
  per-route response interceptor and request interceptor chains. Created by
  `Application` and `RouteGroup` route methods, then iterated by
  `Application.build()` to populate the router. Group-level and app-level
  interceptors are registered separately on tree nodes — the interceptors
  here are per-route only.
  """
  let method: stallion.Method
  let path: String
  let factory: HandlerFactory
  let response_interceptors: (Array[ResponseInterceptor val] val | None)
  let interceptors: (Array[RequestInterceptor val] val | None)

  new val create(
    method': stallion.Method,
    path': String,
    factory': HandlerFactory,
    response_interceptors': (Array[ResponseInterceptor val] val | None),
    interceptors': (Array[RequestInterceptor val] val | None) = None)
  =>
    method = method'
    path = path'
    factory = factory'
    response_interceptors = response_interceptors'
    interceptors = interceptors'
