use stallion = "stallion"

primitive _RunBeforeMiddleware
  """
  Run middleware `before` phases on a `BeforeContext`.

  Forward phase: runs each middleware's `before` in order. A counter is
  incremented BEFORE calling `before` so that even a middleware that errors
  gets its `after` called. If any middleware responds (setting `is_handled()`)
  or errors without responding (triggering a 500), the forward phase stops.

  Returns the number of middleware invoked (needed by `_RunAfterMiddleware`).
  """
  fun apply(ctx: BeforeContext ref,
    middleware: (Array[Middleware val] val | None)): USize
  =>
    var invoked: USize = 0

    match middleware
    | let mw: Array[Middleware val] val =>
      var i: USize = 0
      while i < mw.size() do
        try
          let m = mw(i)?
          invoked = invoked + 1
          try
            m.before(ctx)?
          else
            if not ctx.is_handled() then
              ctx.respond(stallion.StatusInternalServerError,
                "Internal Server Error")
            end
          end
          if ctx.is_handled() then break end
        else
          _Unreachable()
        end
        i = i + 1
      end
    end

    invoked
