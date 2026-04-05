use "constrained_types"

primitive HandlerTimeoutValidator is Validator[U64]
  """
  Validates that a handler timeout duration is within the allowed range.

  The minimum value is 1 millisecond. The maximum value is
  18,446,744,073,709 milliseconds (~213,503 days) — the largest value
  that can be converted to nanoseconds without overflowing U64.

  Used by `MakeHandlerTimeout` to construct `HandlerTimeout` values.
  """
  fun apply(value: U64): ValidationResult =>
    if value == 0 then
      recover val
        ValidationFailure(
          "handler timeout must be greater than zero")
      end
    elseif value > _max_millis() then
      recover val
        ValidationFailure(
          "handler timeout must be at most "
            + _max_millis().string()
            + " milliseconds")
      end
    else
      ValidationSuccess
    end

  fun _max_millis(): U64 =>
    """
    The maximum handler timeout in milliseconds. Values above this
    would overflow U64 when converted to nanoseconds internally.
    """
    U64.max_value() / 1_000_000

type HandlerTimeout is Constrained[U64, HandlerTimeoutValidator]
  """
  A validated handler timeout duration in milliseconds. The allowed
  range is 1 to 18,446,744,073,709 milliseconds (~213,503 days). The
  upper bound ensures the value can be safely converted to nanoseconds
  without overflowing U64.

  Construct with `MakeHandlerTimeout(milliseconds)`, which returns
  `(HandlerTimeout | ValidationFailure)`. Pass to `Server` or
  `Server.ssl` to set the timeout, or pass `None` to disable it.
  """

type MakeHandlerTimeout is
  MakeConstrained[U64, HandlerTimeoutValidator]
  """
  Factory for `HandlerTimeout` values. Returns
  `(HandlerTimeout | ValidationFailure)`.
  """

primitive DefaultHandlerTimeout
  """
  Returns the default handler timeout of 30 seconds (30,000 ms).
  """

  fun apply(): (HandlerTimeout | None) =>
    match MakeHandlerTimeout(30_000)
    | let t: HandlerTimeout => t
    else
      _Unreachable()
      None
    end
