use "collections"
use stallion = "stallion"

class ref Context
  """
  Request context passed to middleware and handlers.

  Provides access to the HTTP request, route parameters, accumulated request
  body, and a key-value data map for inter-middleware communication. Call
  `respond()` or `respond_with_headers()` to send a complete HTTP response,
  or `start_streaming()` to begin a chunked streaming response.

  For HEAD requests, the framework automatically suppresses response bodies
  while preserving headers (including `Content-Length`). Handlers do not need
  special HEAD logic — `respond()` and `respond_with_headers()` send
  headers only, and `start_streaming()` returns `BodyNotNeeded` instead of
  starting a stream.

  Mutation methods (`respond`, `respond_with_headers`, `start_streaming`, `set`)
  require `ref` access. Read-only methods (`param`, `body`, `get`, `is_handled`,
  `is_streaming`) require only `box` access. This split supports the typed accessor convention: middleware
  authors provide accessor primitives that take `Context box`, letting them
  read context data without requiring write access.
  """
  let request: stallion.Request val
  let _responder: stallion.Responder
  let _params: Map[String, String] val
  let _body: Array[U8] val
  let _conn: _Connection tag
  let _response_mode: _ResponseMode val
  embed _data: Map[String, Any val]
  var _handled: Bool = false
  var _streaming: Bool = false

  new create(
    request': stallion.Request val,
    responder': stallion.Responder,
    params': Map[String, String] val,
    body': Array[U8] val,
    conn': _Connection tag)
  =>
    request = request'
    _responder = responder'
    _params = params'
    _body = body'
    _conn = conn'
    _response_mode =
      if request'.method is stallion.HEAD then _HeadResponseMode
      else _StandardResponseMode
      end
    _data = Map[String, Any val]

  fun ref respond(status: stallion.Status, body': ByteSeq) =>
    """
    Send a complete response with the given status and body.

    Sets `Content-Length` automatically. If a response has already been sent,
    this call is silently ignored (the first response wins). For HEAD requests,
    the body is suppressed but `Content-Length` is preserved.
    """
    if not _handled then
      _handled = true
      let body_size: USize = match body'
      | let s: String val => s.size()
      | let a: Array[U8] val => a.size()
      end
      _response_mode.respond(_responder, status, body', body_size)
    end

  fun ref respond_with_headers(status: stallion.Status,
    headers: stallion.Headers val, body': ByteSeq)
  =>
    """
    Send a complete response with explicit headers and body.

    The caller is responsible for including `Content-Length` or any other
    required headers in `headers`. If a response has already been sent, this
    call is silently ignored. For HEAD requests, the body is suppressed but
    all headers are preserved.
    """
    if not _handled then
      _handled = true
      _response_mode.respond_with_headers(
        _responder, status, headers, body')
    end

  fun box is_handled(): Bool =>
    """Returns `true` if a response has already been sent."""
    _handled

  fun ref start_streaming(status: stallion.Status,
    headers: (stallion.Headers val | None) = None)
    : (StreamSender tag | stallion.ChunkedNotSupported | BodyNotNeeded) ?
  =>
    """
    Begin a streaming response using chunked transfer encoding.

    Returns `StreamSender tag` on success, `ChunkedNotSupported` if the
    client does not support chunked encoding (e.g., HTTP/1.0), or
    `BodyNotNeeded` for HEAD requests (the framework has already sent a
    headers-only response). Errors if a response has already been sent
    (programmer error).

    When `ChunkedNotSupported` is returned, `is_handled()` remains `false` and
    the handler can fall back to `ctx.respond()` for a non-streaming response.

    When `BodyNotNeeded` is returned, `is_handled()` is `true` — the handler
    should not start a producer. Existing handlers that don't match on
    `BodyNotNeeded` work correctly: in a statement-position match, unmatched
    cases silently fall through, so the handler does nothing (which is correct
    for HEAD).

    On success, sets `is_handled()` to `true` — no further `respond()` calls
    will take effect. Pass the returned sender to a producer actor. The
    producer calls `send_chunk()` to send data and `finish()` to terminate
    the stream.

    If the handler errors after a successful `start_streaming()`, the framework
    automatically sends the terminal chunk to prevent a hung connection.
    """
    if _handled then error end
    match _response_mode.start_streaming(
      _responder, status, headers, _conn)?
    | let sender: StreamSender tag =>
      _handled = true
      _streaming = true
      sender
    | BodyNotNeeded =>
      _handled = true
      BodyNotNeeded
    | stallion.ChunkedNotSupported =>
      stallion.ChunkedNotSupported
    end

  fun box is_streaming(): Bool =>
    """Returns `true` if a streaming response has been started."""
    _streaming

  fun ref _finish_streaming() =>
    """
    Send the terminal chunk to close an abandoned streaming response.

    Called by `_ChainRunner` when a handler or middleware errors after starting
    a stream. Package-private — not part of the public API.
    """
    _streaming = false
    _responder.finish_response()

  fun box param(key: String): String ? =>
    """
    Get a route parameter by name.

    Errors if the parameter does not exist. Parameter names come from route
    definitions — `:id` in `/users/:id` is accessed as `param("id")`.
    """
    _params(key)?

  fun box body(): Array[U8] val =>
    """Return the accumulated request body bytes."""
    _body

  fun ref set(key: String, value: Any val) =>
    """
    Store a value in the context data map.

    Middleware uses this to communicate with downstream middleware and
    handlers. Keys should be namespaced to the middleware (e.g.,
    `"basic_auth"`) to avoid collisions.
    """
    _data(key) = value

  fun box get(key: String): Any val ? =>
    """
    Retrieve a value from the context data map.

    Errors if the key does not exist. Middleware authors should provide typed
    accessor primitives that wrap this method with `match` to recover domain
    types.
    """
    _data(key)?
