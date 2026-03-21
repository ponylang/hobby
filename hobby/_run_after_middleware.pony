primitive _RunAfterMiddleware
  """
  Run middleware `after` phases in reverse order on an `AfterContext`.

  Always runs for every middleware whose `before` was invoked — regardless
  of how the forward phase ended (normal, short-circuit, or error).
  """
  fun apply(ctx: AfterContext ref,
    middleware: (Array[Middleware val] val | None), invoked: USize)
  =>
    match middleware
    | let mw: Array[Middleware val] val =>
      if invoked > 0 then
        var j = invoked
        while j > 0 do
          j = j - 1
          try
            mw(j)?.after(ctx)
          else
            _Unreachable()
          end
        end
      end
    end
