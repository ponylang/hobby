class val _MethodEntry
  """
  A handler and its per-route interceptors for a specific HTTP method at a
  path node.

  Stored in method-keyed maps on tree nodes. The interceptors here are the
  final pre-computed arrays: accumulated path interceptors concatenated with
  per-route interceptors, computed at freeze time.
  """
  let factory: HandlerFactory
  let interceptors: (Array[RequestInterceptor val] val | None)
  let response_interceptors: (Array[ResponseInterceptor val] val | None)

  new val create(factory': HandlerFactory,
    interceptors': (Array[RequestInterceptor val] val | None),
    response_interceptors': (Array[ResponseInterceptor val] val | None))
  =>
    factory = factory'
    interceptors = interceptors'
    response_interceptors = response_interceptors'
