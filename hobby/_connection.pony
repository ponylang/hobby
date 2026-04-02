use "collections"
use "time"
use stallion = "stallion"
use lori = "lori"
use ssl_net = "ssl/net"

// Connection states
primitive _Idle
primitive _HandlerInProgress
primitive _Streaming

// A request stashed during an active handler or streaming response.
type _PendingRequest is
  (stallion.Request val, stallion.Responder, Array[U8] val)

actor _Connection is (stallion.HTTPServerActor & _ConnectionProtocol)
  """

  Internal connection actor that handles a single HTTP connection.

  Implements Stallion's `HTTPServerActor` to receive HTTP events and
  `_ConnectionProtocol` for handler→connection communication. Each request
  runs through: request interceptors (synchronous) → handler factory →
  handler actor (async) → response interceptors (synchronous) → wire.
  """

  var _http: stallion.HTTPServer = stallion.HTTPServer.none()
  let _router: _Router val
  let _timers: Timers tag
  let _timeout_ns: U64
  let _out: OutStream
  var _body: Array[U8] iso = recover iso Array[U8] end
  var _has_body: Bool = false
  var _current_token: U64 = 0
  var _handler: (HandlerReceiver tag | None) = None
  var _handler_timer: (Timer tag | None) = None
  var _state: (_Idle | _HandlerInProgress | _Streaming) = _Idle
  var _current_request: (stallion.Request val | None) = None
  var _current_responder: (stallion.Responder | None) = None
  var _current_response_interceptors:
    (Array[ResponseInterceptor val] val | None) = None
  var _last_handler_activity: U64 = 0
  var _streaming_status: (stallion.Status | None) = None
  var _is_head: Bool = false
  embed _pending_requests: Array[_PendingRequest]

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: stallion.ServerConfig,
    router: _Router val,
    timers: Timers tag,
    timeout_ns: U64,
    out: OutStream,
    ssl_ctx: (ssl_net.SSLContext val | None) = None)
  =>
    _router = router
    _timers = timers
    _timeout_ns = timeout_ns
    _out = out
    _pending_requests = Array[_PendingRequest]
    _http =
      match ssl_ctx
      | let ctx: ssl_net.SSLContext val =>
        stallion.HTTPServer.ssl(auth, ctx, fd, this, config)
      else
        stallion.HTTPServer(auth, fd, this, config)
      end

  fun ref _http_connection(): stallion.HTTPServer => _http

  // --- HTTP lifecycle callbacks ---
  fun ref on_body_chunk(data: Array[U8] val) =>
    _has_body = true
    _body.append(data)

  fun ref on_request_complete(
    request': stallion.Request val,
    responder: stallion.Responder)
  =>
    let body: Array[U8] val =
      if _has_body then
        _has_body = false
        (_body = recover iso Array[U8] end)
      else
        recover val Array[U8] end
      end

    if _state isnt _Idle then
      _pending_requests.push((request', responder, body))
    else
      _process_request(request', responder, body)
    end

  fun ref on_closed() =>
    // Cancel timer
    match _handler_timer
    | let t: Timer tag =>
      _timers.cancel(t)
      _handler_timer = None
    end
    // Dispose handler
    match _handler
    | let h: HandlerReceiver tag =>
      h.dispose()
      _handler = None
    end
    // Reset state
    _current_request = None
    _current_responder = None
    _current_response_interceptors = None
    _streaming_status = None
    _is_head = false
    _state = _Idle
    _pending_requests.clear()

  fun ref on_throttled() =>
    match _handler
    | let h: HandlerReceiver tag => h.throttled()
    end

  fun ref on_unthrottled() =>
    match _handler
    | let h: HandlerReceiver tag => h.unthrottled()
    end

  fun ref on_start_failure(reason: lori.StartFailureReason) =>
    match \exhaustive\ reason
    | lori.StartFailedSSL =>
      _out.print("Hobby: connection failed (SSL handshake)")
    end

  // --- Request processing ---
  fun ref _process_request(
    request': stallion.Request val,
    responder: stallion.Responder,
    body: Array[U8] val)
  =>
    let path = request'.uri.path
    let is_head = request'.method is stallion.HEAD

    // Single lookup — HEAD→GET fallback is handled inside the router
    match \exhaustive\ _router.lookup(request'.method, path)
    | let m: _RouteMatch =>
      _dispatch(request', responder, body, m, is_head)
    | let na: _MethodNotAllowed =>
      // Path exists but method not allowed — run interceptors then send 405
      match _RunRequestInterceptors(request', na.interceptors)
      | let respond: InterceptRespond =>
        let buf =
          _BufferedResponse._from_intercept_respond(
            respond, is_head)
        let ctx = ResponseContext._create(buf, request')
        _RunResponseInterceptors(ctx, na.response_interceptors)
        responder.respond(buf._build())
        return
      end
      let allow_value: String val =
        ", ".join(na.allowed_methods.values())
      let buf =
        _BufferedResponse._standard(
          stallion.StatusMethodNotAllowed,
          "Method Not Allowed",
          is_head)
      buf.headers.push(("allow", allow_value))
      let ctx = ResponseContext._create(buf, request')
      _RunResponseInterceptors(ctx, na.response_interceptors)
      responder.respond(buf._build())
    | let miss: _RouteMiss =>
      // Run request interceptors from the traversal — may short-circuit
      match _RunRequestInterceptors(request', miss.interceptors)
      | let respond: InterceptRespond =>
        let buf =
          _BufferedResponse._from_intercept_respond(
            respond, is_head)
        let ctx = ResponseContext._create(buf, request')
        _RunResponseInterceptors(ctx, miss.response_interceptors)
        responder.respond(buf._build())
        return
      end
      // No interceptor short-circuit — send 404 with accumulated response
      // interceptors
      let buf =
        _BufferedResponse._standard(
          stallion.StatusNotFound, "Not Found", is_head)
      let ctx = ResponseContext._create(buf, request')
      _RunResponseInterceptors(ctx, miss.response_interceptors)
      responder.respond(buf._build())
    end

  fun ref _dispatch(
    request': stallion.Request val,
    responder: stallion.Responder,
    body: Array[U8] val,
    m: _RouteMatch,
    is_head: Bool)
  =>
    // Run request interceptors — short-circuit before creating handler state
    match _RunRequestInterceptors(request', m.interceptors)
    | let respond: InterceptRespond =>
      let buf =
        _BufferedResponse._from_intercept_respond(
          respond, is_head)
      let ctx = ResponseContext._create(buf, request')
      _RunResponseInterceptors(ctx, m.response_interceptors)
      responder.respond(buf._build())
      return
    end

    // Create HandlerContext and call factory
    _current_token = _current_token + 1
    let token = _current_token
    _current_request = request'
    _current_responder = responder
    _current_response_interceptors = m.response_interceptors
    _is_head = is_head

    let conn_tag: _ConnectionProtocol tag = this

    let handler_ctx: HandlerContext iso =
      recover iso
        HandlerContext._create(
          request',
          m.params,
          body,
          conn_tag,
          token,
          is_head)
      end

    let handler_receiver = m.factory(consume handler_ctx)
    _handler = handler_receiver
    _state = _HandlerInProgress
    _last_handler_activity = Time.nanos()

    // Start timeout timer (if timeouts enabled)
    if _timeout_ns > 0 then
      let timer =
        Timer(
          _HandlerTimeoutNotify(this, token),
          _timeout_ns,
          _timeout_ns)
      let timer_tag: Timer tag = timer
      _handler_timer = timer_tag
      _timers(consume timer)
    end

  // --- Handler protocol behaviors ---
  be _handler_respond(
    token: U64,
    status: stallion.Status,
    headers: (stallion.Headers val | None),
    body': ByteSeq)
  =>
    if (_state isnt _HandlerInProgress) or (token != _current_token) then
      return
    end

    let buf =
      match headers
      | let h: stallion.Headers val =>
        _BufferedResponse._with_headers(
          status, h, body', _is_head)
      else
        _BufferedResponse._standard(status, body', _is_head)
      end

    _run_after_and_send(buf)

  be _handler_start_streaming(
    token: U64,
    status: stallion.Status,
    headers: (stallion.Headers val | None))
  =>
    if (_state isnt _HandlerInProgress) or (token != _current_token) then
      return
    end

    match _current_responder
    | let responder: stallion.Responder =>
      match \exhaustive\ responder.start_chunked_response(status, headers)
      | stallion.StreamingStarted =>
        _state = _Streaming
        _streaming_status = status
        _last_handler_activity = Time.nanos()
      | stallion.ChunkedNotSupported =>
        // Shouldn't happen — RequestHandler checked HTTP version
        let buf =
          _BufferedResponse._standard(
            stallion.StatusInternalServerError,
            "Internal Server Error",
            _is_head)
        _run_after_and_send(buf)
      | stallion.AlreadyResponded =>
        // Shouldn't happen — token validated
        None
      end
    end

  be _handler_send_chunk(token: U64, data: ByteSeq) =>
    if (_state isnt _Streaming) or (token != _current_token) then
      return
    end
    match _current_responder
    | let responder: stallion.Responder =>
      responder.send_chunk(data)
      _last_handler_activity = Time.nanos()
    end

  be _handler_finish(token: U64) =>
    if (_state isnt _Streaming) or (token != _current_token) then
      return
    end
    match _current_responder
    | let responder: stallion.Responder =>
      responder.finish_response()
    end

    let status =
      match _streaming_status
      | let s: stallion.Status => s
      else
        stallion.StatusOK
      end
    let buf =
      _BufferedResponse._streaming_complete(status, _is_head)
    _run_after_and_send(buf)

  be _handler_timeout(token: U64) =>
    if token != _current_token then return end
    if (_state isnt _HandlerInProgress)
      and (_state isnt _Streaming)
    then
      return
    end

    // Check if handler was actually idle long enough
    let now = Time.nanos()
    if (now - _last_handler_activity) < _timeout_ns then
      return
    end

    match _state
    | _HandlerInProgress =>
      // Send 504 Gateway Timeout
      let buf =
        _BufferedResponse._standard(
          stallion.StatusGatewayTimeout,
          "Gateway Timeout",
          _is_head)
      // Dispose handler before cleanup
      match _handler
      | let h: HandlerReceiver tag => h.dispose()
      end
      _handler = None
      _run_after_and_send(buf)
    | _Streaming =>
      // Can't send 504 mid-stream — close connection
      match _handler
      | let h: HandlerReceiver tag => h.dispose()
      end
      _handler = None
      _http.close()
      _cancel_timer()
      _current_request = None
      _current_responder = None
      _current_response_interceptors = None
      _streaming_status = None
      _is_head = false
      _state = _Idle
      _pending_requests.clear()
    end

  // --- Helpers ---
  fun ref _run_after_and_send(buf: _BufferedResponse ref) =>
    """

    Run response interceptors on the buffered response, send to wire,
    clean up.
    """

    match _current_request
    | let req: stallion.Request val =>
      let ctx = ResponseContext._create(buf, req)
      _RunResponseInterceptors(ctx, _current_response_interceptors)
    end
    if not buf.is_streaming then
      match _current_responder
      | let responder: stallion.Responder =>
        responder.respond(buf._build())
      end
    end
    _cancel_timer()
    _handler = None
    _current_request = None
    _current_responder = None
    _current_response_interceptors = None
    _streaming_status = None
    _is_head = false
    _state = _Idle
    _drain_pending()

  fun ref _cancel_timer() =>
    match _handler_timer
    | let t: Timer tag =>
      _timers.cancel(t)
      _handler_timer = None
    end

  fun ref _drain_pending() =>
    while (_state is _Idle) and (_pending_requests.size() > 0) do
      try
        (let req, let resp, let body) =
          _pending_requests.shift()?
        _process_request(req, resp, body)
      else
        _Unreachable()
      end
    end
