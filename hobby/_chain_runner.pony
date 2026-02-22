use stallion = "stallion"

primitive _ChainRunner
  """
  Execute a middleware chain around a handler.

  Forward phase: runs each middleware's `before` in order. If any middleware
  responds (setting `is_handled()`) or errors, the forward phase stops. A
  counter is incremented BEFORE calling `before` so that even a middleware
  that errors gets its `after` called.

  Handler: if the forward phase completes without a response, the handler
  runs. If the handler errors without responding, a 500 is sent.

  After phase: ALWAYS runs, in reverse order, for every middleware whose
  `before` was invoked — regardless of how the forward phase ended.
  """
  fun apply(ctx: Context ref, handler: Handler,
    middleware: (Array[Middleware val] val | None))
  =>
    var invoked: USize = 0

    match middleware
    | let mw: Array[Middleware val] val =>
      // Forward phase
      var i: USize = 0
      while i < mw.size() do
        try
          let m = mw(i)?
          invoked = invoked + 1
          try
            m.before(ctx)?
          else
            if not ctx.is_handled() then
              ctx.respond(stallion.StatusInternalServerError, "Internal Server Error")
            end
          end
          if ctx.is_handled() then break end
        else
          _Unreachable()
        end
        i = i + 1
      end
    end

    // Handler phase
    if not ctx.is_handled() then
      try
        handler(ctx)?
      end
      if not ctx.is_handled() then
        ctx.respond(stallion.StatusInternalServerError, "Internal Server Error")
      end
    end

    // After phase (always runs, reverse order)
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
