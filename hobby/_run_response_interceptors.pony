primitive _RunResponseInterceptors
  """
  Run response interceptors in order on a ResponseContext.

  All interceptors run — there is no short-circuiting. Each interceptor
  sees the response as modified by previous interceptors.
  """
  fun apply(ctx: ResponseContext ref,
    interceptors: (Array[ResponseInterceptor val] val | None))
  =>
    match interceptors
    | let ints: Array[ResponseInterceptor val] val =>
      var i: USize = 0
      while i < ints.size() do
        try
          ints(i)?(ctx)
        else
          _Unreachable()
        end
        i = i + 1
      end
    end
