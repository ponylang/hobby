use "collections"
use stallion = "stallion"
use lori = "lori"

// A request stashed during an active streaming response: the HTTP request,
// its Stallion responder, and the accumulated body.
type _PendingRequest is (stallion.Request val, stallion.Responder, Array[U8] val)

actor _Connection is stallion.HTTPServerActor
  """
  Internal connection actor that handles a single HTTP connection.

  Implements Stallion's `HTTPServerActor` to receive HTTP events. Accumulates
  body chunks, looks up the matching route, and runs the middleware chain and
  handler via `_ChainRunner`.
  """
  var _http: stallion.HTTPServer = stallion.HTTPServer.none()
  let _router: _Router val
  var _body: Array[U8] iso = recover iso Array[U8] end
  var _has_body: Bool = false
  // Only one streaming response per connection at a time. Pipelined
  // requests arriving during streaming are buffered in _pending_requests
  // and drained when the stream finishes.
  var _streaming_responder: (stallion.Responder | None) = None
  embed _pending_requests: Array[_PendingRequest]

  new create(auth: lori.TCPServerAuth, fd: U32,
    config: stallion.ServerConfig, router: _Router val)
  =>
    _router = router
    _pending_requests = Array[_PendingRequest]
    _http = stallion.HTTPServer(auth, fd, this, config)

  fun ref _http_connection(): stallion.HTTPServer => _http

  be send_chunk(data: ByteSeq) =>
    match _streaming_responder
    | let r: stallion.Responder => r.send_chunk(data)
    end

  be finish() =>
    match _streaming_responder
    | let r: stallion.Responder =>
      r.finish_response()
      _streaming_responder = None
    end
    _drain_pending()

  fun ref on_body_chunk(data: Array[U8] val) =>
    _has_body = true
    _body.append(data)

  fun ref on_request_complete(request': stallion.Request val,
    responder: stallion.Responder)
  =>
    let body: Array[U8] val =
      if _has_body then
        _has_body = false
        (_body = recover iso Array[U8] end)
      else
        recover val Array[U8] end
      end

    if _streaming_responder isnt None then
      _pending_requests.push((request', responder, body))
    else
      _process_request(request', responder, body)
    end

  fun ref _process_request(request': stallion.Request val,
    responder: stallion.Responder, body: Array[U8] val)
  =>
    let path = request'.uri.path
    let route_match = match _router.lookup(request'.method, path)
    | let m: _RouteMatch => m
    else
      // HEAD falls back to GET handler when no explicit HEAD route exists
      if request'.method is stallion.HEAD then
        _router.lookup(stallion.GET, path)
      end
    end

    match route_match
    | let m: _RouteMatch =>
      let ctx = Context(request', responder, m.params, body, this)
      _ChainRunner(ctx, m.handler, m.middleware)
      if ctx.is_streaming() then
        _streaming_responder = responder
      end
    else
      if request'.method is stallion.HEAD then
        let response = stallion.ResponseBuilder(stallion.StatusNotFound)
          .add_header("Content-Length", "9")
          .finish_headers()
          .build()
        responder.respond(response)
      else
        let response = stallion.ResponseBuilder(stallion.StatusNotFound)
          .add_header("Content-Length", "9")
          .finish_headers()
          .add_chunk("Not Found")
          .build()
        responder.respond(response)
      end
    end

  fun ref _drain_pending() =>
    while (_streaming_responder is None) and (_pending_requests.size() > 0) do
      try
        (let req, let resp, let body) = _pending_requests.shift()?
        _process_request(req, resp, body)
      else
        _Unreachable()
      end
    end
