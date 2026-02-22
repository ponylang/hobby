use "collections"
use stallion = "stallion"
use lori = "lori"

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

  new create(auth: lori.TCPServerAuth, fd: U32,
    config: stallion.ServerConfig, router: _Router val)
  =>
    _router = router
    _http = stallion.HTTPServer(auth, fd, this, config)

  fun ref _http_connection(): stallion.HTTPServer => _http

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

    let path = request'.uri.path
    match _router.lookup(request'.method, path)
    | let m: _RouteMatch =>
      let ctx = Context(request', responder, m.params, body)
      _ChainRunner(ctx, m.handler, m.middleware)
    else
      let response = stallion.ResponseBuilder(stallion.StatusNotFound)
        .add_header("Content-Length", "9")
        .finish_headers()
        .add_chunk("Not Found")
        .build()
      responder.respond(response)
    end
