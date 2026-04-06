use stallion = "stallion"

primitive _RunRequestInterceptors
  """
  Run request interceptors in order on a request.

  Calls each interceptor and inspects the result. Stops on the first
  `InterceptRespond`. Returns the response if any interceptor short-circuited,
  or `None` if all passed.
  """
  fun apply(request: stallion.Request val,
    interceptors: (Array[RequestInterceptor val] val | None))
    : (InterceptRespond | None)
  =>
    match interceptors
    | let ints: Array[RequestInterceptor val] val =>
      var i: USize = 0
      while i < ints.size() do
        try
          match ints(i)?(request)
          | let respond: InterceptRespond => return respond
          end
        else
          _Unreachable()
        end
        i = i + 1
      end
    end
    None
