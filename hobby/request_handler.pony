use "collections"
use stallion = "stallion"

class ref RequestHandler
  """

  The handler's interface to the connection.

  Embedded in a user's handler actor (or used inline). Hides the connection
  protocol and tracks response state to prevent double-response.

  For inline handlers, create a `RequestHandler`, call `respond()`, and let
  it go out of scope:

  ```pony
  {(ctx) =>
    hobby.RequestHandler(consume ctx).respond(stallion.StatusOK, "Hello!")
  } val
  ```

  For async handlers, embed it in an actor:

  ```pony
  actor MyHandler is hobby.HandlerReceiver
    embed _handler: hobby.RequestHandler

    new create(ctx: hobby.HandlerContext iso) =>
      _handler = hobby.RequestHandler(consume ctx)
      // ... start async work ...

    be result(value: String) =>
      _handler.respond(stallion.StatusOK, value)

    be dispose() => None
    be throttled() => None
    be unthrottled() => None
  ```
  """

  let _conn: _ConnectionProtocol tag
  let _token: U64
  let _request: stallion.Request val
  let _params: Map[String, String] val
  let _body: Array[U8] val
  let _is_head: Bool
  var _responded: Bool = false
  var _streaming: Bool = false

  new create(ctx: HandlerContext iso) =>
    """

    Create a handler from a consumed handler context.

    Extracts all request data and protocol references from the context.
    """

    _request = ctx.request
    _params = ctx.params
    _body = ctx.body
    _conn = ctx._get_conn()
    _token = ctx._get_token()
    _is_head = ctx._get_is_head()

  fun ref respond(status: stallion.Status, body': ByteSeq) =>
    """

    Send a complete response with the given status and body.

    Idempotent — the first call sends the response, subsequent calls are
    silently ignored. `Content-Length` is set automatically by the connection.
    For HEAD requests, the body is suppressed but `Content-Length` is preserved.
    """

    if not _responded then
      _responded = true
      _conn._handler_respond(_token, status, None, body')
    end

  fun ref respond_with_headers(
    status: stallion.Status,
    headers: stallion.Headers val,
    body': ByteSeq)
  =>
    """

    Send a complete response with explicit headers and body.

    The caller is responsible for including `Content-Length` or any other
    required headers. For HEAD requests, the body is suppressed but all
    headers are preserved.
    """

    if not _responded then
      _responded = true
      _conn._handler_respond(_token, status, headers, body')
    end

  fun ref start_streaming(status: stallion.Status,
    headers: (stallion.Headers val | None) = None)
    : (StreamingStarted | stallion.ChunkedNotSupported | BodyNotNeeded)
  =>
    """

    Begin a streaming response using chunked transfer encoding.

    Returns `StreamingStarted` on success, `ChunkedNotSupported` for
    HTTP/1.0 clients, or `BodyNotNeeded` for HEAD requests (the framework
    sends a headers-only response automatically).

    After `StreamingStarted`, call `send_chunk()` to send data and `finish()`
    to complete the stream. If already responded, returns `BodyNotNeeded`.

    For `ChunkedNotSupported`, `respond()` can still be called as a fallback.
    """

    if _responded then
      return BodyNotNeeded
    end
    if _is_head then
      _responded = true
      _conn._handler_respond(_token, status, headers, "")
      return BodyNotNeeded
    end
    if _request.version is stallion.HTTP10 then
      return stallion.ChunkedNotSupported
    end
    _responded = true
    _streaming = true
    _conn._handler_start_streaming(_token, status, headers)
    StreamingStarted

  fun ref send_chunk(data: ByteSeq) =>
    """

    Send a streaming chunk.

    Only effective after `start_streaming()` returned `StreamingStarted`.
    Silently ignored otherwise.
    """

    if _streaming then
      _conn._handler_send_chunk(_token, data)
    end

  fun ref finish() =>
    """

    End the streaming response.

    Sends the terminal chunk and signals completion. Only effective after
    `start_streaming()` returned `StreamingStarted`.
    """

    if _streaming then
      _streaming = false
      _conn._handler_finish(_token)
    end

  fun box param(key: String): String ? =>
    """

    Get a route parameter by name.

    Errors if the parameter does not exist. Parameter names come from route
    definitions — `:id` in `/users/:id` is accessed as `param("id")`.
    """

    _params(key)?

  fun box body(): Array[U8] val =>
    """
    Return the accumulated request body bytes.
    """
    _body

  fun box request(): stallion.Request val =>
    """
    Return the HTTP request.
    """
    _request

  fun box is_head(): Bool =>
    """
    Return `true` if this is a HEAD request.
    """
    _is_head
