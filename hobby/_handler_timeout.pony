use "time"

class iso _HandlerTimeoutNotify is TimerNotify
  """
  Timer notify that sends `_handler_timeout(token)` to the connection on
  each interval fire.

  The connection checks whether the handler has been idle long enough to
  constitute a timeout. The interval-based approach avoids per-chunk timer
  allocation overhead during high-throughput streaming.
  """
  let _conn: _Connection tag
  let _token: U64

  new iso create(conn: _Connection tag, token: U64) =>
    _conn = conn
    _token = token

  fun ref apply(timer: Timer, count: U64): Bool =>
    _conn._handler_timeout(_token)
    true

  fun ref cancel(timer: Timer) => None
