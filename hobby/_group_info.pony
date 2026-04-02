class val _GroupInfo
  """

  Group metadata preserved for tree building.

  Carries the fully-joined prefix and interceptors for a route group. Created
  during `Application.group()` / `RouteGroup.group()` and consumed by
  `Application.serve()` to tag intermediate tree nodes with group-level
  interceptors via `_RouterBuilder.add_interceptors()`.
  """

  let prefix: String
  let interceptors: (Array[RequestInterceptor val] val | None)
  let response_interceptors: (Array[ResponseInterceptor val] val | None)

  new val create(prefix': String,
    interceptors': (Array[RequestInterceptor val] val | None),
    response_interceptors': (Array[ResponseInterceptor val] val | None))
  =>
    prefix = prefix'
    interceptors = interceptors'
    response_interceptors = response_interceptors'
