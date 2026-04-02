interface tag HandlerReceiver
  """
  Lifecycle notifications from the connection to a handler actor.

  Structural typing — an actor just needs these three behaviors. No explicit
  `is HandlerReceiver` is required (but recommended for clarity).

  - `dispose()`: timeout fired or connection closing; stop work and clean up.
  - `throttled()`: TCP send buffer is full; pause chunk production.
  - `unthrottled()`: TCP send buffer drained; resume chunk production.
  """

  be dispose()

  be throttled()
    """
    TCP send buffer is full. Pause producing chunks until `unthrottled()`.
    """

  be unthrottled()
    """
    TCP send buffer drained. Resume producing chunks.
    """
