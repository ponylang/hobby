use stallion = "stallion"

interface val RequestInterceptor
  """

  Synchronous request interceptor that runs before the handler is created.

  Interceptors inspect the request and return `InterceptPass` to let it
  through or `InterceptRespond` to short-circuit with an HTTP response.
  The return type forces an explicit decision — the compiler won't accept
  an interceptor that forgets to decide.

  Interceptors are `val` and must be stateless or capture only immutable
  configuration. They run synchronously in the connection actor, so they
  should do only cheap work (header checks, size limits). Expensive or
  async work belongs in the handler.
  """

  fun apply(request: stallion.Request box): InterceptResult
    """

    Evaluate the request. Return `InterceptPass` to continue to the handler,
    or `InterceptRespond` to short-circuit with a response.
    """

